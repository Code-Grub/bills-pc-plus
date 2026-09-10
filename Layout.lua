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
-- Box B's interior is 18 glyphs (x=8..152).  The four-column layout above
-- spends [gutter 2][gap 1][field 3] x 4 + [margin 1] = 17, and a fifth
-- column on that pattern needs 19 -- one more than exists.  The fields
-- cannot shrink either: a Gen 2 stat routinely reaches three digits, which
-- is exactly what 24px holds.
--
-- So the gaps go and nothing else does: [gutter 2][field 3] x 5
-- [margin 1] = 18, flush.  The gutter is still precisely "DV" at x=8..24
-- and the right margin is still the glyph of air at 144..152 that keeps the
-- table off the frame -- the two things the four-column layout was careful
-- about are the two things kept.  What pays for the column is the air
-- BETWEEN columns, which the headers give back: two-letter headers
-- right-aligned into a three-glyph field leave a leading blank glyph, so
-- every column still opens with a space.  A three-letter header here would
-- run into its neighbour, which is why the callers that use these fields
-- shorten theirs.
--
-- Right edges land on 48, 72, 96, 120, 144: pitch 24, the field width
-- itself.  The last is 144, the same right edge the four-column layout
-- ends on, so the strip's outer shape does not change between generations.
Layout.STATS_COLS_5 = { 24, 48, 72, 96, 120 }

-- Where a DV that belongs to the FOURTH AND FIFTH fields at once is
-- centred.
--
-- Gen 2 kept Gen 1's DV structure even though the stats split: the
-- cartridge stores four DVs -- Attack, Defense, Speed, Special -- and
-- derives HP's from their parity, so one Special DV feeds both special
-- stats (src/battle/gen2/Mon.lua:169).  There is no fourth column to put it
-- in and no fifth either; it belongs to both.
--
-- 120 is the seam between those two fields (field 4 ends there, field 5
-- begins there), so text centred on it straddles the pair and claims
-- neither.  Right-aligning it into field 4 would read as "SpD has no DV"
-- and into field 5 as the reverse, and both are false.
Layout.STATS_DV_SHARED_CX = 120

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
