# Patch info

## How the patch works

The patch consists of these modifications:

1. The game has a counter for how many turn resets the player has available. In order to give unlimited turn resets, the patch prevents that counter from being decreased.

1. To bypass the confirmation dialogue when Reset Turn is clicked, the code that sets the variable used to check the result of the confirmation is replaced to instead set the variable used to trigger the event that resets the turn.

1. But the confirmation dialogue will still briefly flash. To prevent this, the code that creates the confirmation dialogue is bypassed altogether with an early return from the function.

## How the patch was created

#### Unlimited resets

1. First, I searched the Lua files for relevant strings:

   - `undoturn` is the console command
   - `reset turn` is the label in the UI

   The code handling the reset doesn't appear to be in Lua, but I found these strings to search in the binary:

   - `Button_UndoTurn`
   - `Button_UndoTurnUsed`

1. I opened the binary with Ghidra

1. Searching for `Button_UndoTurnUsed`, I found function `BoardPlayer::RenderEndTurn`

   - There was some logic in this function that evaluated RBX+0x451c; if that value was less than 1, it used the value `Button_UndoTurnUsed`, otherwise `Button_UndoTurn`

1. Next, I opened the game binary with gdb

   ```
   gdb Breach
   ```

1. I set a breakpoint on the line in RenderEndTurn evaluating RBX+0x451c and started the game

   ```
   break *0x008bdd81
   ```

   ```
   run
   ```

1. I started a battle in the game until gdb got to the breakpoint

1. Print the value of RBX+0x451c

   ```
   (gdb) print *(int*)($rbx + 0x451c)
   $3 = 1
   ```

1. Make sure RBX is a memory address

   ```
   (gdb) print/x $rbx
   $4 = 0x79d8a68
   ```

1. Set a watch point on RBX+0x451c

   ```
   set $watchaddr = $rbx + 0x451c
   ```

   ```
   watch *(int*)$watchaddr
   ```

1. Delete the previous breakpoint (or it will keep breaking, I guess the UI continually calls that function to render the UI)

   ```
   delete 1
   ```

1. Continue gdb

   ```
   c
   ```

1. Play through the game until the RESET TURN button appear can be clicked, then click it

1. Unfortunately the watch point value didn't change. It seems the address of RBX did, though:

   ```
   (gdb) print/x $rbx
   $13 = 0x76de038
   ```

   I also saw the thread exited and a new one was created:

   ```
   [New Thread 0x7fff9e62c6c0 (LWP 52382)]
   [Thread 0x7fff9e62c6c0 (LWP 52382) exited]
   ```

1. However, the value of RBX+0x451c did change, so that seemed to be correct:

   ```
   (gdb) print *(int*)($rbx + 0x451c)
   $4 = 0
   ```

1. Next, I used objdump to look at instructions involving `0x451c`:

   ```
   $ objdump -d Breach | grep 0x451c
     82b129:       e9 de b6 ff ff          jmp    82680c <glewInit+0x451c>
     8a58c4:       83 af 1c 45 00 00 01    subl   $0x1,0x451c(%rdi)
     8a58cb:       8b 87 1c 45 00 00       mov    0x451c(%rdi),%eax
   ```

   Right away, I saw `subl   $0x1,0x451c(%rdi)`; subtract 1!

1. Opening that address in Ghidra brought me to the function `BoardPlayer::UndoTurnUsed`; the first action is to decrement the value at 0x451c

So I wrote a patcher that modifies the instruction to subtract 0 instead of 1, and tested. Indeed, I now had unlimited turn resets.

#### Hide the confirmation dialogue

I noticed that clicking RESET TURN in the game caused a confirmation dialogue box to pop up, but using `undoturn` in the console did not. So I wanted to figure out how they were behaving differently in the code.

1. In Ghidra, I looked for the string `undoturn`. It's only used in one function: `Game::UpdateConsole`

   - In that function, if `undoturn` is entered, it does `Game::LoadGame("undoSave.lua")`

1. In Ghidra, I looked for other undo turn functions and I found `BoardPlayer::UndoTurn`

1. Run Breach with gdb

   ⓘ Technically I used `rr` so I could record the debugging and move forward and backwards without having to redo it over and over

1. I set breakpoints on various functions and then played with gdb running to figure out which functions were called

   - When using `undoturn` in the console, it's pretty straightforward as it calls `LoadGame` directly
   - When clicking the reset turn button, it was less straightforward
     - `BoardPlayer::UndoTurn` was called
     - At some point `LoadGame` was called
     - Then LoadGame calls UndoTurnUsed

1. I looked at `BoardPlayer::UndoTurn` in Ghidra

   - Unfortunately it does not call `LoadGame` directly, but instead it does some checks (`BoardPlayer::IsUndoTurnPossible`) and then creates the confirmation dialogue

   - But how is `LoadGame` called?

1. I did another debug, setting a break on `BoardPlayer::UndoTurn`. Once that was hit, I set a break on `Game::LoadGame` and did a backtrace:

   ```
   #0  0x00000000004f7be0 in Game::LoadGame(std::basic_string<char, std::char_traits<char>, std::allocator<char> >) ()
   #1  0x00000000004f9e83 in Game::OnLoop() ()
   #2  0x000000000047f65f in CApp::OnLoop() ()
   #3  0x0000000000481b98 in CApp::OnExecute() ()
   #4  0x000000000040cb57 in main ()
   ```

1. Examine `0x4f9e83` in Game::OnLoop

   - It seems LoadGame is called whenever the event `0x4d` is not set and the event `0xf` is set

1. I found a function `EventSystem::AddEvent` so I used that to look for where the events are set

   ```
   $ objdump -d --demangle Breach | grep -B 6 AddEvent | egrep -w '0xf|0x4d'
     67a825:       88 44 24 0f             mov    %al,0xf(%rsp)
     8c9cba:       be 0f 00 00 00          mov    $0xf,%esi
   ```

1. I examined the addresses in Ghidra

   - `0x8c9cba` is in `BoardPlayer::OnLoop`
   - It creates the event `0xf` when the flag at `0x4520` is not 0

1. Check for `0x4520`

   ```
   $ objdump -d --demangle Breach | grep -w 0x4520
     8c25a9:       c6 83 20 45 00 00 01    movb   $0x1,0x4520(%rbx)
     8c97bd:       80 bb 20 45 00 00 00    cmpb   $0x0,0x4520(%rbx)
     8c9cc9:       c6 83 20 45 00 00 00    movb   $0x0,0x4520(%rbx)
     8ca8aa:       c6 83 20 45 00 00 00    movb   $0x0,0x4520(%rbx)
   ```

1. Examine addresses in Ghidra, specifically where `0x4520` is set to 1

   - It's set in `BoardPlayer::UpdateConfirm`
   - In particular, it checks first that `0x4518` is set to 1

1. Look for `0x4518`

   ```
   $ objdump -d --demangle Breach | grep -w 0x4518
     8a722a:       c7 83 18 45 00 00 01    movl   $0x1,0x4518(%rbx)
     8c1044:       c7 83 18 45 00 00 02    movl   $0x2,0x4518(%rbx)
     8c2578:       8b 83 18 45 00 00       mov    0x4518(%rbx),%eax
     8c26b8:       8b 83 18 45 00 00       mov    0x4518(%rbx),%eax
     8ca896:       c7 83 18 45 00 00 00    movl   $0x0,0x4518(%rbx)
     8cec84:       83 bb 18 45 00 00 02    cmpl   $0x2,0x4518(%rbx)
   ```

1. Where is `0x4518` set to 1?

   - Boom: in `BoardPlayer::UndoTurn` before the confirmation dialogue is created
   - So `0x4518` seems to be some kind of flag related to the logic of the confirmation dialogue and undo turn

1. Try bypassing the confirmation dialogue logic

   - In `BoardPlayer::UndoTurn`, I set an early return after `0x4518` is set but before the confirmation dialogue is created by doing an early jump
     - However, this broke the reset turn button; clicking on it did nothing
   - Looking more carefully over the previous findings, `0x4520` is checked before `0x4518` is checked

1. Look over the code again

   - Going back over previous findings above, `LoadGame` is called when the `0xf` event is set, which is created when `0x4520` is not 0
   - `0x4520` is set to 1 in `BoardPlayer::UpdateConfirm` after checking `0x4518`
   - But `BoardPlayer::UpdateConfirm` also checks the state of the confirmation dialogue created at `0x1160`, the same offset for the confirmation dialogue created in `UndoTurn`

1. Set `0x4520` instead of `0x4518`

   - Since the `0xf` event is created when `0x4520` is set, I modified `BoardPlayer::UndoTurn` to set `0x4520` instead of `0x4518`
   - It worked! The confirmation dialogue was bypassed! But it was still being created and flashed briefly on the screen

1. Try an early return again

   - Now that the confirmation dialogue was bypassed, I tried an early return again in `BoardPlayer::UndoTurn` right after `0x4520` is set to skip the creation of the confirmation dialogue
   - It worked! Now I had two patches which together would bypass the confirmation dialogue

#### Windows patch

All of the above was developed with the Linux binary, which has function names and some other debug symbols not stripped.

For Windows, all of the function names were stripped, but I was able to get a working patch:

1. I knew the `UndoTurn` function contained the string `Reset_Turn`, so I was able to find it by searching for the function where that string was referenced

1. In that function, I saw that the value at offset `0x4558` was being set to 1. In Linux, the offset is `0x4518`, so I deduced that the windows offsets were off by `0x40`

1. `UndoTurnUsed` doesn't have any string references, but in Linux it decrements the value at offset `0x451c`. So I searched the binary for decrements to the value at offset `0x455c` (`0x451c` plus `0x40`). I was able to find a decrement instruction that ended up being what I was looking for:

   ```
   $ objdump -d --demangle Breach.exe | grep -A 3 -w 0x455c | grep -B 3 dec
   --
     589a98:       8b 91 5c 45 00 00       mov    0x455c(%ecx),%edx
     589a9e:       8d 45 f0                lea    -0x10(%ebp),%eax
     589aa1:       4a                      dec    %edx
   ```

1. Once I found the two functions, it was mostly a matter of applying the same patches. One notable difference is that when I tried to add a jump to `UndoTurn` for an early return, the game was crashing. It turned out that before `0x4558` was set to 1, there were a couple of PUSH instructions that modified the stack. I had to replace these with NOP so that the stack pointer would be in the right place when the function returned to prevent the crashes.
