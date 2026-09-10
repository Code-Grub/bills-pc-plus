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

-- Gen 1 delegates to the engine's own drawIcon, unchanged, so Red/Blue/Yellow
-- keep today's output exactly -- including the OBP0 bake for built-in icon
-- classes, which only that path knows how to do.
do
  local PartyMenu = require("src.ui.PartyMenu")
  local realDraw = PartyMenu.drawIcon
  local seen
  PartyMenu.drawIcon = function(g, mon, x, y, selected, counter, forceAlt)
    seen = { g = g, mon = mon, x = x, y = y,
             selected = selected, counter = counter, forceAlt = forceAlt }
  end

  local fakeGame = { data = Data }
  local fakeMon = { species = "PIKACHU" }
  Engine.new(false):drawIcon(fakeGame, fakeMon, 24, 40, true)

  PartyMenu.drawIcon = realDraw

  T.check(seen, "the Gen 1 path still goes through PartyMenu.drawIcon")
  T.eq(seen and seen.x, 24, "at the x it was given")
  T.eq(seen and seen.y, 40, "and the y")
  T.eq(seen and seen.selected, false,
    "selected stays false: a stored mon has no meaningful HP-bar animation")
  T.eq(seen and seen.counter, 0, "counter stays 0 for the same reason")
  T.eq(seen and seen.forceAlt, true, "animation rides forceAlt instead")
end

-- Gen 2 resolves its own icon from data.gen2Icons -- per-species sheets,
-- not Gen 1's nine shared classes -- and Gold namespaces that table apart
-- from data.icons precisely so the two cannot collide (src/core/Game2.lua
-- :1036-1037, "Gen 2-only tables the menus read... nothing collides with
-- the Gen 1 keys of the same idea").  A fixture holding one real
-- species->sheet mapping, placed under BOTH keys, pins that the seam reads
-- only the one Gold actually populates: reading data.icons instead would
-- pass just as easily as reading gen2Icons if this test only checked for
-- a truthy image, which is exactly how the wrong key reached review once
-- already.
do
  local sheet = {
    species = { CYNDAQUIL = "ICON_FOX" },
    icons = { ICON_FOX = { image = "x/fox.png" } },
  }
  local e = Engine.new(true)

  local resolved = e:iconImageFor({ data = { gen2Icons = sheet } },
    { species = "CYNDAQUIL" })
  T.check(resolved, "a known species under gen2Icons resolves to an image")
  T.eq(resolved and resolved.path, "x/fox.png", "specifically its own sheet")

  local wrongKey = e:iconImageFor({ data = { icons = sheet } },
    { species = "CYNDAQUIL" })
  T.eq(wrongKey, nil,
    "the same table under the Gen 1 key (icons, not gen2Icons) resolves to " ..
    "nothing -- a regression back to that key must fail loudly here")

  local unknown = e:iconImageFor({ data = { gen2Icons = sheet } },
    { species = "NOSUCHMON" })
  T.eq(unknown, nil, "an unknown species resolves to no image, and does not raise")
end

-- ReadMonMenuIcon (engine/gfx/mon_icons.asm): an EGG slot draws ICON_EGG --
-- the `cp EGG / jr z, .egg` arm -- before any species lookup runs, so a
-- stored egg must draw the egg sheet, never the icon of whatever it will
-- hatch into.  Mirrors src/ui/gen2/PartyMenu.lua:752-757.
do
  local sheet = {
    species = { CYNDAQUIL = "ICON_FOX" },
    icons = { ICON_FOX = { image = "x/fox.png" },
              ICON_EGG = { image = "x/egg.png" } },
  }
  local e = Engine.new(true)
  local game = { data = { gen2Icons = sheet } }

  local egg = e:iconImageFor(game, { species = "CYNDAQUIL", isEgg = true })
  T.check(egg, "an egg resolves to an image")
  T.eq(egg and egg.path, "x/egg.png",
    "specifically the egg sheet, not CYNDAQUIL's own icon")
end

T.finish("bills_pc_plus gen2")
