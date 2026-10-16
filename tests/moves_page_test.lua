-- Standalone: luajit mods/bills_pc_plus/tests/moves_page_test.lua
--
-- The MOVES PAGE: SELECT flips box view's stats strip to the focused Pokemon's
-- four moves, each behind a chip in its type's colour, with a pair of page dots
-- in the strip's top-right corner.  The pure arithmetic is in Layout and
-- TypeBadges; this file is the wiring.  Its own file because
-- bills_pc_plus_test.lua is at LuaJIT's 200-local ceiling.
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local T = require("tests.modkit")
local Data = require("tests.modkit.fixtures").fresh()
local Font = require("src.render.Font")
local PaletteFX = require("src.render.PaletteFX")
local gfx = love.graphics
local L = dofile("mods/bills_pc_plus/Layout.lua")
local B = dofile("mods/bills_pc_plus/TypeBadges.lua")
local Engine = dofile("mods/bills_pc_plus/Engine.lua")

-- ------- the pure parts
T.eq(L.MOVE_SLOTS, 4, "a Pokemon knows at most four moves")
T.eq(L.moveRowY(1), L.STATS_Y, "the first move sits on the strip's top row")
T.eq(L.moveRowY(4), L.STATS_Y + 3 * L.ROW, "the fourth three rows down")
T.check(L.moveRowY(4) + L.ROW <= 136, "and all four fit inside box B's interior")
T.check(L.MOVE_NAME_X > L.MOVE_CHIP_X + L.MOVE_CHIP, "the name starts after the chip")
-- the longest move name either generation prints is 12 glyphs
T.check(L.MOVE_NAME_X + 12 * 8 <= 152, "a 12-glyph move name ends inside the frame")
T.eq(#L.PAGE_DOTS.ys, 2, "two pages, two dots")
T.check(L.PAGE_DOTS.x >= 144 and L.PAGE_DOTS.x + L.PAGE_DOTS.size <= 152,
  "the dots live in the margin right of the stat columns")

-- the seam: only Gen 1 has the page for now
T.eq(Engine.new(false):hasMovesPage(), true, "Gen 1 has the moves page")
T.eq(Engine.new(true):hasMovesPage(), false, "Gen 2 does not, yet")

-- ------- a chip
local rects, marks = {}, {}
do
  local realRect, realColor = gfx.rectangle, gfx.setColor
  local color = { 1, 1, 1, 1 }
  gfx.setColor = function(r, g, b, a)
    if type(r) == "table" then r, g, b, a = r[1], r[2], r[3], r[4] end
    color = { r, g, b, a or 1 }
  end
  gfx.rectangle = function(mode, x, y, w, h)
    rects[#rects + 1] = { x = x, y = y, w = w, h = h, color = { color[1], color[2], color[3] } }
  end
  local ok, err = pcall(B.drawChip, "FIRE", 11, 96, L.MOVE_CHIP)
  gfx.rectangle, gfx.setColor = realRect, realColor
  if not ok then error(err, 0) end
end
local FIRE = B.color("FIRE")
local filled = false
for _, r in ipairs(rects) do
  if math.abs(r.color[1] - FIRE[1] / 255) < 1e-6 then filled = true end
  T.check(r.x >= 11 and r.x + r.w <= 11 + L.MOVE_CHIP and r.y >= 96 and r.y + r.h <= 96 + L.MOVE_CHIP,
    "no chip rectangle strays outside its square")
end
T.check(filled, "a chip is filled in its type's own colour")

-- ------- the option and the screen
local run = T.sdk.loadMod("mods/bills_pc_plus", { data = Data })
T.eq(#run.errors, 0, "loads clean (" .. tostring(run.errors[1]) .. ")")
local Screens = require("src.ui.Screens")
Screens.invalidate()

local row
for _, r in ipairs(run.loader.optionSchemas.bills_pc_plus or {}) do
  if r.key == "moves_page" then row = r end
end
T.check(row ~= nil, "the mod defines a moves_page option row")
T.eq(row and row.type, "toggle", "it is a toggle")
T.eq(row and row.label, "MOVES PAGE", "labelled MOVES PAGE")
T.eq(row and row.default, true, "and it defaults on")

Data.moves = Data.moves or {}
Data.moves.FIX_TACKLE = { name = "SELFDESTRUCT", type = "NORMAL_TYPE", pp = 5 }
Data.moves.FIX_SCRATCH = { name = "EMBER", type = "FIRE", pp = 25 }
Data.moves.FIX_EMBERISH = { name = "SWORDS DANCE", type = "NORMAL_TYPE", pp = 30 }
Data.moves.FIX_CUT = { name = "CUT", type = "NORMAL_TYPE", pp = 30 }

local function monWith(moves)
  local list = {}
  for i, id in ipairs(moves) do list[i] = { id = id, pp = 5, ppUps = 0 } end
  return { species = "FIXMON_A", level = 12, hp = 20,
    dvs = { attack = 15, defense = 10, speed = 10, special = 10 },
    statExp = {}, moves = list,
    stats = { hp = 20, attack = 12, defense = 12, speed = 12, special = 12 } }
end

local pressed = nil
local function gameWith(boxMons)
  return {
    data = Data,
    save = { party = { monWith({ "FIX_CUT" }) }, boxes = { boxMons }, currentBox = 1 },
    stack = { push = function() end, pop = function() end },
    input = { wasPressed = function(_, b) return b == pressed end,
              isDown = function() return false end },
  }
end

local function openGrid(g, rowLabel)
  local captured = {}
  local realStack = g.stack
  g.stack = { push = function(_, st) captured[#captured + 1] = st end,
              pop = function() end }
  local menu = Screens.get(g, "BoxMenu").new(g)
  for _, item in ipairs(menu.items) do
    if item.label == rowLabel and item.onSelect then item.onSelect() end
  end
  g.stack = realStack
  return captured[#captured]
end

local function tap(grid, button)
  pressed = button
  grid:update(0)
  pressed = nil
end

local function drawOnce(grid)
  local texts, rects, chipRects, mks = {}, {}, {}, {}
  local realDraw, realRect, realMark = Font.draw, gfx.rectangle, PaletteFX.markTrueColor
  Font.draw = function(text, x, y)
    texts[#texts + 1] = { text = tostring(text), x = x, y = y }
    return realDraw(text, x, y)
  end
  gfx.rectangle = function(mode, x, y, w, h)
    rects[#rects + 1] = { mode = mode, x = x, y = y, w = w, h = h }
    return realRect(mode, x, y, w, h)
  end
  PaletteFX.markTrueColor = function(x, y, w, h)
    mks[#mks + 1] = { x = x, y = y, w = w, h = h }
    return realMark(x, y, w, h)
  end
  local ok, err = pcall(function() grid.counter = 0; grid:draw() end)
  Font.draw, gfx.rectangle, PaletteFX.markTrueColor = realDraw, realRect, realMark
  if not ok then error(err, 0) end
  local function drew(t)
    for _, d in ipairs(texts) do if d.text == t then return d end end
  end
  -- the page dots: rectangles inside the dot column, split filled / hollow
  local dots = { filled = 0, any = 0 }
  for _, r in ipairs(rects) do
    if r.x >= L.PAGE_DOTS.x and r.x + r.w <= L.PAGE_DOTS.x + L.PAGE_DOTS.size
        and r.y >= L.PAGE_DOTS.ys[1] and r.y + r.h <= L.PAGE_DOTS.ys[2] + L.PAGE_DOTS.size then
      dots.any = dots.any + 1
      if r.w == L.PAGE_DOTS.size and r.h == L.PAGE_DOTS.size then dots.filled = dots.filled + 1 end
    end
  end
  return { texts = texts, rects = rects, marks = mks, drew = drew, dots = dots }
end

local MOVES = { "FIX_TACKLE", "FIX_SCRATCH", "FIX_EMBERISH" }   -- three of four
local G = gameWith({ monWith(MOVES), monWith({ "FIX_CUT" }) })
local grid = openGrid(G, "WITHDRAW POKéMON")
run.loader.modOptions.bills_pc_plus = nil

-- page 1 is today's strip, plus the dots with the first one filled
local d = drawOnce(grid)
T.check(d.drew("ATK") ~= nil, "page 1 is the stats table")
T.check(d.drew("SELFDESTRUCT") == nil, "and shows no moves")
T.eq(d.dots.filled, 1, "the dots show page 1: the first filled")
T.check(d.dots.any > 1, "and the second drawn hollow")

-- SELECT flips to the moves page
tap(grid, "select")
d = drawOnce(grid)
T.check(d.drew("ATK") == nil, "page 2 replaces the stats table")
for i, name in ipairs({ "SELFDESTRUCT", "EMBER", "SWORDS DANCE" }) do
  local t = d.drew(name)
  T.check(t ~= nil, name .. " is listed")
  T.eq(t and t.y, L.moveRowY(i), name .. " on its own row")
  T.eq(t and t.x, L.MOVE_NAME_X, name .. " after the chip")
end
local dash = d.drew("-")
T.check(dash ~= nil, "an empty fourth slot draws a dash, as the summary screen does")
T.eq(dash and dash.y, L.moveRowY(4), "on the fourth row")
T.eq(#d.marks, 3, "each chip is exempted from palette shading (three moves, three chips)")
T.eq(d.dots.filled, 1, "the dots show page 2: still one filled")
local firstDotY
for _, r in ipairs(d.rects) do
  if r.w == L.PAGE_DOTS.size and r.h == L.PAGE_DOTS.size and r.x == L.PAGE_DOTS.x then
    firstDotY = r.y
  end
end
T.eq(firstDotY, L.PAGE_DOTS.ys[2], "and it is the second dot")

-- the page holds while the cursor moves on to another Pokemon
grid.cursor = 2
d = drawOnce(grid)
T.check(d.drew("CUT") ~= nil, "browsing keeps the moves page open")
T.check(d.drew("ATK") == nil, "and the stats stay hidden")

-- an empty cell: the page is still the page, and nothing is listed
grid.cursor = 7
d = drawOnce(grid)
T.check(d.drew("CUT") == nil and d.drew("-") == nil, "an empty cell lists no moves")
T.check(d.dots.any > 0, "but the dots still show which page this is")

-- SELECT again returns to the stats
grid.cursor = 1
tap(grid, "select")
d = drawOnce(grid)
T.check(d.drew("ATK") ~= nil and d.drew("SELFDESTRUCT") == nil, "SELECT again returns to the stats")

-- the option off: SELECT does nothing and the dots are gone
run.loader.modOptions.bills_pc_plus = { moves_page = false }
tap(grid, "select")
d = drawOnce(grid)
T.check(d.drew("ATK") ~= nil and d.drew("SELFDESTRUCT") == nil, "with the option off SELECT does nothing")
T.eq(d.dots.any, 0, "and no dots are drawn")
run.loader.modOptions.bills_pc_plus = nil

-- deposit mode: box C covers the strip's lower rows, so there is no page
local dep = openGrid(gameWith({ monWith(MOVES) }), "DEPOSIT POKéMON")
tap(dep, "select")
d = drawOnce(dep)
T.check(d.drew("CUT") == nil, "deposit mode ignores SELECT")
T.eq(d.dots.any, 0, "and draws no dots")

run.release()
Screens.invalidate()
T.finish("bills_pc_plus moves page")
