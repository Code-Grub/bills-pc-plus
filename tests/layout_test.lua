-- Standalone: luajit mods/bills_pc_plus/tests/layout_test.lua
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local T = require("tests.modkit")
local L = dofile("mods/bills_pc_plus/Layout.lua")

-- the grid is a 5x4 block of 16px cells anchored at the frame's interior
-- corner; assertions are relative to GRID_X/GRID_Y so a future reframe
-- moves the block without invalidating the arithmetic under test
local x, y = L.slotXY(1)
T.eq(x, L.GRID_X, "slot 1 sits at the grid's left edge")
T.eq(y, L.GRID_Y, "slot 1 sits at the grid's top edge")

x, y = L.slotXY(5)
T.eq(x, L.GRID_X + 4 * L.CELL, "slot 5 is the last column")
T.eq(y, L.GRID_Y, "slot 5 is still the first row")

x, y = L.slotXY(6)
T.eq(x, L.GRID_X, "slot 6 wraps to the next row")
T.eq(y, L.GRID_Y + L.CELL, "slot 6 is one cell down")

x, y = L.slotXY(20)
T.eq(x, L.GRID_X + 4 * L.CELL, "slot 20 is the last column")
T.eq(y, L.GRID_Y + 3 * L.CELL, "slot 20 is the last row")
local aFloor = (L.BOX_A_TILES[2] + L.BOX_A_TILES[4] - 1) * 8
T.eq(y + L.CELL, aFloor, "the grid ends exactly at box A's interior floor")

-- slotAt is the inverse of slotXY's cell arithmetic
T.eq(L.slotAt(0, 0), 1, "col 0 row 0 is slot 1")
T.eq(L.slotAt(4, 0), 5, "col 4 row 0 is slot 5")
T.eq(L.slotAt(0, 1), 6, "col 0 row 1 is slot 6")
T.eq(L.slotAt(4, 3), 20, "col 4 row 3 is slot 20")

-- every slot round-trips
for i = 1, L.COLS * L.ROWS do
  local sx, sy = L.slotXY(i)
  local col = (sx - L.GRID_X) / L.CELL
  local row = (sy - L.GRID_Y) / L.CELL
  T.eq(L.slotAt(col, row), i, "slot " .. i .. " round-trips")
end

-- the party row is six cells starting at the frame's interior left edge
local px, py = L.partyXY(1)
T.eq(px, L.PARTY_X, "party slot 1 sits at the interior left edge")
T.eq(py, L.PARTY_Y, "the party row sits on the PARTY_Y baseline")
px = L.partyXY(6)
T.eq(px, L.PARTY_X + 5 * L.CELL, "six party cells span 96px from the left edge")

-- the whole composition adds up to the Game Boy screen
T.eq(L.STATS_Y + 4 * L.ROW, L.PARTY_Y, "four stat rows end where the party row begins")
T.check(L.PARTY_Y + L.CELL <= 144, "the composition fits the 144px canvas")

-- sprite centring: SPRITE_CX is the panel centre, so consumers can subtract
-- half the sprite's width and get the correct left edge for any sprite size
local sprite56_left = L.SPRITE_CX - math.floor(56 / 2)
T.eq(sprite56_left, L.PANEL_X, "a 56px sprite fills the panel, flush to the divider")
local sprite56_right = sprite56_left + 56
T.eq(sprite56_right, L.PANEL_X + L.PANEL_W, "and flush to the frame's inner edge")
T.check(sprite56_left >= L.PANEL_X, "a 56px sprite never crosses into the grid")
T.check(sprite56_right <= L.PANEL_X + L.PANEL_W, "56px sprite fits within panel")

local sprite40_left = L.SPRITE_CX - math.floor(40 / 2)
T.eq(sprite40_left, L.PANEL_X + 8, "a 40px sprite centres with 8px either side")
local sprite40_right = sprite40_left + 40
T.eq(sprite40_right, L.PANEL_X + L.PANEL_W - 8, "a 40px sprite ends 8px short of the frame")
T.check(sprite40_left >= L.PANEL_X, "a 40px sprite never crosses into the grid")
T.check(sprite40_right <= L.PANEL_X + L.PANEL_W, "40px sprite fits within panel")
-- verify equal margins for 40px sprite
local left_margin = sprite40_left - L.PANEL_X
local right_margin = (L.PANEL_X + L.PANEL_W) - sprite40_right
T.eq(left_margin, right_margin, "40px sprite has equal margins in panel (visually centred)")

-- ------- framed layout: two stacked boxes sharing a border row
-- Font.drawBox(tx, ty, tw, th) takes TILE coords, fills the area white and
-- draws a 1-tile border, so every framed region loses 8px on each side.
-- Box A = drawBox(0, 0, 20, 11): interior px x=8..152, y=8..80
-- Box B = drawBox(0, 10, 20, 8): interior px x=8..152, y=88..136
local IN_L, IN_R = 8, 152
local A_TOP, A_BOT = 8, 80
local B_TOP, B_BOT = 88, 136

T.eq(L.BOX_A_TILES ~= nil, true, "Layout names box A's tile rect")
T.eq(table.concat(L.BOX_A_TILES, ","), "0,0,20,11", "box A frames header, grid and panel")
T.eq(table.concat(L.BOX_B_TILES, ","), "0,10,20,8", "box B frames stats and the party row")

-- everything lives inside the frames
T.eq(L.GRID_X, IN_L, "the grid starts one tile in from the left edge")
local lastX = select(1, L.slotXY(L.COLS))
T.eq(lastX + L.CELL, IN_L + 80, "five 16px cells end 80px after the grid's left edge")
T.eq(select(2, L.slotXY(L.COLS * L.ROWS)) + L.CELL, A_BOT,
  "the grid's last row ends exactly at box A's interior bottom")

T.eq(L.PANEL_X, IN_L + 80 + 8, "the sprite panel starts after the grid and the divider")
T.eq(L.PANEL_W, 56, "the panel is 56px after the frame and the divider take their tiles")
T.eq(L.PANEL_X + L.PANEL_W, IN_R, "the panel ends at box A's interior right edge")
T.eq(L.SPRITE_CX, L.PANEL_X + L.PANEL_W / 2, "SPRITE_CX is still the panel's centre")
T.eq(A_BOT - L.SPRITE_BASELINE, 0, "sprites stand on box A's interior floor, clearing headroom for the plate")

-- a 56px sprite, the widest in Gen 1, fills the panel exactly
local left56 = L.SPRITE_CX - math.floor(56 / 2)
T.eq(left56, L.PANEL_X, "a 56px sprite starts at the panel's left edge")
T.check(left56 >= L.PANEL_X, "a 56px sprite does not overlap the grid")
T.check(left56 + 56 <= IN_R, "a 56px sprite stays inside the frame")

-- stats sit at a fixed place in both modes; the party row goes below them
T.eq(L.STATS_X, IN_L, "stats start one tile in")
T.eq(L.STATS_Y, B_TOP, "stats start at box B's interior top")
T.eq(L.STATS_Y + 4 * L.ROW, 120, "four stat rows end at y=120")
T.eq(L.PARTY_X, IN_L, "the party row starts one tile in")
T.eq(L.PARTY_Y, 120, "the party row sits below the stats, not above")
T.eq(L.PARTY_Y + L.CELL, B_BOT, "the party row ends at box B's interior bottom")
local px6 = L.partyXY(L.PARTY_SLOTS)
T.check(px6 + L.CELL <= IN_R, "six party cells stay inside the frame")

-- ------- the party row gets its own frame in deposit mode
-- Box C is drawn OVER the lower part of box B, which box mode leaves empty
-- anyway.  Its interior must land exactly on the existing PARTY_Y so no
-- layout constant has to move.
T.eq(table.concat(L.BOX_C_TILES, ","), "0,14,20,4", "box C frames the party row")
local cx, cy, cw, ch = L.BOX_C_TILES[1], L.BOX_C_TILES[2], L.BOX_C_TILES[3], L.BOX_C_TILES[4]
T.eq((cy + 1) * 8, L.PARTY_Y, "box C's interior top is the party row's baseline")
T.eq((cy + ch - 1) * 8, L.PARTY_Y + L.CELL, "box C's bottom border sits under the icons")
T.eq((cy + ch) * 8, 144, "box C ends flush with the bottom of the screen")
T.eq((cx + 1) * 8, L.PARTY_X, "box C's interior left edge is the party row's left edge")
T.eq((cx + cw - 1) * 8, 152, "box C spans the full width, like the boxes above it")

-- the identity plate rides above the sprite, at the panel's content top,
-- in both modes: the count lives in the box window now, so the panel's
-- header row is free everywhere
T.eq(L.PLATE_Y, 8, "the plate takes the panel's header row in both modes")
T.eq(L.SPRITE_BASELINE - 56, L.PLATE_Y + 16,
  "a 56px sprite's top clears the plate exactly")

-- the strip runs HP, ATK/DEF, SPD/SPC; box C covers the type line, so
-- deposit mode shows the three stat rows and box view gets types as its
-- bonus row
T.eq(L.STATS_Y + 3 * L.ROW, cy * 8,
  "the last deposit-visible stat row ends where box C's border starts")

-- ------- the divider between the grid and the sprite panel
-- Box A's interior is 144px and the grid takes 80 of it, so the divider
-- tile comes out of the panel: 64 -> 56, which is exactly a 7x7 sprite.
T.eq(L.DIVIDER_X, L.GRID_X + 5 * L.CELL, "the divider sits where the grid ends")
T.eq(L.DIVIDER_X, 88, "the divider column starts at x=88")
T.eq(L.DIVIDER_TOP, 16, "the divider starts at the grid's top, under the header row")
T.eq(L.DIVIDER_ROWS, 8, "eight 8px glyphs span the grid's 64px height")
T.eq(L.DIVIDER_TOP + L.DIVIDER_ROWS * L.ROW, A_BOT,
  "the divider ends flush with box A's interior floor")

T.eq(L.PANEL_X, L.DIVIDER_X + 8, "the panel starts after the divider tile")
T.eq(L.PANEL_W, 56, "the panel narrows to 56px, the width of the largest sprite")
T.eq(L.PANEL_X + L.PANEL_W, 152, "the panel still ends at the frame's inner edge")
T.eq(L.SPRITE_CX, L.PANEL_X + L.PANEL_W / 2, "SPRITE_CX tracks the narrowed panel")
T.eq(L.SPRITE_CX, 124, "the sprite centre moves to 124")

-- a 7x7 sprite fits exactly; smaller ones still centre with margin
local left56 = L.SPRITE_CX - math.floor(56 / 2)
T.eq(left56, L.PANEL_X, "a 56px sprite fills the panel exactly, flush to the divider")
T.eq(left56 + 56, 152, "and flush to the frame's inner edge")
local left40 = L.SPRITE_CX - math.floor(40 / 2)
T.check(left40 > L.PANEL_X, "a 40px sprite keeps margin on the divider side")
T.check(left40 + 40 < 152, "and on the frame side")
T.eq(left40 - L.PANEL_X, 152 - (left40 + 40), "a smaller sprite stays centred")

-- ------- the sprite stands on the frame's floor
-- The identity plate owns the panel's top two rows, so the baseline sits
-- on the interior floor: every pixel of headroom goes to the sprite, and
-- the tallest sprites keep their heads out from under the plate as far as
-- the box allows.
T.eq(L.SPRITE_BASELINE, 80, "the sprite baseline is the interior floor")
T.eq(A_BOT - L.SPRITE_BASELINE, 0, "no float -- the floor is the baseline")

-- a 56px sprite's top reaches y=24, under the plate's bottom edge (32) --
-- the plate bites 8px of the tallest sprites, 4px of 52px ones, and
-- nothing 48px or shorter
local top56 = L.SPRITE_BASELINE - 56
T.eq(top56, 24, "the tallest sprite starts at y=24")
T.check(top56 >= A_TOP, "and stays inside box A's interior")

T.finish("bills_pc_plus layout")
