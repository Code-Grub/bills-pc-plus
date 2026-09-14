-- Standalone: luajit mods/bills_pc_plus/tests/panel_sprite_test.lua
--
-- The sprite panel shows the same front art the summary screen does.
-- Separate from bills_pc_plus_test.lua because that file sits at LuaJIT's
-- 200-local ceiling and cannot take another top-level local.
--
-- The break this pins reached a player through HGSS Visual Overhaul.  HGSS
-- answers the pokemon.sprite hook only for battles; for the summary screen it
-- wraps SummaryMenu.new and pins one frame of its art onto the new screen
-- (hgss_sprites/main.lua:1954-1969).  The panel asked Sprites.path itself, so
-- it never saw that art and kept the ROM sprite.  Most of that art is also
-- bigger than the 56px panel, so it has to be fitted.
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local T = require("tests.modkit")
local Data = require("tests.modkit.fixtures").fresh()

local run = T.sdk.loadMod("mods/bills_pc_plus", { data = Data })
T.eq(#run.errors, 0, "loads clean (" .. tostring(run.errors[1]) .. ")")

local Screens = require("src.ui.Screens")
local SummaryMenu = require("src.ui.SummaryMenu")
local Sound = require("src.core.Sound")
local Transition = require("src.render.Transition")
local PaletteFX = require("src.render.PaletteFX")
local Boxes = require("src.pokemon.Boxes")
local L = dofile("mods/bills_pc_plus/Layout.lua")
Screens.invalidate()

-- ------- the fit only ever shrinks
T.eq(L.fitScale(56, 56, 56), 1, "56px art fits the 56px panel as it is")
T.eq(L.fitScale(80, 80, 56), 0.7, "80px art scales to 56px")
T.eq(L.fitScale(64, 40, 56), 0.875, "wide art scales by its width")
T.eq(L.fitScale(40, 20, 56), 1, "small art is never enlarged")

local function fmt(r)
  return r and ("%g,%g %gx%g"):format(r[1], r[2], r[3], r[4]) or "none"
end

local function newMon(level)
  return { species = "FIXMON_A", level = level or 12, hp = 20, dvs = {},
    statExp = {}, moves = {},
    stats = { hp = 20, attack = 12, defense = 12, speed = 12, special = 12 } }
end

-- Every field of a mon, stats included, as one comparable string.
local function snapshot(mon)
  local keys = {}
  for k, v in pairs(mon) do
    if type(v) == "table" then
      local inner = {}
      for ik, iv in pairs(v) do inner[#inner + 1] = tostring(ik) .. "=" .. tostring(iv) end
      table.sort(inner)
      keys[#keys + 1] = tostring(k) .. "={" .. table.concat(inner, ",") .. "}"
    else
      keys[#keys + 1] = tostring(k) .. "=" .. tostring(v)
    end
  end
  table.sort(keys)
  return table.concat(keys, ";")
end

-- A fixture front picture: only its size matters to the panel.
local function art(w, h)
  return { art = true, getDimensions = function() return w, h end }
end

local function openGrid(mons)
  local g = { data = Data, save = { party = {}, boxes = nil, currentBox = 1 },
    input = { wasPressed = function() return false end,
              isDown = function() return false end } }
  Boxes.ensure(g.save)
  g.save.boxes[1] = mons
  local captured = {}
  g.stack = { push = function(_, st) captured[#captured + 1] = st end,
              pop = function() end }
  local menu = Screens.get(g, "BoxMenu").new(g)
  for _, item in ipairs(menu.items) do
    if item.label == "WITHDRAW POKéMON" then item.onSelect() end
  end
  return captured[#captured]
end

-- The summary screen as HGSS leaves it: the stock constructor runs, then the
-- sprite is replaced with a full-colour frame.
local realNew, realCry = SummaryMenu.new, Sound.playCry
local realFlash, realMark = Transition.flashFrames, PaletteFX.markTrueColor
local builds, seen, nextArt, failBuild = 0, nil, nil, false
local cries, marks = 0, {}
SummaryMenu.new = function(game, mon, ...)
  builds = builds + 1
  seen = mon
  if failBuild then error("summary screen failed to build") end
  local summary = realNew(game, mon, ...)
  if nextArt then
    summary.sprite = nextArt
    summary.spriteTrueColor = true
  end
  return summary
end
Sound.playCry = function() cries = cries + 1 end
-- With no white flash the summary screen cries the moment it is built
-- (src/ui/SummaryMenu.lua:57-60), which is the case a borrowed build must
-- keep quiet.
Transition.flashFrames = function() return 0 end
PaletteFX.markTrueColor = function(x, y, w, h)
  marks[#marks + 1] = fmt({ x, y, w, h })
end

-- Draws the screen and returns every blit of a fixture picture as the rect it
-- covers, mirrored draws included.
local function drawn(grid)
  local realG = love.graphics
  local rects = {}
  love.graphics = setmetatable({
    draw = function(img, x, y, r, sx, sy)
      if type(img) ~= "table" or not img.art then return end
      local w, h = img:getDimensions()
      sx = sx or 1
      sy = sy or sx
      local ax, bx = x, x + w * sx
      local ay, by = y, y + h * sy
      rects[#rects + 1] = { math.min(ax, bx), math.min(ay, by),
        math.abs(bx - ax), math.abs(by - ay) }
    end,
  }, { __index = realG })
  marks = {}
  local ok, err = pcall(grid.draw, grid)
  love.graphics = realG
  if not ok then error(err, 0) end
  return rects
end

-- ------- oversized summary art is shown, scaled into the panel
do
  builds, cries, nextArt = 0, 0, art(80, 80)
  local mon = newMon(7)
  local before = snapshot(mon)
  local grid = openGrid({ mon })
  local rects = drawn(grid)
  T.eq(builds, 1, "the panel asks the summary screen for its picture")
  T.check(seen ~= nil and seen ~= mon,
    "building it from a copy of the mon, not the stored mon")
  T.eq(snapshot(mon), before, "which leaves the stored mon exactly as it was")
  T.eq(cries, 0, "and plays no cry")
  T.eq(#rects, 1, "the summary screen's picture is drawn once")
  T.eq(fmt(rects[1]), "96,24 56x56",
    "an 80px picture is scaled to fill the 56px panel, standing on its floor")
  T.eq(marks[#marks], "96,24 56x56",
    "and its full colour is kept over exactly the rect it covers")

  drawn(grid)
  drawn(grid)
  T.eq(builds, 1, "the picture is built once per mon, not once per frame")
end

do
  builds, nextArt = 0, art(64, 40)
  local rects = drawn(openGrid({ newMon(9) }))
  T.eq(fmt(rects[1]), "96,45 56x35",
    "wide art scales by its width and keeps its proportions")
end

do
  builds, nextArt = 0, art(48, 56)
  local rects = drawn(openGrid({ newMon(9) }))
  T.eq(fmt(rects[1]), "100,24 48x56", "art that fits is drawn at its own size")
end

-- ------- each mon gets its own picture
do
  builds, nextArt = 0, art(56, 56)
  local grid = openGrid({ newMon(5), newMon(6) })
  drawn(grid)
  grid.cursor = 2
  drawn(grid)
  T.eq(builds, 2, "moving to another mon builds that mon's picture")
end

-- ------- a summary screen that fails to build does not take the panel down
do
  builds, nextArt, failBuild = 0, nil, true
  local grid = openGrid({ newMon(8) })
  local ok, err = pcall(drawn, grid)
  failBuild = false
  T.check(ok, "the screen still draws when the summary screen raises: " .. tostring(err))
  T.check(grid.sprite ~= nil, "and the panel falls back to the plain sprite")
end

-- ------- Gold keeps its own sprite path
-- HGSS leaves Gen 2 summary pictures native, and Gold's summary screen is a
-- different constructor altogether; the Gen 2 seam never builds one.
do
  builds = 0
  local Engine = dofile("mods/bills_pc_plus/Engine.lua")
  T.eq(Engine.new(true):summarySprite({ data = Data }, newMon(5)), nil,
    "the Gen 2 seam has no borrowed summary picture")
  T.eq(builds, 0, "and builds no summary screen asking")
end

SummaryMenu.new, Sound.playCry = realNew, realCry
Transition.flashFrames, PaletteFX.markTrueColor = realFlash, realMark

T.finish("bills_pc_plus panel_sprite")
