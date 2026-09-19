-- Standalone: luajit mods/bills_pc_plus/tests/presenter_surface_test.lua
--
-- The grid, offered to every UI mod that presents other people's screens.
-- Separate from bills_pc_plus_test.lua because that file sits at LuaJIT's
-- 200-local ceiling and cannot take another top-level local.
--
-- Both Rex's UI Overhaul and Gen 1 Modern UI hide a stock Menu they
-- believe they can present, and both decide that against the whole visible
-- stack.  The grid is a screen neither has heard of, so the cursor menu
-- opened over it -- MOVE / WITHDRAW / STATS / RELEASE, the refusal boxes,
-- the release prompt -- was hidden.  Rex then drew nothing at all; Gen 1
-- Modern UI draws its own replacement over our pixel art.  Neither is what
-- the player asked this mod for.
--
-- Both publish the same escape hatch: registerAdapter(spec) taking
-- { owner, contract } with an API-v2 custom surface, and both stop hiding
-- anything while a surface is on the stack.  Their validators agree on the
-- shape (match/model/render, a virtual canvas, an explicit native.policy),
-- and Gen 1 Modern UI's SURFACE_API_VERSION is 2 like Rex's -- so one
-- contract table satisfies both, and this file pins that.
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local T = require("tests.modkit")
local Screens = require("src.ui.Screens")

local MOD = "mods/bills_pc_plus"
local REX = "mods/bills_pc_plus/tests/fixtures/rexs_ui_overhaul"
local MODERN = "mods/bills_pc_plus/tests/fixtures/gen1_modern_ui"

local function newMon()
  return { species = "FIXMON_A", level = 12, hp = 20, dvs = {}, statExp = {},
    moves = {},
    stats = { hp = 20, attack = 12, defense = 12, speed = 12, special = 12 } }
end

-- Opens the PC the way the game does and returns the grid WITHDRAW pushes,
-- plus the WITHDRAW/DEPOSIT menu beneath it.
local function openPc(run)
  Screens.invalidate()
  local g = { data = run.data,
    save = { party = { newMon() }, boxes = nil, currentBox = 1 },
    input = { wasPressed = function() return false end,
              isDown = function() return false end } }
  local captured = {}
  g.stack = { push = function(_, st) captured[#captured + 1] = st end,
              pop = function() end, states = {} }
  local menu = Screens.get(g, "BoxMenu").new(g)
  for _, item in ipairs(menu.items) do
    if item.label == "WITHDRAW POKéMON" then item.onSelect() end
  end
  return captured[#captured], menu
end

local function hasFunction(value, seen)
  if type(value) == "function" then return true end
  if type(value) ~= "table" then return false end
  seen = seen or {}
  if seen[value] then return false end
  seen[value] = true
  for k, v in pairs(value) do
    if hasFunction(k, seen) or hasFunction(v, seen) then return true end
  end
  return false
end

-- Everything both presenters require of the one contract we hand them.
local function checkSurfaceContract(who, spec, grid, menu)
  if type(spec) ~= "table" then
    T.check(false, who .. ": nothing was registered, so there is no contract")
    return
  end
  T.eq(spec.owner, "bills_pc_plus",
    who .. ": the owner is our manifest id, which is what it checks")
  local contract = spec.contract or {}
  T.eq(contract.apiVersion, 2, who .. ": an API-v2 contract")
  T.eq(contract.screens, nil,
    who .. ": no screen adapter -- that would let it draw the grid itself")
  local surfaces = {}
  for _, surface in pairs(contract.surfaces or {}) do
    surfaces[#surfaces + 1] = surface
  end
  T.eq(#surfaces, 1, who .. ": exactly one surface")
  local surface = surfaces[1] or {}
  T.eq(surface.native and surface.native.policy, "preserve",
    who .. ": preserve, so it recognises the grid without touching its pixels")
  T.eq(type(surface.match), "function", who .. ": the surface has a match")
  T.eq(surface.match and surface.match(grid), true,
    who .. ": that accepts our grid")
  T.eq(surface.match and surface.match(menu), false,
    who .. ": and not the menu beneath it")
  T.eq(surface.match and surface.match({}), false,
    who .. ": or an unrelated state")
  local layout = surface.layout or {}
  T.eq(layout.virtualWidth, 160, who .. ": a Game Boy canvas, width")
  T.eq(layout.virtualHeight, 144, who .. ": and height")
  T.check(not hasFunction(layout),
    who .. ": with a data-only layout, which its validator requires")
  local model = surface.model and surface.model()
  T.eq(type(model), "table", who .. ": the model is a table")
  T.check(not hasFunction(model), who .. ": with no functions in it")
  T.eq(surface.render and surface.render(model, {}), true,
    who .. ": render answers handled without drawing anything")
end

-- ------- Gen 1 Modern UI alone
do
  local run = T.sdk.loadMods({ MOD, MODERN })
  T.eq(#run.errors, 0, "loads clean (" .. tostring(run.errors[1]) .. ")")
  local modern = run.loader.exports.gen1_modern_ui
  T.check(modern and modern.registerAdapter, "the double is loaded")
  local grid, menu = openPc(run)
  T.eq(#modern.registered, 1, "opening the PC registers with Gen 1 Modern UI")
  checkSurfaceContract("modern", modern.registered[1], grid, menu)
  run.release()
end

-- ------- both installed: each is told, and told the same thing
do
  local run = T.sdk.loadMods({ MOD, REX, MODERN })
  T.eq(#run.errors, 0, "all three load (" .. tostring(run.errors[1]) .. ")")
  local rex = run.loader.exports.rexs_ui_overhaul
  local modern = run.loader.exports.gen1_modern_ui
  local grid, menu = openPc(run)
  T.eq(#rex.registered, 1, "Rex is registered with")
  T.eq(#modern.registered, 1, "and so is Gen 1 Modern UI")
  checkSurfaceContract("rex", rex.registered[1], grid, menu)
  checkSurfaceContract("modern", modern.registered[1], grid, menu)
  T.eq(rex.registered[1] and rex.registered[1].contract,
    modern.registered[1] and modern.registered[1].contract,
    "both are handed the very same contract table")
  run.release()
end

-- ------- neither installed: nothing is registered and the PC still opens
do
  local run = T.sdk.loadMods({ MOD })
  T.eq(#run.errors, 0, "loads clean alone (" .. tostring(run.errors[1]) .. ")")
  local grid = openPc(run)
  T.check(grid ~= nil, "the PC opens with no presenter installed")
  run.release()
end

T.finish("bills_pc_plus presenter_surface")
