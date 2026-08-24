-- Pure geometry for the box screen, in native pixels on the 160x144
-- canvas.  Font.GLYPH is 8, so the screen is 20x18 characters and every
-- constant here is a multiple of 8.
--
-- The screen is framed by two stacked Game Boy boxes that share their
-- border row, the way adjacent boxes meet in the original.  Font.drawBox
-- takes TILE coords, fills its area white and draws a 1-tile border, so a
-- framed region loses 8px on every side:
--
--   Box A = (0, 0, 20, 11)  interior px x=8..152, y=8..80
--           header, the grid, and the sprite panel
--   Box B = (0, 10, 20, 8)  interior px x=8..152, y=88..136
--           the stats strip, and the party row in deposit mode
--
-- Row 10 is both A's bottom border and B's top, drawn once as a shared
-- line.  Box B must therefore be drawn AFTER box A and BEFORE any content,
-- since drawBox's white fill erases whatever it covers.

local Layout = {}

Layout.CELL = 16
-- Length of each cursor corner arm, in pixels.  5 of a 16px cell reads as a
-- bracket with the edge left open in the middle.
Layout.CURSOR_ARM = 5
Layout.ROW = 8

-- tile rects for the two frames, as drawBox takes them
Layout.BOX_A_TILES = { 0, 0, 20, 11 }
Layout.BOX_B_TILES = { 0, 10, 20, 8 }
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
-- out of the panel.  It starts at the grid's top, not the header's: the
-- header row belongs to the box label and count, which cross this column
-- on their way across the window.
Layout.DIVIDER_X = 88
Layout.DIVIDER_TOP = 16
Layout.DIVIDER_ROWS = 8   -- 8 x 8px spans the grid's 64px height

-- 56 wide, after the outer frame took it from 80 to 64 and the divider took
-- another tile.  56 is exactly a 7x7 sprite, the largest in Gen 1, so those
-- sit flush between the divider and the frame; 5x5 and 6x6 still centre
-- with margin.
Layout.PANEL_X, Layout.PANEL_Y = 96, 16
Layout.PANEL_W, Layout.PANEL_H = 56, 64

-- the identity plate (name over level) sits at the panel's top.  Box view
-- puts it on the header row -- the count moved to the box window -- so a
-- 56px sprite at its floor baseline clears it exactly; deposit's count
-- keeps that row, so the plate holds one row lower there.
Layout.PLATE_Y = 8
Layout.PLATE_Y_DEPOSIT = 16

-- horizontal centre of the sprite panel; consumers subtract half the
-- sprite's own width so sprites of any size centre correctly
Layout.SPRITE_CX = 124
-- on the frame floor, not lifted: the identity plate above needs every
-- pixel of headroom, so a tall sprite stands on the border instead of
-- floating 4px over it
Layout.SPRITE_BASELINE = 80

-- Below the stats rather than above them, so the stats strip never shifts
-- when deposit mode opens.
Layout.PARTY_X, Layout.PARTY_Y = 8, 120
Layout.PARTY_SLOTS = 6

Layout.STATS_X, Layout.STATS_Y = 8, 88

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
