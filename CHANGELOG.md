# Changelog

Written in the style described in [docs/changelog-style.md](docs/changelog-style.md):
what changed for the player, with the reasoning left in the commit history.

## 0.15.1

- The sprite panel shows each Pokemon in its own colours. Every Pokemon was
  drawn in the same purple and orange before, whatever it actually was.
- Full-colour menu icons keep their colours on Gold, Silver and Crystal
  instead of being repainted in the party menu's four. This one waits on an
  engine build that carries the icon true-colour flag; on current builds
  nothing changes.

## 0.15.0

### Added

- The box screen works on Gold, Silver and Crystal now, not only Red, Blue and
  Yellow. The grid, the sprite panel, the stats strip and deposit mode all
  behave the way they do on Gen 1.
- Gen 2 shows all five of its stats. Special is two stats there rather than
  one, so the strip runs five columns instead of four, with two-letter headers
  to fit them. The DV row still shows four numbers: Gen 2 stores a single
  Special DV that feeds both special stats, so it sits centred under the pair
  rather than claiming either column.

### Changed

- The stats strip is a table. A header row names each column, and every DV sits
  under the stat it belongs to.
- The type line has its own row at the foot of the strip, a blank line clear of
  the numbers, and has dropped the TY label it carried in 0.14.0.
- Left and right arrows flank the box number, showing which directions page.

### Known limitations

- On Gen 2 the DV row carries no DV label -- the fifth column takes the space
  it used. Told apart by their length on most Pokemon, the two number rows can
  read alike on a low-level one, where both are two digits wide.
- On Gen 2 an egg's portrait shows the Pokemon it will hatch into. Its icon in
  the grid is correct.

## 0.14.0

- Empty slots in a box now show a small dot, so a half-full box reads as a box
  with gaps rather than a short one.

  ![A box holding ten Pokemon, the empty slots between them each marked with a
  single dot](images/detail_empty_slots.png)

- The type line is labelled TY, matching the DV line under it.

## 0.13.0

- Paging between boxes slides instead of cutting.
- Holding a d-pad direction now repeats at the same speed as every other menu
  in the game. It used to run noticeably faster.

## 0.12.0

- The DV spread can be turned off, under OPTIONS -> MODS -> BILL'S PC PLUS ->
  DV DISPLAY. It stays on by default, and the change lands on the next frame
  rather than the next PC visit.
- The shiny mark keeps showing with the DV numbers hidden: it says which
  Pokemon this is, not what its stats are.

## 0.11.0

- Saving inside the PC is refused, and happens the moment you leave instead.
  A mod that saves on its own -- autosave, save states -- could previously
  catch you holding a Pokemon, which belongs to no box and no party, and write
  it nowhere at all. Nothing is lost now: the save you asked for still runs, on
  the way out.
- Saving anywhere else is untouched, and another mod's own veto still decides.
- A box that something else rearranged drops its gaps instead of applying them
  to the wrong Pokemon, and no Pokemon can go missing down any of these paths.

## 0.10.0

- The PC no longer writes your save. Moving a Pokemon used to end the visit
  with "Now saving..."; now what you did rides along with your next ordinary
  save, like the rest of your progress. The trade is the one vanilla never
  made: quit without saving and the PC visit goes with everything else.
- A save landing mid-visit -- the F1 hotkey, another mod -- can no longer catch
  the boxes half-updated and duplicate or drop a Pokemon.
- The PC reopens on the box you were last looking at.

## 0.9.4

- Picking a Pokemon up and putting it back where it was no longer counts as a
  change, so a cancelled move stops running the save sequence.
- Opening the PC on a save another tool had touched no longer crashes.
- A box holding more Pokemon than the grid has cells keeps all of them.
- Sprite memory no longer grows as you play.
- Releases carry their name again instead of a bare version number.

## 0.9.3

- A nickname with a gender symbol in it no longer scrolls out of its panel.
- The shiny mark moved up beside the level, so it no longer lands on top of the
  HP readout for a shiny with three-figure HP.

## 0.9.2

- Front sprites are cached instead of reloaded every time the focus changes.
- The README's demo GIFs loop instead of stopping on the last frame.
- Dev assets are kept out of the release archive.

## 0.9.1

- The stats window gains a DV spread line under the types, for the Pokemon in
  focus.
- The README links the newest release instead of pinning a version.

## 0.9.0

- The focused Pokemon's name and level moved to a plate above its sprite, and
  the stats strip reordered around it: the box count under the grid, HP under
  the sprite, then ATK/DEF, SPD/SPC and the type line.
- Boxes can hold gaps. Drop a Pokemon on any free cell and the others stay
  where they are. Exporting a `.sav` packs each box solid, and a box the game
  changed outside the PC -- a catch, a trade -- fills its gaps from the left on
  your next visit.
- Deposit places into the destination box's first free cell.
- Holding a d-pad direction repeats, so walking the grid and paging boxes no
  longer means a tap per step. A and B never repeat.
- Box icons keep their own colours instead of taking the palette of whatever
  map you happened to open the PC on.
- The grid remembers your cursor. Leaving to the WITHDRAW / DEPOSIT menu and
  coming back puts you back on the cell you left.
- The stats strip shows three things the vanilla PC never did: the focused
  Pokemon's types, its status condition, and a `*` when it is shiny.

## 0.8.0

- Renamed to Bill's PC Plus (id `bills_pc_plus`), from Modern PC Boxes. If you
  have the old version installed, remove the `modern_boxes` folder: the ids
  differ, so the two install side by side and both claim the same screen.

## 0.7.0

- Leaving the PC after moving anything shows the save dialog, jingle and all.
  The game is no longer written silently.
- A visit where nothing moved writes nothing, and shows no dialog.

## 0.6.1

- The front sprite sits clear of the frame floor instead of resting on the
  border.

## 0.6.0

- A vertical divider separates the box grid from the sprite panel. The largest
  Gen 1 sprites sit flush between it and the frame; smaller ones still centre.

## 0.5.2

- The sprite and stats no longer blank out while you are moving a Pokemon. The
  panel follows the one in your hand.

## 0.5.1

- The cursor is corner marks rather than a full square, and draws black instead
  of picking up a colour from the palette.

## 0.5.0

- Added a cursor: a blinking outline on the selected cell, in the grid and on
  the deposit party row. Before this the only cue was the selected Pokemon's
  icon animating, which showed nothing at all on an empty slot.
- The outline holds steady while you are carrying, marking the drop target.

## 0.4.0

- The party row has its own frame in deposit mode. Deposit shows three stat
  rows instead of four; box mode keeps all four.

## 0.3.1

- Fixed B in deposit mode switching the grid to withdraw instead of returning
  to the WITHDRAW / DEPOSIT menu. Both modes leave the same way now.

## 0.3.0

- The screen is framed by two stacked Game Boy boxes sharing a border row,
  matching the original's chrome.
- The party row moved below the stats strip, so the stats no longer shift when
  deposit mode opens.

## 0.2.0

- Opening the PC shows a WITHDRAW / DEPOSIT / SEE YA! menu, matching the
  original's shape. Picking a row opens the grid in that mode and B returns to
  the menu, replacing the hidden START toggle.

## 0.1.1

- Fixed the box screen drawing transparently, with the overworld map and the PC
  menu showing through the grid.

## 0.1.0

- Replaces the PC box screen with a 5x4 grid, a front-sprite panel and a
  condensed stats strip.
- Changing box no longer forces a save. The game writes once on exit, and only
  when something actually moved.
- Pick up and drop to rearrange within a box or across boxes.
- Deposit mode shows the party as a row: left and right choose the Pokemon, up
  and down choose the destination box.
