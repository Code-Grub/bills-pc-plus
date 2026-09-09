# Changelog style

The changelog says what changed for the player. The commit body says why and
how.

Commit messages here carry the full reasoning -- the pixel arithmetic, the
palette constraints, the case that forced a choice. That belongs in the
history, where someone touching the code will find it. It does not belong in
the file players read to find out what is new.

## Writing an entry

- One or two sentences, plain language, present tense. Lead with what the
  player sees or can now do.
- One entry per **change**, not per commit. A feature that took five commits to
  get right is one entry describing where it landed -- not the journey, not the
  intermediate tweaks, not what was tried and reverted.
- Name the symptom for a bug fix, not the mechanism: "opening the PC on a save
  another tool had touched no longer crashes", not the guard that was missing.
- Keep a consequence the player would otherwise be surprised by -- a trade-off,
  a migration step, a known limitation. Cut the derivation behind it.
- Flat bullet list per version. Group under Added / Changed / Fixed only when a
  release is big enough to need it; don't add ceremony to a two-line release.

## What this looks like

Before -- one entry, twenty lines:

> Empty cells in the grid now carry a mark of their own: a single black pixel
> at the centre of each one. A gap was otherwise indistinguishable from the
> white around the frame, so a half-full box read as a short box rather than a
> box with holes in it [...] It is black rather than a mid-gray because
> PaletteFX only anchors shade 0 and shade 3 near white and black across every
> named palette; shades 1 and 2 are real hues that vary per palette, so a gray
> dot would come out salmon under MEWMON and some other color again elsewhere.

After:

> - Empty slots in a box now show a small dot, so a half-full box reads as a
>   box with gaps rather than a short one.

The palette reasoning is not lost -- it is in the commit that made the change,
and in the code comment beside the constant.

## Screenshots

An entry can carry a screenshot when the change is visual and hard to picture
from a sentence -- a new mark, a redrawn icon, a layout that moved. Most
entries do not need one, and a file where every entry has a picture is harder
to skim than one where the pictures mean something.

- Crop to the thing that changed, not the whole screen. A full 160x144 capture
  makes the reader hunt for the difference.
- Pin the crop to what that version looked like. Cropping a current screenshot
  into an old entry can show features that did not exist yet -- the grid detail
  under 0.14.0 stops at the header row for exactly that reason, since the
  paging arrows above it arrived in 0.15.0.
- Write real alt text saying what is in the shot, not "screenshot".
- Relative paths are fine here: this file is read on the repo page. Check
  before relying on them elsewhere -- a release workflow that pastes the
  changelog into GitHub Releases will not render them.

## When entries are written

Feature commits do not touch `CHANGELOG.md`. A separate `[release X.Y.Z]`
commit writes the entry and bumps `manifest.json`, so the entry is written once
at release time, looking back over the whole release. That is the moment to
merge a release's tweaks into a single line each.
