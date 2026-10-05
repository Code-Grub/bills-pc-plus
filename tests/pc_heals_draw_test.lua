-- Standalone: luajit mods/bills_pc_plus/tests/pc_heals_draw_test.lua
--
-- PC HEALS on the screen: the option row, the HP line it removes, and the
-- session it arms.  The healing rules themselves are pc_heals_test.lua; where
-- the sprite stands is panel_sprite_test.lua.
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local T = require("tests.modkit")
local Data = require("tests.modkit.fixtures").fresh()
local Font = require("src.render.Font")
local Screens = require("src.ui.Screens")

local run = T.sdk.loadMod("mods/bills_pc_plus", { data = Data })
T.eq(#run.errors, 0, "loads clean (" .. tostring(run.errors[1]) .. ")")
Screens.invalidate()

local row
for _, r in ipairs(run.loader.optionSchemas.bills_pc_plus or {}) do
  if r.key == "pc_heals" then row = r end
end
T.check(row ~= nil, "the mod defines a pc_heals option row")
T.eq(row and row.type, "toggle", "it is a toggle")
T.eq(row and row.label, "PC HEALS", "labelled PC HEALS")
T.eq(row and row.default, true, "and it defaults on")

local function openGrid()
  local g = {
    data = Data,
    save = { party = {}, boxes = { { {
      species = "FIXMON_A", level = 12, hp = 7,
      dvs = { attack = 15, defense = 10, speed = 10, special = 10 },
      statExp = {}, moves = {},
      stats = { hp = 20, attack = 12, defense = 12, speed = 12, special = 12 } } } },
      currentBox = 1 },
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

local function textsOf(grid)
  local texts, real = {}, Font.draw
  Font.draw = function(text, x, y)
    texts[#texts + 1] = { text = tostring(text), x = x, y = y }
    return real(text, x, y)
  end
  local ok, err = pcall(function() grid:draw() end)
  Font.draw = real
  if not ok then error(err, 0) end
  return function(t)
    for _, d in ipairs(texts) do if d.text == t then return d end end
  end
end

-- default on: no HP line, but the box count under the grid stays
run.loader.modOptions.bills_pc_plus = nil
local grid = openGrid()
grid.counter = 0
local drew = textsOf(grid)
T.eq(drew("7/20"), nil, "with PC HEALS on the HP line is not drawn")
T.check(drew("1/20") ~= nil, "but the box count under the grid still is")
T.eq(grid.session:heals(), true, "and the session heals")

-- off: today's screen, the line back where it was
run.loader.modOptions.bills_pc_plus = { pc_heals = false }
drew = textsOf(grid)
local hp = drew("7/20")
T.check(hp ~= nil, "with the option off the HP line returns, on the very next draw")
T.eq(hp and hp.x, 108, "centred under the sprite")
T.eq(hp and hp.y, 80, "on the box window's bottom line")
T.eq(grid.session:heals(), false, "and the session stops healing")

run.loader.modOptions.bills_pc_plus = nil
run.release()
Screens.invalidate()
T.finish("bills_pc_plus pc_heals drawing")
