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
