-- Standalone: luajit mods/bills_pc_plus/tests/box_visibility_test.lua
--
-- What the rest of the game sees in save.boxes while a PC visit is open.
-- Separate from bills_pc_plus_test.lua because that file sits at LuaJIT's
-- 200-local ceiling and cannot take another top-level local.
--
-- The session keeps a sparse mirror and reconciles it into save.boxes on
-- the way out, so for as long as the GRID is up save.boxes is deliberately
-- stale -- a withdrawn mon is in the party and still in its box, and a mon
-- in hand is in neither.  That is what the save.write veto exists to cover
-- and it must stay true.
--
-- What must not stay true is the same staleness at the WITHDRAW/DEPOSIT
-- menu.  The menu outlives each grid push (its rows carry keepOpen), other
-- mods add their own rows to it -- FOLLOWERS_EX injects BOX LEADER into
-- whatever the PC pushes, and that row reads Boxes.active(game.save) --
-- and nothing there is mid-move: B cancels a carry before it can leave the
-- grid, so the hand is always empty by the time the menu is back on top.
-- A visit that withdrew a mon and backed out showed it in the party AND
-- still in box 1, and a row acting on that list acted on a duplicate.
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local T = require("tests.modkit")
local Screens = require("src.ui.Screens")
local Boxes = require("src.pokemon.Boxes")

local MOD = "mods/bills_pc_plus"

local function newMon(name)
  return { species = "FIXMON_A", nickname = name, level = 12, hp = 20,
    dvs = {}, statExp = {}, moves = {},
    stats = { hp = 20, attack = 12, defense = 12, speed = 12, special = 12 } }
end

-- A real LIFO, because this file is about which screen is on top: the menu
-- only reconciles once it is, and the engine only updates the top state
-- (src/core/StateStack.lua:60).
local function newGame(run, save)
  local g = { data = run.data, save = save }
  local states = {}
  g.stack = {
    states = states,
    push = function(_, st) states[#states + 1] = st end,
    pop = function() return table.remove(states) end,
    top = function() return states[#states] end,
  }
  g.input = { queue = {}, down = {},
    wasPressed = function(self, b) return self.queue[b] or false end,
    isDown = function(self, b) return self.down[b] or false end }
  return g
end

local function press(state, btn)
  state.game.input.queue = { [btn] = true }
  state.game.input.down = { [btn] = true }
  state:update(1 / 60)
  state.game.input.queue = {}
  state.game.input.down = {}
end

-- Opens the PC the way a player does: the menu, then WITHDRAW.
local function openPc(run, save)
  Screens.invalidate()
  local g = newGame(run, save)
  local menu = Screens.get(g, "BoxMenu").new(g)
  g.stack:push(menu)
  for _, item in ipairs(menu.items) do
    if item.label == "WITHDRAW POKéMON" then item.onSelect() end
  end
  return g, menu, g.stack:top()
end

-- How many copies of a nicknamed mon the rest of the game can see, counting
-- the party and every box: the duplicate is the whole bug.
local function copiesOf(save, name)
  local n = 0
  for _, mon in ipairs(save.party or {}) do
    if mon.nickname == name then n = n + 1 end
  end
  for _, box in ipairs(Boxes.ensure(save)) do
    for _, mon in ipairs(box) do
      if mon.nickname == name then n = n + 1 end
    end
  end
  return n
end

local run = T.sdk.loadMods({ MOD })
T.eq(#run.errors, 0, "loads clean (" .. tostring(run.errors[1]) .. ")")

-- ------- while the grid is up, the boxes stay stale on purpose
do
  local save = { party = { newMon("PARTY") }, boxes = nil, currentBox = 1 }
  Boxes.ensure(save)
  save.boxes[1] = { newMon("ALPHA"), newMon("BETA") }

  local g, _, grid = openPc(run, save)
  grid.session:withdraw(1, 1)

  T.eq(g.stack:top(), grid, "the grid is the screen on top")
  T.eq(copiesOf(save, "ALPHA"), 2,
    "mid-grid a withdrawn mon is in the party and still in its box")
  T.eq(#Boxes.active(save), 2, "because the box has not been reconciled yet")
end

-- ------- backing out to the menu reconciles, so another mod's row is right
do
  local save = { party = { newMon("PARTY") }, boxes = nil, currentBox = 1 }
  Boxes.ensure(save)
  save.boxes[1] = { newMon("ALPHA"), newMon("BETA") }

  local g, menu, grid = openPc(run, save)
  grid.session:withdraw(1, 1)
  press(grid, "b")
  T.eq(g.stack:top(), menu, "B with nothing in hand lands back on the menu")
  menu:update(1 / 60)

  T.eq(copiesOf(save, "ALPHA"), 1,
    "the withdrawn mon exists exactly once once the menu is back")
  local box = Boxes.active(save)
  T.eq(#box, 1, "its box holds only what is left")
  T.eq(box[1] and box[1].nickname, "BETA", "and that is the right mon")
  T.eq(save.party[2] and save.party[2].nickname, "ALPHA",
    "while the party keeps the one that was taken")
end

-- ------- deposit is the mirror case: mid-grid the mon is in NEITHER
-- list, so another mod's row sees it nowhere rather than twice.
do
  local save = { party = { newMon("PARTY"), newMon("GAMMA") },
    boxes = nil, currentBox = 1 }
  Boxes.ensure(save)

  local g, menu, grid = openPc(run, save)
  grid.session:deposit(2, 1)
  T.eq(copiesOf(save, "GAMMA"), 0,
    "mid-grid a deposited mon is out of the party and not yet in a box")

  press(grid, "b")
  menu:update(1 / 60)
  T.eq(copiesOf(save, "GAMMA"), 1,
    "and exists exactly once once the menu is back")
  T.eq(Boxes.active(save)[1] and Boxes.active(save)[1].nickname, "GAMMA",
    "in the box it was sent to")
  T.eq(#save.party, 1, "and out of the party")
end

-- ------- rearranging inside a box reaches the save the same way
do
  local save = { party = {}, boxes = nil, currentBox = 1 }
  Boxes.ensure(save)
  save.boxes[1] = { newMon("ALPHA"), newMon("BETA") }

  local g, menu, grid = openPc(run, save)
  grid.session:pickUp(1, 1)
  grid.session:drop(1, 5)
  press(grid, "b")
  menu:update(1 / 60)

  local box = Boxes.active(save)
  T.eq(#box, 2, "both mons are still there")
  T.eq(box[1] and box[1].nickname, "BETA", "in the order the move left them")
  T.eq(box[2] and box[2].nickname, "ALPHA", "with the moved one behind it")
end

-- ------- a visit that changed nothing writes nothing
do
  local save = { party = {}, boxes = nil, currentBox = 1 }
  Boxes.ensure(save)
  local alpha = newMon("ALPHA")
  save.boxes[1] = { alpha }

  local g, menu, grid = openPc(run, save)
  press(grid, "b")
  menu:update(1 / 60)
  T.eq(Boxes.active(save)[1], alpha,
    "a browse-only visit leaves the very same table in place")
end

run.release()
T.finish("bills_pc_plus box_visibility")
