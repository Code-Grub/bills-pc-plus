-- Standalone: luajit mods/bills_pc_plus/tests/modern_pc_ui_test.lua
--
-- Bill's PC Plus beside Modern PC UI.  Separate from bills_pc_plus_test.lua
-- because that file sits at LuaJIT's 200-local ceiling and cannot take
-- another top-level local.
--
-- The two mods want the same screen.  Modern PC UI replaces "only Someone's
-- /Bill's Pokemon-storage screen" (its main.lua:1) and loads at priority
-- 1100 against our 100, so it always runs second and its register-or-
-- override branch takes ours away.  Nothing says so: both mods report
-- loaded, and the player who installed both sees its PC with no hint that
-- this one is even involved.
--
-- Declaring it in `conflicts` is the wrong tool twice over.  The loader
-- fails the mod that DECLARES the incompatibility ("the declaring mod
-- loses", src/mods/Loader.lua:983), so we would be the one refused -- and
-- it has no Gold code at all, so that would surrender Gold, Silver and
-- Crystal for a clash that only exists on Red, Blue and Yellow.
--
-- So we stand down where we are beaten and nowhere else: on Gen 1 with it
-- installed we claim no screen and leave the box count alone, because our
-- EXTRA BOXES option reaches its screen too -- it lays its box picker out
-- as ceil(Boxes.COUNT / 4) rows in one fixed panel (its screen.lua:1570),
-- so raising the count to 99 crushes 25 rows into the space for three.
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local T = require("tests.modkit")
local FsIo = require("tests.fs_io")
local Screens = require("src.ui.Screens")
local Boxes = require("src.pokemon.Boxes")
local Save2 = require("src.core.gen2.Save")

local MOD = "mods/bills_pc_plus"
local RIVAL = "mods/bills_pc_plus/tests/fixtures/modern_pc_ui"

-- Loads through a filesystem that answers options.lua from memory, so a
-- test chooses what EXTRA BOXES is at load, and that rewrites "mods/<id>"
-- to wherever that mod really lives -- the same aliasing the SDK does for
-- itself (tests/modkit/sdk.lua), redone here because opts.fs replaces it.
local function loadWith(extraBoxes, withRival, generation)
  local inner = FsIo.new(".")
  local options = ("return { modOptions = { bills_pc_plus = { extra_boxes = %s } } }")
    :format(tostring(extraBoxes))
  local alias = { bills_pc_plus = MOD }
  local names = { "bills_pc_plus" }
  local paths = { MOD }
  if withRival then
    alias.modern_pc_ui = RIVAL
    names[#names + 1] = "modern_pc_ui"
    paths[#paths + 1] = RIVAL
  end

  local function map(path)
    if path == nil then return path end
    for name, real in pairs(alias) do
      local prefix = "mods/" .. name
      if path == prefix then return real end
      if path:sub(1, #prefix + 1) == prefix .. "/" then
        return real .. path:sub(#prefix + 1)
      end
    end
    return path
  end

  local fs = {}
  function fs.read(path)
    if path == "options.lua" then return options end
    return inner.read(map(path))
  end
  function fs.write(path, body)
    if path == "options.lua" then options = body end
    return true
  end
  function fs.load(path) return inner.load(map(path)) end
  function fs.getInfo(path)
    if path == "options.lua" then return { type = "file" } end
    if path == "mods" then return { type = "directory" } end
    return inner.getInfo(map(path))
  end
  function fs.getDirectoryItems(path)
    if path == "mods" then return names end
    return inner.getDirectoryItems(map(path))
  end

  local run = T.sdk.loadMods(paths, { fs = fs, generation = generation })
  Screens.invalidate()
  return run
end

-- Who the engine actually builds the PC from, by the route the game takes.
local function pcOwner(run)
  local g = { data = run.data, save = { party = {}, boxes = nil, currentBox = 1 },
    input = { wasPressed = function() return false end,
              isDown = function() return false end } }
  g.stack = { push = function() end, pop = function() end, states = {} }
  local screen = Screens.get(g, "BoxMenu").new(g)
  if screen.modernPcUi then return "modern_pc_ui" end
  if screen.session then return "bills_pc_plus" end
  return "builtin"
end

-- ------- alone on Gen 1: nothing changes
do
  local run = loadWith(true, false)
  T.eq(#run.errors, 0, "loads clean alone (" .. tostring(run.errors[1]) .. ")")
  T.eq(pcOwner(run), "bills_pc_plus", "with no rival installed the PC is ours")
  T.eq(Boxes.COUNT, 99, "and EXTRA BOXES still gives 99 boxes")
  run.release()
end

-- ------- beside it on Gen 1: we stand down, and both mods still load
do
  local run = loadWith(true, true)
  T.eq(#run.errors, 0,
    "both mods load, neither is refused (" .. tostring(run.errors[1]) .. ")")
  T.eq(pcOwner(run), "modern_pc_ui", "the PC is theirs")

  local ops = run.loader.content.screens.ops["BoxMenu"] or {}
  T.eq(#ops, 1, "and only one mod ever claimed the screen")
  T.eq(ops[1] and ops[1].owner, "modern_pc_ui",
    "theirs, registered rather than overriding ours away")

  -- the block above loaded us alone with the option on, so the engine
  -- module comes in here already carrying our 99 -- exactly what the
  -- manager leaves behind when it enables their mod and reloads
  T.eq(Boxes.COUNT, 12,
    "EXTRA BOXES puts the count back, so their box picker keeps its rows")
  run.release()
end

-- ------- Gold has no rival: it ships no Gen 2 code, so nothing is given up
do
  local run = loadWith(true, true, 2)
  T.eq(#run.errors, 0,
    "both load on Gold too (" .. tostring(run.errors[1]) .. ")")
  local ops = run.loader.content.screens.ops["Gen2BoxMenu"] or {}
  T.eq(#ops, 1, "Gold's PC is still claimed")
  T.eq(ops[1] and ops[1].owner, "bills_pc_plus", "and it is ours")
  -- Gold keeps its count on its own modules, not on the Gen 1 one this
  -- file holds: a Gen 2 boot resolves src.pokemon.Boxes to the
  -- compatibility adapter (src/mods/Gen2Compat.lua), a different table.
  T.eq(Save2.NUM_BOXES, 99, "EXTRA BOXES still works there")
  run.release()
end

Boxes.COUNT = 12
T.finish("bills_pc_plus modern_pc_ui")
