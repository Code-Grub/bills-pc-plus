-- Standalone: luajit mods/bills_pc_plus/tests/speed_category_test.lua
--
-- The grid replaces vanilla's BoxMenu, which the engine marks isMenu so
-- MENU SPEED governs it (Game.speedCategoryInStack).  The grid has to carry
-- the same mark.  Unmarked, the stack walk skips it and finds the overworld
-- under the PC, so the grid ran at OVERWORLD SPEED: fast beside every other
-- menu once that option sat above 1X.
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local T = require("tests.modkit")
local Screens = require("src.ui.Screens")
local Game = require("src.core.Game")

local run = T.sdk.loadMods({ "mods/bills_pc_plus" })
T.eq(#run.errors, 0, "loads clean (" .. tostring(run.errors[1]) .. ")")

Screens.invalidate()
local g = { data = run.data, save = { party = {}, boxes = nil, currentBox = 1 } }
local states = { { isOverworld = true } }
g.stack = {
  states = states,
  push = function(_, st) states[#states + 1] = st end,
  pop = function() return table.remove(states) end,
  top = function() return states[#states] end,
}
g.input = { wasPressed = function() return false end,
            isDown = function() return false end }

T.eq(Game.speedCategoryInStack(g.stack), "overworld",
  "with only the overworld up, the overworld speed applies")

local menu = Screens.get(g, "BoxMenu").new(g)
g.stack:push(menu)
T.eq(Game.speedCategoryInStack(g.stack), "menu",
  "the PC menu over the overworld runs at MENU SPEED")

for _, item in ipairs(menu.items) do
  if item.label == "WITHDRAW POKéMON" then item.onSelect() end
end
T.check(g.stack:top() ~= menu, "WITHDRAW pushed the grid")
T.eq(Game.speedCategoryInStack(g.stack), "menu",
  "and the grid over it runs at MENU SPEED too, not the overworld's")

run.release()
Screens.invalidate()
T.finish("bills_pc_plus speed_category")
