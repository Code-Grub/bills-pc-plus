-- Pure geometry for the box screen, in native pixels on the 160x144
-- canvas.  Font.GLYPH is 8, so the screen is 20x18 characters and every
-- constant here is a multiple of 8.
--
-- The screen is framed by two stacked Game Boy boxes that share their
-- border row, the way adjacent boxes meet in the original.  Font.drawBox
-- takes TILE coords, fills its area white and draws a 1-tile border, so a
-- framed region loses 8px on every side:
--
--   Box A = (0, 0, 20, 12)  interior px x=8..152, y=8..88
--           header, the grid, the count line, and the sprite panel
--   Box B = (0, 11, 20, 7)  interior px x=8..152, y=96..136
--           the stats strip, and the party row in deposit mode
--
-- Row 11 is both A's bottom border and B's top, drawn once as a shared
-- line.  Box B must therefore be drawn AFTER box A and BEFORE any content,
-- since drawBox's white fill erases whatever it covers.

local Layout = {}

Layout.CELL = 16
-- Length of each cursor corner arm, in pixels.  5 of a 16px cell reads as a
-- bracket with the edge left open in the middle.
Layout.CURSOR_ARM = 5
Layout.ROW = 8

-- tile rects for the two frames, as drawBox takes them
Layout.BOX_A_TILES = { 0, 0, 20, 12 }
Layout.BOX_B_TILES = { 0, 11, 20, 7 }
-- Box C frames the party row in deposit mode only, drawn OVER the lower
-- part of box B -- which box mode leaves empty anyway, so the frame costs
-- nothing there.  Its interior lands exactly on PARTY_Y, which is why no
-- other constant moves.  It covers the type line in the stats strip (see
-- drawStats), which is the one row deposit mode gives up.
Layout.BOX_C_TILES = { 0, 14, 20, 4 }

-- header text sits inside box A, above the grid
Layout.HEADER_X, Layout.HEADER_Y = 8, 8

Layout.GRID_X, Layout.GRID_Y = 8, 16
Layout.COLS, Layout.ROWS = 5, 4

-- A column of Font.BORDER.v glyphs separating the grid from the sprite
-- panel, drawn in the same chrome as the frames around it.  Box A's
-- interior is 144px wide and the grid takes 80, so the divider's tile comes
-- out of the panel.  It spans the full interior height, down through the
-- count line.
Layout.DIVIDER_X = 88
Layout.DIVIDER_TOP = 8
Layout.DIVIDER_ROWS = 10  -- 10 x 8px spans the interior's 80px height

-- 56 wide, after the outer frame took it from 80 to 64 and the divider took
-- another tile.  56 is exactly a 7x7 sprite, the largest in Gen 1, so those
-- sit flush between the divider and the frame; 5x5 and 6x6 still centre
-- with margin.
Layout.PANEL_X, Layout.PANEL_Y = 96, 16
Layout.PANEL_W, Layout.PANEL_H = 56, 64

-- the identity plate (name over level) sits at the panel's top in both
-- modes: the count lives in the box window now, so the panel's header row
-- is free everywhere, and a floor-baseline 56px sprite clears it exactly
Layout.PLATE_Y = 8

-- horizontal centre of the sprite panel; consumers subtract half the
-- sprite's own width so sprites of any size centre correctly
Layout.SPRITE_CX = 124
-- on the frame floor, not lifted: the identity plate above needs every
-- pixel of headroom, so a tall sprite stands on the border instead of
-- floating 4px over it
Layout.SPRITE_BASELINE = 80

function Layout.spritePos(pw, ph)
  return Layout.SPRITE_CX - math.floor(pw / 2), Layout.SPRITE_BASELINE - ph
end

-- The pic's tile block, for the SGB zone that colours it on Gen 1.
--
-- A whole-screen zone alone paints the pic with whatever palette the screen
-- declared, and MEWMON -- what this screen declares, and what PaletteFX.monPal
-- returns for an UNKNOWN species -- then reads as the mod colouring every mon
-- wrong.  SummaryMenu carves the same block back out of its own screen with
-- the species palette (src/ui/SummaryMenu.lua:32); this is that rect here.
--
-- Fixed at 7x7 whatever the pic's real size, exactly as SummaryMenu's is: a
-- Gen 1 front pic is at most 56x56 and spritePos centres anything smaller
-- inside the same block, so a 5x5 pic's margin is bare white either way.
-- Sitting on SPRITE_BASELINE under a PLATE_Y plate it clears, the block owns
-- no chrome -- and shade 0/3 stay white/black across every named palette, so
-- the name and level above it would not shift even if it did.
Layout.SPRITE_MAX = 56

function Layout.spriteZone()
  local x, y = Layout.spritePos(Layout.SPRITE_MAX, Layout.SPRITE_MAX)
  local tx, ty = math.floor(x / 8), math.floor(y / 8)
  return tx, ty, tx + Layout.SPRITE_MAX / 8 - 1, ty + Layout.SPRITE_MAX / 8 - 1
end

-- Below the stats rather than above them, so the stats strip never shifts
-- when deposit mode opens.
Layout.PARTY_X, Layout.PARTY_Y = 8, 120
Layout.PARTY_SLOTS = 6

-- The box window's bottom line, inside box A under the grid: the count on
-- the left, the focused mon's HP on the right (under the sprite).
Layout.COUNT_Y = 80

-- The stats strip inside box B, a four-column table: a header row naming
-- the stats, the values under it, and the DVs under those (the DV row is
-- box view only -- deposit's party frame covers it).  Box B's interior is
-- five rows; the table takes three, then a blank row, then the type line
-- on the floor row, box view only for the same reason.
--
-- The types sit apart because they are not a fourth line of the table --
-- one word where every row above is four numbers, and since the "TY "
-- label came off, position is the only thing left to say so.  That spends
-- box B's spare row, so the strip has no slack: a new row has to come out
-- of the gap or out of the frame.
--
-- STATS_X is the label gutter, three glyphs wide, holding DV and the type
-- line.  The header and values rows leave it empty: the header names the
-- values, so only the second row of numbers needs telling apart.
Layout.STATS_X, Layout.STATS_Y = 8, 96

-- Column fields, 24px (three glyphs -- what SPC and a three-digit stat each
-- need), pitched 32px so a glyph of air separates them.  The last ends at
-- 120 + 24 = 144, a glyph short of box B's interior edge at 152.
--
-- That last glyph is deliberate.  The columns fit flush to 152, but text
-- hard against the frame is what made the old labeled type line look
-- cramped, and 144 is exactly where the previous layout's DEF and SPC
-- columns ended -- so this keeps the right margin the strip already had
-- rather than inventing a tighter one.  The gutter takes the other 8px:
-- x=8..24 is precisely "DV".
--
-- These are fields callers right-align INTO, not text origins: Font is
-- proportional under a TTF font pack (Font.advanceOf), where a 5px glyph
-- makes "%3d" space padding land columns wherever the spaces happen to
-- measure.  Right-aligning with Font.width holds the table under any pack.
Layout.STATS_COLS = { 24, 56, 88, 120 }
Layout.STATS_COL_W = 24

-- The same strip with FIVE fields, for a generation whose Special is two
-- stats rather than one.
--
-- Box B's interior is 144px (x=8..152).  Three things in it cannot move:
--
--   * The FIELD stays 24px.  A Gen 2 stat routinely reaches three digits
--     and three digits are exactly 24px, so a narrower field truncates.
--   * The GLYPH stays 8px.  Crystal's five extracted font pages declare no
--     `advance`, and the engine pins digits to the vanilla tiles even under
--     a TTF pack precisely so right-aligned numeric columns do not drift.
--   * The ROW stays 8px, and box B's interior is exactly five of them, so
--     there is no sixth row to move a column onto.
--
-- Five 24px fields are 120px, leaving 24px for everything else -- and Gen
-- 1's furniture (a 16px "DV" gutter, a glyph of air between each pair of
-- columns, an 8px right margin) wants 56.  Something had to go, and only
-- the gutter is big enough to pay for the rest.
--
--   [field 24][gap 4] x 4 [field 24][margin 8] = 144, flush.
--
-- WHY 4px, and not 8 or 0.  All three were rendered on real hardware-path
-- boots (Crystal, L100 Suicune: three digits in all five columns) and
-- looked at:
--
--   0px -- shipped in b56fb62 and rejected.  A three-digit value fills its
--          24px field edge to edge, so nothing separates it from its
--          neighbour: the row read `185253199215265`, one unbroken
--          fifteen-digit run.  Not "two values flush" -- all five.
--   2px -- the only width that also keeps the gutter (16 + 120 + 8 = 144),
--          so it was tried in order to save the "DV" label.  It does not
--          work.  The row still read as one run with a hairline in it, and
--          the last digit landed 1px off the frame.  This is why the label
--          is unaffordable rather than merely unfashionable.
--   4px -- reads.  The vanilla digit tiles do not ink their full 8px cell,
--          so 4px of layout gap presents as 5-6px of white and the eye
--          separates the groups without effort: `185 253 199 215 265`.
--   8px -- would be better still and does not fit.  Five fields and four
--          whole-glyph gaps are 152, eight more than the interior, before
--          any margin at all.
--
-- 4px is a HALF glyph, which is new here but not new to the screen: the
-- box header and the HP line have always centred on half-glyphs
-- (`48 - #label * 4`, `124 - #hpText * 4`).
--
-- Right edges land on 32, 60, 88, 116, 144.  The last is 144, the same
-- right edge the four-column layout ends on, so the strip's outer shape
-- does not change between generations; the left edge is the one that
-- moves, from 24 to STATS_X, because the gutter is gone.
--
-- Headers shorten to two letters.  Right-aligned into a 24px field, a
-- two-letter header leaves a leading blank glyph, so the header row is
-- separated by 12px where the value row is separated by 4 -- the row that
-- needs the least help gets the most air.  Three-letter headers would fill
-- the field and be separated by the same 4px as the digits.
Layout.STATS_COLS_5 = { 8, 36, 64, 92, 120 }
Layout.STATS_GAP_5 = 4

-- WHAT THIS COSTS, recorded because it was chosen with the picture in
-- front of us and should not read later as an oversight.
--
-- The gutter held the word "DV", and its loss leaves the Gen 2 DV row
-- unlabelled.  On a late-game mon that is fine: 1-2 digit DVs under a row
-- of three-digit stats are obviously a different kind of number.  On a
-- low-level mon it is genuinely ambiguous -- a level 6 Sentret renders
--
--     12  10   8  11  12      <- stats
--     15   9  12      15      <- DVs
--
-- two rows of two-digit numbers with nothing naming either.  The owner
-- accepted that, having seen it, over the alternative that would have kept
-- the label: moving the special pair to a line of its own, which reads
-- worse overall because it spends the blank separator row at y=120 and
-- leaves the type line running flush under the numbers again.
--
-- There is no room to put the label back.  Every DV is at most two glyphs,
-- so x=8..16 is free on this row -- one glyph, and "DV" needs two.

-- Where a DV that belongs to the FOURTH AND FIFTH fields at once is
-- centred.
--
-- Gen 2 kept Gen 1's DV structure even though the stats split: the
-- cartridge stores four DVs -- Attack, Defense, Speed, Special -- and
-- derives HP's from their parity, so one Special DV feeds both special
-- stats (src/battle/gen2/Mon.lua:169).  There is no fourth column to put it
-- in and no fifth either; it belongs to both.
--
-- 118 is the middle of the gap between those two fields (SA ends at 116,
-- SD begins at 120), so text centred on it straddles the pair and claims
-- neither.  Right-aligning it into field 4 would read as "SpD has no DV"
-- and into field 5 as the reverse, and both are false.
Layout.STATS_DV_SHARED_CX = 118

function Layout.slotXY(index)
  local i = index - 1
  return Layout.GRID_X + (i % Layout.COLS) * Layout.CELL,
         Layout.GRID_Y + math.floor(i / Layout.COLS) * Layout.CELL
end

function Layout.slotAt(col, row)
  return row * Layout.COLS + col + 1
end

function Layout.partyXY(index)
  return Layout.PARTY_X + (index - 1) * Layout.CELL, Layout.PARTY_Y
end

return Layout
