# Changelog

## 0.9.0

- Holding a d-pad direction now repeats: it acts on the press, then again
  after a short delay, then steadily -- so walking the grid and paging
  boxes no longer means tapping per step. A and B never repeat.
- The grid remembers the cursor. Leaving to the WITHDRAW/DEPOSIT menu and
  coming back puts you on the cell you left, in deposit mode too, with the
  party cursor clamped to the party that is actually there.
- The stats strip shows three facts the vanilla PC never did: the focused
  mon's types (box view; deposit mode covers that row with the party
  frame), a status condition if it carries one, and a `*` mark when its DVs
  are the shiny spread.

## 0.8.0

- Renamed to Bill's PC Plus (id `bills_pc_plus`), from Modern PC Boxes.
  Anyone with the old version installed should remove the `modern_boxes`
  folder: the ids differ, so the two would install side by side and both
  claim the same screen.

## 0.7.0

- Leaving the PC after moving anything now shows the save dialog -- the same
  "Now saving..." and "saved the game!" pages the START menu's SAVE uses,
  with the save jingle. The game is no longer written silently.
- A visit where nothing moved still writes nothing, and shows no dialog.

## 0.6.1

- The front sprite now sits 4px clear of the frame's inner floor instead of
  flush against it, so it no longer looks like it is resting on the border.

## 0.6.0

- Added a vertical divider between the box grid and the sprite panel, drawn
  with the same border glyph as the frames.
- The sprite panel narrows from 64px to 56px to make room for it. That is
  exactly the width of a 7x7 sprite, the largest in Gen 1, so those now sit
  flush between the divider and the frame; 5x5 and 6x6 sprites still centre
  with margin.

## 0.5.2

- Fixed the sprite and stats blanking out while moving a Pokemon. Picking
  one up removes it from the box, and the panel was still reading the cell
  under the cursor -- so it showed nothing, or, when another Pokemon had
  compacted into that slot, showed the wrong one as though it had been
  picked up instead. The panel now follows the Pokemon in hand.

## 0.5.1

- The cursor is now corner marks rather than a full square.
- Fixed the cursor rendering as a colour instead of black. It was drawn with
  a stroked rect on whole-pixel coordinates, which straddles pixel edges;
  LOVE's default smooth line style left partial-coverage greys, and the
  shade remap put those in a lighter shade than black, which the palette
  then coloured. It is drawn with filled stubs now, like every other shape
  on the Game Boy canvas.

## 0.5.0

- Added a cursor indicator: a blinking outline on the selected cell, in the
  grid and on the deposit-mode party row. Previously the only cue was the
  selected Pokemon's icon animating, which showed nothing at all on an empty
  slot -- the slot a carried Pokemon is usually headed for.
- While carrying, the outline holds steady rather than blinking, marking the
  drop target.

## 0.4.0

- The party row now has its own frame in deposit mode, drawn over the lower
  part of the stats box. Deposit mode therefore shows three stat rows
  instead of four; the SPD/SPC line is the one it gives up, and the rows
  above it do not move.
- Box mode is unchanged and keeps all four stat rows.

## 0.3.1

- Fixed B in deposit mode switching the grid over to withdraw instead of
  returning to the WITHDRAW / DEPOSIT menu. Both modes now leave the same
  way. This was a leftover from the START-toggle design that 0.2.0 replaced.

## 0.3.0

- The screen is now framed by two stacked Game Boy boxes sharing a border
  row, matching the original's chrome.
- The sprite panel narrows from 80px to 64px to make room for the frame. A
  56px sprite, the widest in Gen 1, still fits with 4px either side.
- The party row moved below the stats strip, so the stats no longer shift
  16px when deposit mode opens.

## 0.2.0

- Opening the PC now shows a WITHDRAW / DEPOSIT / SEE YA! menu, matching the
  original's shape. Picking a row opens the grid in that mode, and B returns
  to the menu, so switching between withdrawing and depositing no longer
  depends on a hidden START toggle.
- The START toggle is gone.
- The menu owns every exit from the PC, so the save is written in one place
  instead of two.

## 0.1.1

- Fixed the box screen drawing transparently: the overworld map and the PC
  main menu both showed through the grid, and the screen had no background.
  The screen now declares itself opaque, which also restores the classic
  white background.

## 0.1.0

- Replaces the PC box screen with a 5x4 grid, a front-sprite panel and a
  condensed stats strip.
- Changing box no longer forces a save. The game writes once on exit, and
  only when something actually moved.
- Pick up and drop to rearrange within a box or across boxes.
- Deposit mode shows the party as a row, with left and right choosing the
  mon and up and down choosing the destination box.
