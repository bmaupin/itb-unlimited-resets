# Research

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
