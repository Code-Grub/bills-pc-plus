-- Standalone: luajit mods/bills_pc_plus/tests/gen2_test.lua
--
-- Gen 2 (Gold/Silver/Crystal) load and seam behaviour.  Separate from
-- bills_pc_plus_test.lua because that file sits at LuaJIT's 200-local
-- ceiling and cannot take another top-level local.
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local T = require("tests.modkit")
local Data = require("tests.modkit.fixtures").fresh()

-- A gate skip is deliberately NOT an error, so #run.errors == 0 passes for a
-- mod that never ran a line.  Assert the state, not just the error count.
local run = T.sdk.loadMod("mods/bills_pc_plus", { data = Data, generation = 2 })
T.eq(#run.errors, 0,
  "loads with no boot errors on gen 2 (" .. tostring(run.errors[1]) .. ")")
T.eq(run.mod and run.mod.state, "loaded",
  "the mod runs on gen 2: " .. tostring(run.mod and run.mod.skipReason))

-- The seam is constructed with an explicit generation rather than sniffing
-- one: the screen id the factory was registered under is the signal, so
-- nothing here allow-lists a version.
local Engine = dofile("mods/bills_pc_plus/Engine.lua")

local gen1 = Engine.new(false)
T.eq(gen1.gen2, false, "a Gen 1 seam knows it is Gen 1")
T.eq(gen1:summaryScreenId(), "SummaryMenu", "and opens the Gen 1 summary")

local gen2 = Engine.new(true)
T.eq(gen2.gen2, true, "a Gen 2 seam knows it is Gen 2")
T.eq(gen2:summaryScreenId(), "Gen2SummaryMenu", "and opens Gold's summary")

-- The seam only reaches the Screen as newGrid's fourth argument -- newGrid is
-- defined outside the factory, so it cannot capture the upvalue.  A nil there
-- stays invisible until a stored mon's STATS row fires, so open the grid the
-- way a player does, through each registered id, and check what landed.
local Screens = require("src.ui.Screens")
Screens.invalidate()

local function gridFor(id)
  local g = {
    data = Data,
    save = { party = {}, boxes = nil, currentBox = 1 },
    stack = { push = function() end },
    input = { wasPressed = function() return false end,
              isDown = function() return false end },
  }
  local menu = Screens.get(g, id).new(g)
  local captured
  g.stack = { push = function(_, state) captured = state end,
              pop = function() end }
  for _, item in ipairs(menu.items) do
    if item.label == "WITHDRAW POKéMON" then item.onSelect() end
  end
  return captured
end

local boxGrid = gridFor("BoxMenu")
T.check(boxGrid and boxGrid.engine, "the grid behind BoxMenu carries a seam")
T.eq(boxGrid.engine:summaryScreenId(), "SummaryMenu",
  "the Gen 1 id's seam, so STATS there opens Red's summary")

local gen2Grid = gridFor("Gen2BoxMenu")
T.check(gen2Grid and gen2Grid.engine,
  "the grid behind Gen2BoxMenu carries a seam")
T.eq(gen2Grid.engine:summaryScreenId(), "Gen2SummaryMenu",
  "Gold's, so STATS there opens Gold's summary")

T.finish("bills_pc_plus gen2")
