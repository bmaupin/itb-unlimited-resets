# Patch info

#### How the patch works

TODO

#### How the patch was created

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
