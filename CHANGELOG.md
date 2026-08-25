# Changelog

## 0.10.0

- The PC no longer writes your save. Moving a Pokemon used to end the visit
  with the "Now saving..." sequence; now it ends the visit, and what you did
  rides along with your next ordinary save the way the rest of your progress
  does. Leaving after moving six mons looks exactly like leaving after
  moving none. The trade is the one vanilla never made: quit without saving
  and the PC visit goes with everything else you did since.
- Box data can no longer be written half-reconciled. The grid keeps its own
  copy of the boxes while the PC is open, and the packed save only caught up
  when you left, so a save landing inside that window -- the F1 hotkey,
  another mod -- wrote a withdrawn Pokemon into the party *and* the box it
  came from, or a deposited one into neither. The mod now wraps the engine's
  `save.write` hook and reconciles before any save captures state, whoever
  started it.
- `save.currentBox` follows the box you were last looking at rather than
  being held back until something moved. Nothing writes on its own either
  way, and the PC reopens where you left it.

## 0.9.4

- Picking a mon up to look at it and putting it back no longer counts as a
  change. Browsing was never supposed to write, but the carry set the dirty
  flag on the way down regardless of where the mon landed, so a cancelled
  MOVE ran the whole "Now saving..." sequence over a box that had not
  moved. A carry that ends on the cell it started from now leaves the flag
  where it found it -- while a swap, which really did move the occupant,
  still counts.
- A `bpp_layout` that is not a table no longer takes the PC down with it.
  The per-cell guard was already there; the container itself was trusted,
  and anything that writes a save can reach it, so opening the PC on a save
  another tool had touched could throw before the grid ever drew.
- A box holding more mons than the grid has cells keeps them. Committing
  rewrites every box from its sparse copy, so mons past the twentieth used
  to disappear the moment any other box was touched. They ride alongside
  the layout now and go back into the save untouched.
- Front sprites are held in a bounded cache rather than one that grew for
  every mon the player walked past, and the true-colour flag is read fresh
  for each mon instead of being remembered against the sprite's path -- a
  hook can serve one file for two mons and flag only one of them.
- Releases carry their name again: the packaging workflow titled them with
  a bare version number.

## 0.9.3

- A nickname carrying a gender symbol no longer scrolls out of its own
  panel. The identity plate measured names in UTF-8 bytes, so a glyph
  written in three bytes counted as three: `PIKA` plus the two gender
  marks measured 80px against a 56px panel, and a name that fits marqueed
  anyway -- pinned to the panel's left edge with its tail sliding. Names
  measure glyph advances now, which is what `Font.width` is for.
- The shiny mark moved off the HP line, up to the plate beside the level.
  HP centres under the sprite and a three-digit `100/100` is 56px -- the
  panel's whole width -- so the mark had been landing on top of its last
  digit for any shiny past three-figure HP.

## 0.9.2

- Front sprites are cached rather than reloaded from disk on every focus
  change, and sprite placement moved behind `Layout.spritePos` so every
  view positions art the same way. Layout gained validation.
- The README's demo GIFs loop instead of stopping on their last frame.
- Dev assets are kept out of the release archive, and the release itself
  is cut by a workflow rather than by hand.

## 0.9.1

- Box view's stats window gains a DV spread line under the types: the
  hidden numbers breeders and competitive players sort boxes by, shown for
  the focused mon.
- The README links the newest release instead of pinning a version.

## 0.9.0

- The focused mon's name and level moved from the stats strip to a plate
  above its sprite, and the sprite stands on the frame floor. The strip
  reordered around what sits above it: the box count reads under the grid,
  the mon's HP under its sprite, with the shiny mark and status condition
  between them. Then ATK/DEF, SPD/SPC, and the type line (box view's bonus
  row; deposit's party frame covers it).
- Boxes can hold gaps. Drop a Pokemon on any free cell and the others stay
  exactly where they are -- no more compaction. The cartridge save cannot
  encode a hole, so the layout rides in the engine save beside it: a .sav
  export packs each box in reading order, an import refills that box
  solid, and a box the game changed outside the PC (a catch, a trade)
  fills its gaps from the left on the next visit.
- Deposit places into the destination box's first free cell, gaps included.
- Holding a d-pad direction now repeats: it acts on the press, then again
  after a short delay, then steadily -- so walking the grid and paging
  boxes no longer means tapping per step. A and B never repeat.
- The screen now declares its own SGB palette (MEWMON, the generic
  full-screen menu palette). Neither PC menu above the overworld declares
  one, so the box previously inherited the current map's palette -- the
  icons changed color depending on where you were standing when you opened
  the PC.
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
