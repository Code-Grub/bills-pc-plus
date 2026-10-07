-- Standalone: luajit mods/bills_pc_plus/tests/shiny_mark_test.lua
--
-- The shiny mark on grid icons: two diamonds in a shiny Pokemon's cell, none
-- on anyone else.  Its geometry is layout_test.lua; this is that the grid
-- actually draws it, where, and for whom.  Separate from
-- bills_pc_plus_test.lua because that file sits at LuaJIT's 200-local ceiling.
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local T = require("tests.modkit")
local Data = require("tests.modkit.fixtures").fresh()
local Screens = require("src.ui.Screens")

local run = T.sdk.loadMod("mods/bills_pc_plus", { data = Data })
T.eq(#run.errors, 0, "loads clean (" .. tostring(run.errors[1]) .. ")")
Screens.invalidate()
local L = dofile("mods/bills_pc_plus/Layout.lua")

local SHINY = { attack = 15, defense = 10, speed = 10, special = 10 }
local PLAIN = { attack = 8, defense = 8, speed = 8, special = 8 }
local function mon(dvs, extra)
  local m = {
    species = "FIXMON_A", level = 12, hp = 20, dvs = dvs, statExp = {},
    moves = {},
    stats = { hp = 20, attack = 12, defense = 12, speed = 12, special = 12 } }
  for k, v in pairs(extra or {}) do m[k] = v end
  return m
end

-- slot 1 shiny, 2 plain, 3 a shiny egg, 4 shiny again; the cursor goes on an
-- empty slot so no cursor stub is drawn inside a cell under test
local function openGrid()
  local g = {
    data = Data,
    save = { party = {}, boxes = { {
      mon(SHINY), mon(PLAIN), mon(SHINY, { isEgg = true }), mon(SHINY),
    } }, currentBox = 1 },
    input = { wasPressed = function() return false end,
              isDown = function() return false end },
  }
  local captured = {}
  g.stack = { push = function(_, st) captured[#captured + 1] = st end,
              pop = function() end }
  local menu = Screens.get(g, "BoxMenu").new(g)
  for _, item in ipairs(menu.items) do
    if item.label == "WITHDRAW POKéMON" and item.onSelect then item.onSelect() end
  end
  return captured[#captured]
end

-- every filled rectangle one draw makes, with the colour it was set to
local function fills(grid)
  local out, color = {}, { 1, 1, 1, 1 }
  local G = love.graphics
  local realRect, realColor = G.rectangle, G.setColor
  G.setColor = function(r, g, b, a)
    if type(r) == "table" then r, g, b, a = r[1], r[2], r[3], r[4] end
    color = { r, g, b, a }
    return realColor(r, g, b, a)
  end
  G.rectangle = function(mode, x, y, w, h)
    out[#out + 1] = { x = x, y = y, w = w, h = h, black = color[1] == 0 }
    return realRect(mode, x, y, w, h)
  end
  local ok, err = pcall(function() grid:draw() end)
  G.rectangle, G.setColor = realRect, realColor
  if not ok then error(err, 0) end
  return out
end

-- how many of the mark's rows were painted in the cell at (cx, cy)
local function markRows(all, cx, cy)
  local n = 0
  for _, r in ipairs(L.SHINY_MARK) do
    for _, f in ipairs(all) do
      if f.x == cx + r.x and f.y == cy + r.y and f.w == r.w
          and f.h == 1 and f.black == r.black then
        n = n + 1
        break
      end
    end
  end
  return n
end

local grid = openGrid()
grid.cursor = 6
grid.counter = 0
local all = fills(grid)
local total = #L.SHINY_MARK

local x1, y1 = L.slotXY(1)
T.eq(markRows(all, x1, y1), total, "a shiny Pokemon's cell carries the whole mark")
local x2, y2 = L.slotXY(2)
T.eq(markRows(all, x2, y2), 0, "a plain Pokemon's cell carries none of it")
local x3, y3 = L.slotXY(3)
T.eq(markRows(all, x3, y3), 0, "a shiny egg carries none: its shininess is the hatchling's")
local x4, y4 = L.slotXY(4)
T.eq(markRows(all, x4, y4), total, "and another shiny after it still does")
local x6, y6 = L.slotXY(6)
T.eq(markRows(all, x6, y6), 0, "an empty cell carries none")

-- the mark is painted AFTER the icon, so nothing of the icon covers it: it is
-- the last thing drawn in its cell
local lastInCell = 0
for i, f in ipairs(all) do
  if f.x >= x1 and f.x < x1 + L.CELL and f.y >= y1 and f.y < y1 + L.CELL then
    lastInCell = i
  end
end
local lastMark = all[lastInCell]
T.check(lastMark and lastMark.black == false and lastMark.w == 1,
  "the last fill in the cell is the small diamond's white centre")

run.release()
Screens.invalidate()
T.finish("bills_pc_plus shiny_mark")
