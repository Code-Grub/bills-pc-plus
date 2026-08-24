# Bill's PC Plus

Replaces the Bill's PC storage screen with a grid interface: free box paging
with no forced save, grab-and-place rearranging, and an inline art and stats
panel.

## Install

Drop the `bills_pc_plus` folder into the game's `mods/` directory. It claims
the `BoxMenu` screen id, so it replaces the built-in PC box screen with no
further configuration.

## Controls

Opening the PC shows a menu:

| Row | Action |
|---|---|
| WITHDRAW POKéMON | Opens the box grid |
| DEPOSIT POKéMON | Opens the box grid with your party shown as a row |
| SEE YA! | Leaves the PC, saving if anything moved |

`B` from either grid returns to this menu, so switching between withdrawing
and depositing is `B` then pick. The menu is also the only place the game
writes your save, and it announces it: if anything moved, leaving the PC
shows the same "Now saving..." and "saved the game!" pages the START menu's
SAVE shows, so the game is never written under you silently. A visit where
you only looked around writes nothing and shows nothing.

The Game Boy pad has no L/R buttons, so paging between boxes is done by
walking the cursor off the left or right edge of the grid instead of a
dedicated shoulder button.

### Box view (WITHDRAW)

| Input | Action |
|---|---|
| D-pad | Move the cursor within the grid |
| Left/Right at a grid edge | Page to the previous/next box, cursor wrapping to the opposite column |
| A on a Pokemon | Cursor menu: MOVE / WITHDRAW / STATS / RELEASE / CANCEL |
| A while carrying | Drop: swap if the slot is occupied, append if empty |
| B | Cancel carry; if not carrying, back to the menu |

### Deposit mode (DEPOSIT)

| Input | Action |
|---|---|
| Left/Right | Move along the party row (what to deposit) |
| Up/Down | Page the destination box (where to put it) |
| A | Deposit the highlighted Pokemon into the box shown |
| B | Back to the menu |

## Layout

The screen is framed by two stacked Game Boy boxes that share their border
row, the way adjacent boxes meet in the original. The upper frame holds the
box number, the 5x4 grid and the front sprite, with a border-glyph divider
between the grid and the sprite; the lower one holds the
condensed stats. In deposit mode a third frame appears at the bottom around
the party row, covering the stats strip's fourth line -- so deposit mode
shows three stat rows rather than four, and the first three never move.

## The cursor

The selected cell carries blinking corner marks, in the grid and on the
party row alike. While you are carrying a Pokemon the outline holds steady
instead of blinking, marking where it will land -- and because it is drawn
on the cell rather than on the Pokemon, it stays readable on empty slots,
which is where a carried Pokemon usually goes.

While you are carrying, the sprite panel and stats keep describing the
Pokemon in hand rather than whatever the cursor is passing over.

## Known limitations

- Boxes stay packed: occupied slots always run 1..n with no gaps. The
  cartridge save format stores a count byte followed by that many
  contiguous Pokemon, so a decorative gap has no encoding and would be
  destroyed on export. Rearranging, swapping and cross-box moves all work;
  only scattered placement is unavailable.
- `save.currentBox` does not persist if the player only browsed. Changing
  box never marks the save dirty, since that is the point of the feature,
  so the game writes on exit only when something actually moved.
- If every box is full, cancelling a carry refuses with a message and the
  Pokemon stays in hand, rather than creating an over-capacity box.
