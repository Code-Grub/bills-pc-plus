-- Standalone: luajit mods/bills_pc_plus/tests/rex_ui_test.lua
--
-- Bill's PC Plus beside Rex's UI Overhaul.  Separate from
-- bills_pc_plus_test.lua because that file sits at LuaJIT's 200-local
-- ceiling and cannot take another top-level local.
--
-- The break this pins: Rex hides every stock Menu it believes it can
-- present, but only draws its replacement once it recognises EVERY visible
-- screen.  Our grid is a screen it does not know, so the MOVE/WITHDRAW menu
-- opened over it was hidden and never redrawn -- open, taking input, and
-- invisible.  Rex's public answer for a source mod's own screen is an API-v2
-- custom surface; with native.policy "preserve" the screen is recognised and
-- its pixels are left alone, and while a surface is on the stack Rex hides
-- nothing (its canSuppressState refuses), so our menus draw as they always
-- have.
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local T = require("tests.modkit")
local Screens = require("src.ui.Screens")

local MOD = "mods/bills_pc_plus"
local REX = "mods/bills_pc_plus/tests/fixtures/rexs_ui_overhaul"

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
  return captured[#captured], menu, g
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

-- ------- without Rex, nothing changes
do
  local run = T.sdk.loadMods({ MOD })
  T.eq(#run.errors, 0, "loads clean alone (" .. tostring(run.errors[1]) .. ")")
  local ok, grid = pcall(openPc, run)
  T.check(ok, "the PC opens with no Rex installed: " .. tostring(not ok and grid))
  T.check(ok and grid ~= nil, "and pushes its grid")
  run.release()
end

-- ------- with Rex, opening the PC registers a preserve surface for the grid
do
  local run = T.sdk.loadMods({ MOD, REX })
  T.eq(#run.errors, 0,
    "loads clean beside Rex (" .. tostring(run.errors[1]) .. ")")
  local rex = run.loader.exports.rexs_ui_overhaul
  T.check(rex and rex.registerAdapter, "the Rex test double is loaded")

  local grid, menu, game = openPc(run)
  local registered = rex and rex.registered or {}
  T.check(#registered >= 1, "opening the PC registers with Rex")

  local spec = registered[#registered] or {}
  T.eq(spec.owner, "bills_pc_plus",
    "under our own mod id, which Rex checks is an active mod")
  local contract = spec.contract or {}
  T.eq(contract.apiVersion, 2, "as an API-v2 contract, the version surfaces need")
  T.eq(contract.screens, nil,
    "with no screen adapter -- that would have Rex draw the grid itself")

  local surfaces = {}
  for id, surface in pairs(contract.surfaces or {}) do
    surfaces[#surfaces + 1] = { id = id, surface = surface }
  end
  T.eq(#surfaces, 1, "and exactly one surface")
  local surface = surfaces[1] and surfaces[1].surface or {}

  T.eq(surface.native and surface.native.policy, "preserve",
    "which preserves our pixels rather than replacing them")
  T.check(type(surface.match) == "function", "the surface has a match")
  T.eq(surface.match and surface.match(grid), true, "that accepts our grid")
  T.eq(surface.match and surface.match(menu), false,
    "and not the WITHDRAW/DEPOSIT menu, a stock Menu Rex styles itself")
  T.eq(surface.match and surface.match({}), false, "or an unrelated state")

  local model = surface.model and surface.model(game, grid)
  T.check(type(model) == "table", "the model is a table")
  T.check(not hasFunction(model), "with no functions in it, as Rex requires")
  T.eq(surface.render and surface.render(model, {}), true,
    "render reports success, which Rex requires before it commits a frame")

  local layout = surface.layout or {}
  local vw = tonumber(layout.virtualWidth or layout.width)
  local vh = tonumber(layout.virtualHeight or layout.height)
  T.check(vw and vh and vw >= 1 and vh >= 1 and vw <= 2048 and vh <= 2048,
    "the layout declares a virtual canvas inside Rex's 2048x2048 limit")
  T.check(not hasFunction(layout), "and is data-only")
  run.release()
end

T.finish("bills_pc_plus rex_ui")
