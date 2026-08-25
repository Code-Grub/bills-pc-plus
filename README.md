<div align="center">

<img src="images/logo.png" alt="Bill's PC+" width="640"/>

**A storage-system overhaul for the [Pokémon Gen 1 Recompilation Project](https://github.com/bryanthaboi/pokemon-gen1-recomp-project).**

Free box paging with no forced save · grab-and-place rearranging · an inline art and stats panel

<p align="center">
  <a href="https://github.com/Code-Grub/bills-pc-plus/releases/latest"><img src="https://img.shields.io/github/v/release/Code-Grub/bills-pc-plus?style=flat&label=release&color=306230" alt="Latest release"/></a>
  <a href="LICENSE"><img src="https://img.shields.io/github/license/Code-Grub/bills-pc-plus?style=flat&color=306230" alt="MIT license"/></a>
  <img src="https://img.shields.io/badge/lua-L%C3%96VE-306230?style=flat" alt="Written in Lua for LOVE"/>
</p>

</div>

---

Bill's PC+ replaces the built-in PC box screen with a grid interface. Browse and
rearrange your boxes freely — the game is only written when you actually move
something, and it tells you when it does.

<p align="center">
  <img src="images/demo_box_v3.gif" width="480" alt="Box view: the 5x4 grid with gaps, the selected Pokemon's sprite and stats — cursor blinks, MOVE and page"/><br/>
  <sub>Box view — free paging, grab-and-place with gaps</sub>
</p>

<p align="center">
  <img src="images/demo_deposit_v3.gif" width="480" alt="Deposit view: the party row under the box grid — party cursor and destination paging"/><br/>
  <sub>Deposit view — party row and destination paging</sub>
</p>

## Features

- **Free box paging** — walk the cursor off the left or right edge of the grid
  to page between boxes. No forced save when you switch; `save.currentBox` only
  persists if you move something.
- **Grab-and-place, with gaps** — pick a Pokemon up with `A`, drop it on any
  cell. Swap if the slot is occupied, place if it is free, and the rest stay
  exactly where they were. Cross-box moves just work.
- **Inline art and stats panel** — the selected Pokemon's front sprite and
  condensed stats (level, HP, ATK/DEF/SPD/SPC) sit beside the grid, and keep
  describing the Pokemon in hand while you carry it.
- **Deposit mode** — your party appears as a row under the box; pick one and
  page the destination box independently.
- **Honest saves** — the PC menu is the only place the game writes your save,
  and it announces it with the same "Now saving... / saved the game!" pages as
  the START menu's SAVE. Browsing writes nothing and shows nothing.
- **Readable cursor** — blinking corner marks on the selected cell, holding
  steady over a carry's landing spot, readable on empty slots.
- **Stays Gen 1** — everything is drawn from the game itself: the same font,
  window borders, palette and sound effects as the vanilla PC, so the grid
  reads like something the Game Boy could have shipped.

## Install

**Mod manager:** grab the release zip from
[Releases](../../releases) and import it — FIND MODS in the launcher, or drop
the zip into the save directory's `imports/mods/` folder and rescan.

**Manual:** unzip the release into the game's `mods/bills_pc_plus/` directory.
It claims the `BoxMenu` screen id, so it replaces the built-in PC box screen
with no further configuration.

## Controls

Opening the PC shows a menu:

| Row | Action |
|---|---|
| WITHDRAW POKéMON | Opens the box grid |
| DEPOSIT POKéMON | Opens the box grid with your party shown as a row |
| SEE YA! | Leaves the PC, saving if anything moved |

`B` from either grid returns to this menu, so switching between withdrawing
and depositing is `B` then pick.

### Box view (WITHDRAW)

| Input | Action |
|---|---|
| D-pad | Move the cursor within the grid |
| Left/Right at a grid edge | Page to the previous/next box, cursor wrapping to the opposite column |
| A on a Pokemon | Cursor menu: MOVE / WITHDRAW / STATS / RELEASE / CANCEL |
| A while carrying | Drop: swap if the slot is occupied, append if empty |
| B | Cancel carry; if not carrying, back to the menu |

### Deposit view (DEPOSIT)

| Input | Action |
|---|---|
| Left/Right | Move along the party row (what to deposit) |
| Up/Down | Page the destination box (where to put it) |
| A | Deposit the highlighted Pokemon into the box shown |
| B | Back to the menu |

## Known limitations

- **Gaps are a display layer, not cartridge data.** The Gen 1 save format
  stores a count byte followed by that many contiguous Pokemon — no hole
  encoding — so the layout rides in the engine save beside it. Exporting a
  .sav packs each box in reading order; importing one refills that box
  solid. A box the game changed outside the PC (a catch, a trade) fills
  its gaps from the left on the next visit.
- `save.currentBox` does not persist if the player only browsed. Changing box
  never marks the save dirty, since that is the point of the feature.
- If every cell of every box is full, cancelling a carry refuses with a
  message and the Pokemon stays in hand, rather than creating an
  over-capacity box.

## Version

Newest release: [releases/latest](https://github.com/Code-Grub/bills-pc-plus/releases/latest) — full history in [CHANGELOG.md](CHANGELOG.md).

## License

MIT — see [LICENSE](LICENSE). Fork it, bundle it, build on it; just keep the
notice. The mod draws its font, borders, palette and sounds from the game at
runtime and ships no game assets of its own.
