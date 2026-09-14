-- Standalone: luajit mods/bills_pc_plus/tests/extra_boxes_test.lua
--
-- EXTRA BOXES on Red/Blue/Yellow: 99 boxes of 20 when on, the engine's own
-- 12 when off.  Separate from bills_pc_plus_test.lua because that file sits
-- at LuaJIT's 200-local ceiling and cannot take another top-level local.
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local T = require("tests.modkit")
local FsIo = require("tests.fs_io")
local Screens = require("src.ui.Screens")
local Boxes = require("src.pokemon.Boxes")

-- Loads bills_pc_plus alone through a filesystem that answers options.lua
-- from memory, so a test chooses what the option is at load.  The SDK's own
-- aliasing filesystem would read C:/g2dev's real options.lua instead.
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
  local run = T.sdk.loadMods({ "mods/bills_pc_plus" }, { fs = fs })
  Screens.invalidate()
  return run
end

local function newMon(level)
  return { species = "FIXMON_A", level = level or 12, hp = 20, dvs = {},
    statExp = {}, moves = {},
    stats = { hp = 20, attack = 12, defense = 12, speed = 12, special = 12 } }
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

-- Opens the PC the way a player does and returns the grid WITHDRAW pushes,
-- plus the WITHDRAW/DEPOSIT menu under it.
local function openGrid(g)
  local menu = Screens.get(g, "BoxMenu").new(g)
  for _, item in ipairs(menu.items) do
    if item.label == "WITHDRAW POKéMON" then item.onSelect() end
  end
  return g.pushed[#g.pushed], menu
end

local function press(state, btn)
  state.game.input.queue = { [btn] = true }
  state.game.input.down = { [btn] = true }
  state:update(1 / 60)
  state.game.input.queue = {}
  state.game.input.down = {}
end

-- ------- off at load: the engine's own 12
do
  local run = loadWith(false)
  T.eq(#run.errors, 0, "loads clean with EXTRA BOXES off (" .. tostring(run.errors[1]) .. ")")
  T.eq(Boxes.COUNT, 12, "off keeps Red's 12 boxes")
  T.eq(Boxes.CAPACITY, 20, "and 20 slots a box")
  run.release()
end

-- ------- on at load: 99 boxes, still 20 slots, and the grid pages through them
do
  local run = loadWith(true)
  T.eq(#run.errors, 0, "loads clean with EXTRA BOXES on (" .. tostring(run.errors[1]) .. ")")
  T.eq(Boxes.COUNT, 99, "on gives 99 boxes")
  T.eq(Boxes.CAPACITY, 20, "without touching slots a box")

  local g = newGame(run, { party = {}, boxes = nil, currentBox = 1 })
  local grid = openGrid(g)
  grid.cursor = 1
  press(grid, "left")
  T.eq(g.save.currentBox, 99, "paging left from box 1 wraps to box 99")
  run.release()
end

-- ------- a later load with it off restores 12, not an already-raised 99
do
  local run = loadWith(false)
  T.eq(Boxes.COUNT, 12, "turning it off at the next load puts 12 back")
  run.release()
end

-- ------- flipping the option in the mod manager applies at once
-- ManagerState:setOption writes loader.modOptions and then emits
-- mod.options_changed with { mod, key, value } (src/mods/ManagerState.lua);
-- this does the same two things in that order.
do
  local run = loadWith(false)
  local stored = run.loader.modOptions.bills_pc_plus
  local function flip(value, payload)
    stored.extra_boxes = value
    run.loader.events:emit("mod.options_changed", payload)
  end

  flip(true, { mod = "bills_pc_plus", key = "extra_boxes", value = true })
  T.eq(Boxes.COUNT, 99, "turning EXTRA BOXES on mid-game gives 99 boxes at once")

  flip(false, { mod = "bills_pc_plus", key = "dv_display", value = false })
  T.eq(Boxes.COUNT, 99, "a change to another of this mod's options leaves the count alone")

  flip(false, { mod = "some_other_mod", key = "extra_boxes", value = false })
  T.eq(Boxes.COUNT, 99, "the same key on another mod leaves the count alone")

  flip(false, { mod = "bills_pc_plus", key = "extra_boxes", value = false })
  T.eq(Boxes.COUNT, 12, "turning it off mid-game puts 12 back at once")
  run.release()
end

Boxes.COUNT = 12
T.finish("bills_pc_plus extra_boxes")
