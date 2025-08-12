# Research

⚠️ This is an incoherent dump of research notes

## To do

- [x] Check Lua to see if it can just be changed in Lua
- [x] String search for binaries to decompile
- [ ] Decompile with Ghidra
  - [ ] Search for Button_UndoTurn
  - [ ] Search for Button_UndoTurnUsed
  - [ ] Search for `undoturn`
- [ ] Debug
  - [ ] Reset button click
  - [ ] Console `undoturn` functionality
- [ ] Otherwise, find button implementation and see if there's an easy way to disable setting whatever flag tracks that the reset turn button has been pressed
- [ ] Or debug the console `undoturn` functionality and see how it differs
- [ ] Wire the button to match the console `undoturn` functionality instead

## Initial research

#### Game files

- text.lua

  ```
  Button_UndoTurn = "RESET TURN",
  Button_UndoTurnUsed = "RESET USED",
  ```

- images.lua

  ```
  Buttons["undoTurn"] = Button(Boxes["undo_turn_rect"], "Button_UndoTurn", 12)
  ```

#### Text searches

The `Breach` binary is the only other file that has matches for:

- `Button_UndoTurn`
- `UndoTurnUsed`
- `undoturn`

## Breach binary research

Binary with debug info, not stripped!

#### Research

- `RenderEndTurn`
- `IsUndoTurnPossible`
  - Does this check to see that the player can undo turn, or only that the file to undo the turn exists?

It looks like the code boils down to an if statement, corresponding to this assembly:

```
        008bdd79 8b 8b 1c        MOV        ECX,dword ptr [RBX + 0x451c]
                 45 00 00
        008bdd7f 85 c9           TEST       ECX,ECX
        008bdd81 0f 8e 21        JLE        LAB_008be7a8
                 0a 00 00
```

So to mod, I think I can change 0f 8e 21 0a 00 00 to 90 90 90 90 90 90 to make it so that the if statement is bypassed

Hmm, no, that's not a good idea. Better yet: track the memory location at RBX+0x451c to see where it's decremented, and mod that instead

1. Debug with gdb

1. Set breakpoint at RenderEndTurn

1. Check value of RBX+0x451c

1. Set watch point on address of RBX+0x451c

1. Continue debugging

1. Click reset turn

Didn't work: the address of watch point was in a thread and when reset turn was clicked, thread was destroyed, address of RBX changed

Next, searched the code for modifications of `0x451c`

Boom:

```
$ objdump -d Breach | grep 0x451c
  82b129:       e9 de b6 ff ff          jmp    82680c <glewInit+0x451c>
  8a58c4:       83 af 1c 45 00 00 01    subl   $0x1,0x451c(%rdi)
```

Right away there's a decrement (0x451c - 1)

Try patching it, and it worked!

## Don't show reset turn confirmation dialogue

It would be nice if we didn't have to see the reset turn confirmation dialogue at all. Clicking Reset Turn in the UI shows the dialogue, but the console command `undoturn` doesn't.

- `UndoTurn` function seems to call `ConfirmBox::Open`

  - Setting breakpoint, the flow seems to be straightforward: UndoTurn > ConfirmBox::Open
  - Then at some point LoadGame is called
  - Then LoadGame calls UndoTurnUsed

- Searching Ghidra for `undoturn` shows `UpdateConsole` function

  - Seems like `undoturn` calls `LoadGame` directly to load `undoSave.lua`
  - Interesting; LoadGame actually calls UndoTurnUsed? I guess it doesn't matter right now, but I wonder why the undo turn counter isn't decremented when using `undoturn`

- I think to implement it, we'd need to instead of calling ConfirmBox::Open, just call LoadGame
  - The whole logic of UndoTurn just seems to be setting up the ConfirmBox as far as I can tell

#### UndoTurn

- Logic seems straightforward:
  1. IsUndoTurnPossible
     - check save file exists, maybe checking units have done something, etc
  1. Interesting: sets 0x4518 to 1
  1. Then just sets string for confirmation dialogue and shows it (`ConfirmBox::Open`)
  1. Then does some cleanup
- So I guess the actual call to LoadGame is handled by the game loop (Game::OnLoop)

#### ConfirmBox::Open

- Called like this: `ConfirmBox::Open((ConfirmBox *)(this + 0x1160),local_18,0,1);`

- `0x20`: main text
- `0x90`: yes button text
- `0x268`: no button text
- `0x440`: ok button text
- `0x5d0`: "choice?"
  - Defaults to 2
- Third parameter (cancel?) gets mapped to `this[0x640]`
  - Defaults to 0
- `this[0x641]` Gets set to 0; maybe this is the OK button?
  - Defaults to 0
- Last parameter gets mapped to `this[0x642]`
  - Defaults to 1

#### What is 0x4518?

```
objdump -d Breach | grep -w 0x4518
```

- Set to 1 in `UndoTurn` (which is called by clicking the button but not by the `undoturn` command)
- Set to 2 in `BoardPlayer::EndTurn`
  - Seems to be set when the `no_confirm` setting is set, seems to be some kind of configuration value in settings.lua
  - Not sure we want to mess with this? Seems to also be used by other functions
    - BoardPlayer::UpdateConfirm

#### How to call LoadGame?

- Copy functionality from UpdateConsole?
- Or trigger the event loop somehow? seems complicated ...

#### Could we instead re-use the mouse event from clicking reset turn to instead do whatever the confirmation does when clicking the confirm reset turn

## BoardPlayer

State set in `BoardPlayer::BoardPlayer` function

- 0x1160
  - Confirmation box object, seems to be generic (e.g. used by UndoTurn, EndTurn, etc.)
- 0x4518: whether or not to show confirmation dialogues? not sure
  - defaults to 0 but gets set to e.g. 1 by UndoTurn dialogue
  - Possibly related to `no_confirm` option ("End Turn Confirmation" in game options)
- 0x451c: number of resets available
  - defaults to 1

Trying

`break BoardPlayer::UndoTurnUsed`

```
break BoardPlayer::OnMouseAction
```

```
break ConfirmBox::Open
```

`break ConfirmBox::OnMouseAction`

`break ConfirmBox::GetChoice`

`break BoardPlayer::StateMouseAction`

```
Thread 1 "Breach" hit Breakpoint 17, 0x00000000008cff70 in BoardPlayer::OnMouseAction(KeyAction, int) ()
(gdb) bt
#0  0x00000000008cff70 in BoardPlayer::OnMouseAction(KeyAction, int) ()
#1  0x0000000000704b50 in CEvent::OnEvent(SDL_Event const*) ()
#2  0x0000000000481947 in CApp::OnExecute() ()
#3  0x000000000040cb57 in main ()
```

(gdb) print/x $rdi
$18 = 0x7d58978
(gdb) print/x $rsi
$19 = 0x1
(gdb) print/x $rdx
$20 = 0x1

#### Click Reset Turn

```
Thread 1 "Breach" hit Breakpoint 9.1, 0x00000000009307f0 in ConfirmBox::Open(std::basic_string<char, std::char_traits<char>, std::allocator<char> >, bool, bool) ()
(gdb) bt
#0  0x00000000009307f0 in ConfirmBox::Open(std::basic_string<char, std::char_traits<char>, std::allocator<char> >, bool, bool) ()
#1  0x00000000008a7295 in BoardPlayer::UndoTurn() ()
#2  0x00000000008c2494 in BoardPlayer::StateMouseAction(KeyAction, int) ()
#3  0x00000000008d0239 in BoardPlayer::OnMouseAction(KeyAction, int) ()
#4  0x0000000000704b50 in CEvent::OnEvent(SDL_Event const*) ()
#5  0x0000000000481947 in CApp::OnExecute() ()
#6  0x000000000040cb57 in main ()
```

- BoardPlayer::OnMouseAction > StateMouseAction
- Checks to see if hovering over reset turn button; I guess that's `0x790`?
- The calls UndoTurn(this)

- I think ConfirmBox::GetChoice() is the loop that waits for the click??

#### Click Yes on reset confirm dialogue

```
Thread 1 "Breach" hit Breakpoint 20, 0x000000000092fe10 in ConfirmBox::OnMouseAction(KeyAction, int) ()
(gdb) bt
#0  0x000000000092fe10 in ConfirmBox::OnMouseAction(KeyAction, int) ()
#1  0x00000000008d00cc in BoardPlayer::OnMouseAction(KeyAction, int) ()
#2  0x0000000000704b50 in CEvent::OnEvent(SDL_Event const*) ()
#3  0x0000000000481947 in CApp::OnExecute() ()
#4  0x000000000040cb57 in main ()
```

```
Thread 1 "Breach" hit Breakpoint 19, 0x00000000008cff70 in BoardPlayer::OnMouseAction(KeyAction, int) ()
(gdb) bt
#0  0x00000000008cff70 in BoardPlayer::OnMouseAction(KeyAction, int) ()
#1  0x0000000000704b50 in CEvent::OnEvent(SDL_Event const*) ()
#2  0x0000000000481947 in CApp::OnExecute() ()
#3  0x000000000040cb57 in main ()
```

```
(gdb) bt
#0  0x000000000092fe10 in ConfirmBox::OnMouseAction(KeyAction, int) ()
#1  0x00000000008d00cc in BoardPlayer::OnMouseAction(KeyAction, int) ()
#2  0x0000000000704b50 in CEvent::OnEvent(SDL_Event const*) ()
#3  0x0000000000481947 in CApp::OnExecute() ()
#4  0x000000000040cb57 in main ()
```

```
(gdb) bt
#0  0x00000000008a58c0 in BoardPlayer::UndoTurnUsed() ()
#1  0x00000000005eafb4 in GameMap::LoadGame() ()
#2  0x00000000004f7ddf in Game::LoadGame(std::basic_string<char, std::char_traits<char>, std::allocator<char> >) ()
#3  0x00000000004f9e83 in Game::OnLoop() ()
#4  0x000000000047f65f in CApp::OnLoop() ()
#5  0x0000000000481b98 in CApp::OnExecute() ()
#6  0x000000000040cb57 in main ()
```

Is this it??? This is what gets called after clicking Yes!!

```
  if (this[0x1168] != (BoardPlayer)0x0) {
    ConfirmBox::OnMouseAction((ConfirmBox *)(this + 0x1160));
    return;
  }
```

- This just passes the mouse event to ConfirmBox, which then does its own logic
- If we call this manually it probably won't do anything because the mouse pointer will be in a different spot
- But if we trace this functionality we might just be able to see where it leads
  - It's possibly triggering some kind of event

To do:

- Break on ConfirmBox::OnMouseAction
- Once we get there, maybe do nexti to step through and see what happens?
  - The end goal would be to set the state exactly as needed and call the same functionality, if possible

```
rr replay Breach-0
```

```
break *0x8d00c7
```

- ConfirmBox::OnMouseAction called with param2=2, param3=1

```
(rr) print (int)$rsi
$1 = 2
(rr) print (int)$rdx
$2 = 1
```

- When clicking the actual confirmation:

(gdb) print (int)$rsi
$13 = 1
(gdb) print (int)$rdx
$14 = 1

- at line 18, first nested if
  (gdb) print/x _(unsigned char _)($rdi + 0x641)
  $15 = 0x0

- made it to line 21, 23

- line 23

  - print/x _(unsigned char _)($rbx + 0x5d0)

  - RDX+0x5d0 is 2, setting to 0

- line 31
  - I think cVar2 must be 0 because line 32 gets skipped
- line 43

  - RBX+0628 is 0, second condition gets skipped

- Then we get kicked to

704b50 CEvent::ONEvent
704350
481947 CApp::OnExecute
481927
8d00c7 BoardPlayer::OnMouseAction

Then ConfirmBox::OnMouseAction gets called again :/
with 2,1, skipps both conditions

#### Flow

- ConfirmBox::OnMouseAction gets called twice, second time 2nd parameter is 1, which does extra stuff

#### Latest

```
break ConfirmBox::OnMouseAction
```

Then

```
break Game::LoadGame
```

```c

void __thiscall ConfirmBox::OnMouseAction(ConfirmBox *this,int param_2,int param_3)

{
  int *piVar1;
  char cVar2;
  int iVar3;
  allocator local_3b;
  allocator local_3a [2];
  long local_38 [2];
  long local_28 [2];

  if ((param_3 == 1) && (param_2 == 1)) {
    if (this[0x641] == (ConfirmBox)0x0) {
      cVar2 = Button::IsHovering((Button *)(this + 0x208));
      if (cVar2 == '\0') {
        cVar2 = Button::IsHovering((Button *)(this + 0x30));
        if (cVar2 != '\0') {
          *(undefined4 *)(this + 0x5d0) = 0;
        }
      }
      else {
        // skipped
        // *(undefined4 *)(this + 0x5d0) = 1;
      }
      cVar2 = Rect2D::Contains((Rect2D *)(this + 0x5d4),(int)(float)MouseControl::Mouse,
                               (int)(float)DAT_00de6684,false);
      if ((cVar2 == '\0') && (this[0x628] == (ConfirmBox)0x0)) {
        // skipped
        // *(undefined4 *)(this + 0x5d0) = 1;
      }
    }
    else {
      cVar2 = Button::IsHovering((Button *)(this + 0x3e0));
      if (cVar2 != '\0') {
        *(undefined4 *)(this + 0x5d0) = 0;
        (**(code **)(*(long *)this + 0x20))(this);
      }
    }
  }
  if ((this[0x640] != (ConfirmBox)0x0) &&
     (cVar2 = ToggleBox::OnMouseAction((ToggleBox *)(this + 0x650),param_2,param_3), cVar2 != '\0'))
  {
    // skipped
  }
  return;
}
```

rbreak CEvent::
rbreak BoardPlayer::
rbreak CApp::
rbreak Game::
rbreak ConfirmBox::

tracing backwards from LoadGame:

```
#0  0x000000000047bc60 in CApp::OnMouseAction(KeyAction, int) ()
#1  0x0000000000704b50 in CEvent::OnEvent(SDL_Event const*) ()
#2  0x0000000000481947 in CApp::OnExecute() ()
#3  0x000000000040cb57 in main ()
```

```
#0  0x00000000007034b0 in CEvent::OnEvent(SDL_Event const*) ()
#1  0x0000000000481947 in CApp::OnExecute() ()
#2  0x000000000040cb57 in main ()
```

```
#0  0x000000000092fe10 in ConfirmBox::OnMouseAction(KeyAction, int) ()
#1  0x00000000008d00cc in BoardPlayer::OnMouseAction(KeyAction, int) ()
#2  0x0000000000704b50 in CEvent::OnEvent(SDL_Event const*) ()
#3  0x0000000000481947 in CApp::OnExecute() ()
#4  0x000000000040cb57 in main ()
```

```
$ objdump -d --demangle Breach | grep -B 6 AddEvent | egrep -w '0xf|0x4d'
  67a825:       88 44 24 0f             mov    %al,0xf(%rsp)
  8c9cba:       be 0f 00 00 00          mov    $0xf,%esi
```

Break on AddEvent:

break \*0x7086a0
condition $bpnum ( (int)$rsi == 0xf || (int)$rsi == 0x4d || (int)$rsi == 0xe)

To do:

1. set initial breakpoints
   - UndoTurn
   - AddEvent with condition?
     - This might be super slow!
1. Run until break
1. Add more breakpoints and run again
   - LoadGame
   - ConfirmBox::OnMouseAction

#### Event

- 0x4d is never set?
- 0xf set in BoardPlayer::OnLoop
- 0xe set in Game::LoadGame
  - And BoardPlayer::StateLabelDone

BoardPlayer::OnLoop does this; adds the event if 0x4520 is set to 1

```
  if ((this[0x4520] != (BoardPlayer)0x0) &&
     (cVar1 = (**(code **)(**(long **)(this + 8) + 0x100))(), cVar1 == '\0')) {
    EventSystem::AddEvent((EventSystem *)EventSystem::EventManager,0xf,0x7fffffff);
    this[0x4520] = (BoardPlayer)0x0;
  }
```

- Set to 0 by default

```
$ objdump -d --demangle Breach | grep -w 0x4520
  8c25a9:       c6 83 20 45 00 00 01    movb   $0x1,0x4520(%rbx)
  8c97bd:       80 bb 20 45 00 00 00    cmpb   $0x0,0x4520(%rbx)
  8c9cc9:       c6 83 20 45 00 00 00    movb   $0x0,0x4520(%rbx)
  8ca8aa:       c6 83 20 45 00 00 00    movb   $0x0,0x4520(%rbx)
```

```
$ objdump -d --demangle Breach | grep -w 0x4518
  8a722a:       c7 83 18 45 00 00 01    movl   $0x1,0x4518(%rbx)
  8c1044:       c7 83 18 45 00 00 02    movl   $0x2,0x4518(%rbx)
  8c2578:       8b 83 18 45 00 00       mov    0x4518(%rbx),%eax
  8c26b8:       8b 83 18 45 00 00       mov    0x4518(%rbx),%eax
  8ca896:       c7 83 18 45 00 00 00    movl   $0x0,0x4518(%rbx)
  8cec84:       83 bb 18 45 00 00 02    cmpl   $0x2,0x4518(%rbx)
```

Ideas:

- Add 0xf event?
- Or set the flags that trigger that event
  - 0x4520 is 1
    - ... which happens when 0x4518 is 1
    - Which happens right at the top of undo turn ............. 🤦‍♂️🤦‍♂️🤦‍♂️🤦‍♂️🤦‍♂️🤦‍♂️🤦‍♂️

Set 4a7234 to c3 (early return)

Set 4a7290 5 bytes to NOP (90)

break \*0x8a722a

break BoardPlayer::UndoTurnUsed

break BoardPlayer::UndoTurn

break Game::LoadGame

## Confirmation dialog flow

1. BoardPlayer::BoardPlayer
   - Initialises 0x4518 to 0
1. BoardPlayer::UndoTurn

   1. Sets 0x4518 to 1
   1. Calls ConfirmBox::Open at 0x1160

1. BoardPlayer::UpdateConfirm

   1. Checks that 0x1168 is 0??
   1. Calls ConfirmBox::GetChoice on ConfirmBox at 0x1160
   1. Checks result
   1. Checks 0x4518 is 1
      1. Sets 0x4520 to 1
   1. Checks 0x4518 is 1
      1. Sets 0x4524 to 0

1. BoardPlayer::OnLoop

   - Checks 0x4520 is 1
     - Adds the event 0xf
     - Sets 0x4520 to 0

1. Game::OnLoop
   - Checks for the 0xf event
     - Calls Game::LoadGame

Conclusions:

- Setting 0x4518 isn't enough by itself because it still checks the ConfirmBox result :/
- Try setting 0x4520

#### Patch

- 0x4a722a: modify 0x4520 instead of 0x4518
- 0x4a7234: set to JMP

## Keep reset turn button visible during enemy turn

#### Summary

It doesn't seem possible:

- All the logic for the reset turn button display is in RenderEndTurn
  - It gets called by OnRenderUI, which is where I think the logic is checked to see if it's enemy or player turn
    - Enemy or player turn are controlled by StartState
- Looking through RenderEndTurn, it contains all of the logic for showing the end turn button, reset turn button, and undo move button. There's no way to show just the reset turn button
- Using gdb to bypass the call to RenderEndTurn confirms that it contains the logic for those three buttons. The logic is too complex and intertwined to be able to reproduce the functionality just to show the reset turn button

### Code

- The button is `Button_UndoTurn`
- End turn button is `Button_EndTurn`
- Undo move button is `Button_Undo`
- When _End Turn_ is clicked, `Button_UndoTurn` disappears
  - _End Turn_ is disabled and then disappears, hidden behind _WARNING_ _ENEMY ACTIVITY_ message
    - `Enemy_Activity_1`
    - `Enemy_Activity_2`
  - _ENEMY TURN_ flashes on the screen
    - `State_Enemy`
  - _UNDO MOVE_ also disappears
- Functions
  - `BoardPlayer::EndTurn`
  - `RenderDeployment`
    `

#### Buttons

- RenderEndTurn
  - this_00: 0x208
    - End turn button?
  - this_01: 0x5b8
    - Undo move button
  - this_02: 0x790
    - Reset turn button
- OnRenderUI
  - BoardPlayer + 0x3e0
    - Start turn?
    - Related to 0x1850
    - Disabled when 0x1b5c is true
    - Enabled when 0x1b5c is false
    - Disabled and enabled when 0x4588 is true
  - BoardPlayer + 0x1f68
    - ?
  - BoardPlayer + 0x39d8
    - Options?

#### Reset turn button

- RenderEndTurn
- OnRenderUI

#### StartState

- param_1
  - 0: player turn
  - 1: enemy attack
  - 2: enemy movement

#### RenderEndTurn

- Button logic checks 0x1850 == 0?

#### Logic

- Clicking End Turn calls BoardPlayer::EndTurn
  - This shows a confirmation dialogue popup
    - This confirmation is stored at BoardPlayer + 0x1160
    - 0x1160 is where all of the confirmation dialogues are stored, so not meaningful here I don't think
  - Sets 0x4518 to 2
    - This was set to 1 in UndoTurn; maybe we need to find where it's checked for a value of 2?
  - Calls StartState with a value of 1
- BoardPlayer::OnRenderUI checks if 0x4518 is 2
  - First checks if 0x1168 is not 0, then calls RenderActiveUnits
  - I think this is just keeping the rendering loop going if the confirm dialogue hasn't been clicked yet
- BoardPlayer::UpdateConfirm
  - I think this checks the result of the confirmation dialogue
  - Calls StartState with a value of 1

### Ideas

- Look at logic that disables _End Turn_ button when clicked
- Look at `BoardPlayer` state
  - `0x4551` (set to 1 in `UpdateEndTurn`)
- Breakpoints
  - `BoardPlayer::EndState`
  - `BoardPlayer::EndTurn`
  - `BoardPlayer::IsEnemyTurn`
  - `BoardPlayer::OnRenderUI`
  - `BoardPlayer::RenderEndTurn`
  - `BoardPlayer::StartState`
  - `BoardPlayer::UpdateEndTurn`
  - `Button::SetActive`

#### To do

- [x] Investigate Button::SetActive in RenderEndTurn
  - Button::SetActive simply enables or disables the button
- [ ] Figure out which code is hiding/showing the button
  - [ ] Set breakpoints
  - [ ] Find where 0x1160 popup confirmation is checked
- [ ] StartState
  - Is this setting something checked elsewhere in the render code?
  - What's rendering the button?
    - OnRender
  - Is the button being not rendered or hidden?
    - SetWidth
    - SetAlpha
    - SetLocation
- [ ] Figure out what the relevant functions are and check to see when they're called for 0x790
  - Button::OnRender
  - KaijuButton::OnRender
- [ ] Look again for strings
  - `undo_turn_rect`
  - `Button_UndoTurn`
  - `undo_turn`
