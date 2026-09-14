-- Standalone: luajit mods/bills_pc_plus/tests/extra_boxes_gen2_test.lua
--
-- EXTRA BOXES on Gold/Silver/Crystal: 99 boxes of 20 when on, the engine's
-- own 14 when off.  Gold's box count lives in three places -- Save, Boxes,
-- and the compatibility adapter's copied COUNT -- and all three must move.
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local T = require("tests.modkit")
local FsIo = require("tests.fs_io")
local Screens = require("src.ui.Screens")
local Save2 = require("src.core.gen2.Save")
local Boxes2 = require("src.core.gen2.Boxes")

local function loadWith(extraBoxes)
  local inner = FsIo.new(".")
  local options = ("return { modOptions = { bills_pc_plus = { extra_boxes = %s } } }")
    :format(tostring(extraBoxes))
  local fs = {}
  function fs.read(path)
    if path == "options.lua" then return options end
    return inner.read(path)
  end
  function fs.write(path, body)
    if path == "options.lua" then options = body end
    return true
  end
  function fs.getInfo(path)
    if path == "options.lua" then return { type = "file" } end
    if path == "mods" then return { type = "directory" } end
    return inner.getInfo(path)
  end
  function fs.load(path) return inner.load(path) end
  function fs.getDirectoryItems(path)
    if path == "mods" then return { "bills_pc_plus" } end
    return inner.getDirectoryItems(path)
  end
  local run = T.sdk.loadMods({ "mods/bills_pc_plus" }, { fs = fs, generation = 2 })
  Screens.invalidate()
  return run
end

local function newMon(level)
  return { species = "FIXMON_A", level = level or 12, hp = 20, dvs = {},
    statExp = {}, moves = {},
    stats = { hp = 20, attack = 12, defense = 12, speed = 12,
              specialAttack = 12, specialDefense = 12 } }
end

-- The game must share the loader's data table: registrations merge into
-- run.data, and Screens.get resolves through game.data (and caches the
-- answer), so a separate fixtures table resolves the builtin screen instead.
local function newGame(run, save)
  local g = { data = run.data, save = save }
  g.pushed = {}
  g.stack = { push = function(_, st) g.pushed[#g.pushed + 1] = st end,
              pop = function() end }
  g.input = { queue = {}, down = {},
    wasPressed = function(self, b) return self.queue[b] or false end,
    isDown = function(self, b) return self.down[b] or false end }
  return g
end

-- Gold's PC menu asks WITHDRAW before building the screen and pushes it with
-- the answer, so the factory returns the grid itself.
local function openGrid(g)
  return Screens.get(g, "Gen2BoxMenu").new(g, { mode = "withdraw",
    onClose = function() end })
end

local function press(state, btn)
  state.game.input.queue = { [btn] = true }
  state.game.input.down = { [btn] = true }
  state:update(1 / 60)
  state.game.input.queue = {}
  state.game.input.down = {}
end

-- ------- off at load: Gold's own 14, in all three places
do
  local run = loadWith(false)
  T.eq(#run.errors, 0, "loads clean on gen 2 with EXTRA BOXES off (" .. tostring(run.errors[1]) .. ")")
  T.eq(Save2.NUM_BOXES, 14, "off keeps Save.NUM_BOXES at 14")
  T.eq(Boxes2.NUM_BOXES, 14, "and Boxes.NUM_BOXES at 14")
  T.eq(Boxes2.MONS_PER_BOX, 20, "with 20 slots a box")
  run.release()
end

-- ------- on at load: 99 in all three, and the grid pages through them
do
  local run = loadWith(true)
  T.eq(#run.errors, 0, "loads clean on gen 2 with EXTRA BOXES on (" .. tostring(run.errors[1]) .. ")")
  T.eq(Save2.NUM_BOXES, 99, "on sets Save.NUM_BOXES to 99")
  T.eq(Boxes2.NUM_BOXES, 99, "and Boxes.NUM_BOXES to 99")
  T.eq(Boxes2.MONS_PER_BOX, 20, "without touching slots a box")

  -- the adapter's copied COUNT is what BoxSession pages by
  local g = newGame(run, { party = {}, boxes = {}, currentBox = 1 })
  local grid = openGrid(g)
  grid.cursor = 1
  press(grid, "left")
  T.eq(g.save.currentBox, 99, "paging left from box 1 wraps to box 99 on gen 2")
  run.release()
end

do
  local run = loadWith(false)
  T.eq(Save2.NUM_BOXES, 14, "a later load with it off restores 14")
  run.release()
end

Save2.NUM_BOXES, Boxes2.NUM_BOXES = 14, 14
T.finish("bills_pc_plus extra_boxes_gen2")
