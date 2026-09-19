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

-- ------- the raised count reaches the save the game already wrote
-- Boxes.ensure only builds boxes when save.boxes is nil, so a save made
-- before EXTRA BOXES was turned on carries 12 of them and nothing else
-- fills the rest.  Every engine box helper -- and every other mod -- walks
-- 1..Boxes.COUNT off that array, so raising the count without raising the
-- save leaves 87 nils in their path: the catch that overflows box 12 dies
-- in Boxes.deposit, on the player's behalf, with the PC never opened.
do
  local run = loadWith(true)
  local g = newGame(run, { party = {}, boxes = {}, currentBox = 1 })
  for b = 1, 12 do
    g.save.boxes[b] = {}
    for _ = 1, Boxes.CAPACITY do
      table.insert(g.save.boxes[b], newMon(3))
    end
  end

  local ok, landed = pcall(Boxes.deposit, g.save, newMon(7))
  T.eq(ok, true, "catching with the original 12 boxes full does not error ("
    .. tostring(landed) .. ")")
  T.eq(landed, 13, "the catch lands in the first of the extra boxes")
  T.eq(#Boxes.ensure(g.save), 99, "and every box a mod walks is a real box")
  T.eq(#g.save.boxes[1], Boxes.CAPACITY, "the boxes that were there are untouched")
  run.release()
end

-- The manager can raise the count with a save already loaded, and the next
-- catch is the first thing to walk it.
do
  local run = loadWith(false)
  local g = newGame(run, { party = {}, boxes = nil, currentBox = 1 })
  Boxes.ensure(g.save)
  for b = 1, 12 do
    g.save.boxes[b] = {}
    for _ = 1, Boxes.CAPACITY do
      table.insert(g.save.boxes[b], newMon(3))
    end
  end

  run.loader.modOptions.bills_pc_plus.extra_boxes = true
  run.loader.events:emit("mod.options_changed",
    { mod = "bills_pc_plus", key = "extra_boxes", value = true })

  local ok, landed = pcall(Boxes.deposit, g.save, newMon(7))
  T.eq(ok, true, "a catch after flipping the option on mid-game does not error ("
    .. tostring(landed) .. ")")
  T.eq(landed, 13, "and lands in the first of the extra boxes")
  run.release()
end

-- The other edge of the same seam: filling follows the live count, so with
-- the option off it must not invent a thirteenth box for the engine to
-- offer, name or export.
do
  local run = loadWith(false)
  local g = newGame(run, { party = {}, boxes = nil, currentBox = 1 })
  T.eq(#Boxes.ensure(g.save), 12,
    "with EXTRA BOXES off a save keeps the engine's own 12 boxes")
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

-- ------- turning it off hides extra boxes and never deletes them
-- BoxSession unpacks and commits boxes 1..Boxes.COUNT only, so a visit that
-- rearranges box 1 must leave box 60 exactly as it was.
do
  local run = loadWith(false)
  local hidden = newMon(40)
  local a, b = newMon(5), newMon(6)
  local g = newGame(run, { party = {}, boxes = nil, currentBox = 1 })
  Boxes.ensure(g.save)
  g.save.boxes[1] = { a, b }
  g.save.boxes[60] = { hidden }

  local grid, menu = openGrid(g)
  grid.session:pickUp(1, 1)
  grid.session:drop(1, 3)
  for _, item in ipairs(menu.items) do
    if item.label == "SEE YA!" then item.onSelect() end
  end
  T.eq(#g.save.boxes[1], 2, "the visit's own rearranging still commits")
  T.eq(g.save.boxes[60] and g.save.boxes[60][1], hidden,
    "a Pokemon in box 60 survives a PC visit with EXTRA BOXES off")
  T.eq(#g.save.boxes[60], 1, "and nothing else lands in its box")
  run.release()
end

-- ------- the notice: once per visit, only when something is hidden
local TextBox = require("src.render.TextBox")
local realTextBoxNew = TextBox.new
local shown = {}
TextBox.new = function(game, text)
  shown[#shown + 1] = text
  return { notice = text }
end

do
  local run = loadWith(false)
  local g = newGame(run, { party = {}, boxes = nil, currentBox = 1 })
  Boxes.ensure(g.save)
  g.save.boxes[1] = { newMon(5) }
  g.save.boxes[60] = { newMon(40) }
  g.save.boxes[77] = { newMon(41), newMon(42) }

  shown = {}
  local grid, menu = openGrid(g)
  grid:update(1 / 60)
  T.eq(shown[1], "POKéMON in extra\nboxes: 3.\fTurn EXTRA BOXES\non to reach them.",
    "opening the grid with Pokemon past box 12 names how many are hidden")
  T.eq(g.pushed[#g.pushed] and g.pushed[#g.pushed].notice, shown[1],
    "and pushes that notice over the grid")

  grid:update(1 / 60)
  for _, item in ipairs(menu.items) do
    if item.label == "DEPOSIT POKéMON" then item.onSelect() end
  end
  g.pushed[#g.pushed]:update(1 / 60)
  T.eq(#shown, 1, "it shows once per PC visit, not per frame or per grid")
  run.release()
end

do
  local run = loadWith(true)
  local g = newGame(run, { party = {}, boxes = nil, currentBox = 1 })
  Boxes.ensure(g.save)
  g.save.boxes[60] = { newMon(40) }
  shown = {}
  local grid = openGrid(g)
  grid:update(1 / 60)
  T.eq(#shown, 0, "with EXTRA BOXES on nothing is hidden, so there is no notice")
  run.release()
end

do
  local run = loadWith(false)
  local g = newGame(run, { party = {}, boxes = nil, currentBox = 1 })
  Boxes.ensure(g.save)
  g.save.boxes[1] = { newMon(5) }
  shown = {}
  local grid = openGrid(g)
  grid:update(1 / 60)
  T.eq(#shown, 0, "with no Pokemon past box 12 there is no notice")
  run.release()
end

TextBox.new = realTextBoxNew

Boxes.COUNT = 12
T.finish("bills_pc_plus extra_boxes")
