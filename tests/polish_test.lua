-- Standalone: luajit mods/bills_pc_plus/tests/polish_test.lua
--
-- The sprite panel and stats strip polish: the pic centred in the panel's free
-- space, the type pills centred under the table, and hairlines between the
-- stat columns.  The pure arithmetic is first, the drawing and the wiring
-- after.  Its own file because bills_pc_plus_test.lua is at LuaJIT's 200-local
-- ceiling.  The Gen 2 half is polish_gen2_test.lua (one generation per load).
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local T = require("tests.modkit")
local L = dofile("mods/bills_pc_plus/Layout.lua")

-- A missing function is a failed check rather than a crash, so a red run says
-- which behaviour is absent instead of dying on the first call.
local function F(name, ...)
  local fn = L[name]
  if type(fn) ~= "function" then return nil end
  return fn(...)
end

-- ------- A: the pic is centred in the space under the plate
-- The area runs from the plate's bottom edge to the floor the sprite stood on.
T.eq(L.SPRITE_AREA_TOP, L.PLATE_Y + 16, "the area starts where the plate ends")
T.eq(L.SPRITE_AREA_TOP, 24, "which is y=24")

-- no measurement: exactly where it stood before, on the floor
T.eq(F("spriteY", 40, nil, nil, 88), 88 - 40, "unmeasured art still stands on the floor")
T.eq(F("spriteY", 40, nil, nil, 80), 80 - 40, "on either floor")

-- a fully inked 40px pic in the 64px area (PC HEALS on): 12px above, 12 below
T.eq(F("spriteY", 40, 0, 40, 88), 36, "a 40px pic centres in the 64px area")
-- Diglett's pic is a 40px block with the ink in its lower 30 rows: it is the
-- ink that is centred, not the block, or the mon would sit 5px low
T.eq(F("spriteY", 40, 10, 30, 88), 31, "the ink is what centres, not the block")
-- a 7x7 has 4px to spare above and below with the HP line gone
T.eq(F("spriteY", 56, 0, 56, 88), 28, "a 56px pic floats 4px off the floor")
-- with the HP line kept the area is 56px and a 7x7 fills it exactly
T.eq(F("spriteY", 56, 0, 56, 80), 24, "a 56px pic fills the HP-line area exactly")
T.eq(F("spriteY", 40, 10, 30, 80), 27, "and a 30px ink centres in it")
-- art whose ink sits at the TOP of its block would be centred below the
-- floor; it never goes lower than standing on it
T.eq(F("spriteY", 56, 0, 20, 88), 32, "never lower than standing on the floor")

-- Whatever is centred stays inside the SGB zone that colours the pic, so no
-- sprite pixel is left wearing the screen's whole-screen palette.
for _, baseline in ipairs({ L.SPRITE_BASELINE, L.SPRITE_BASELINE_NO_HP }) do
  local _, zy1, _, zy2 = L.spriteZone(baseline)
  T.eq(zy1 * 8, L.SPRITE_AREA_TOP, "the zone starts at the area's top (floor " .. baseline .. ")")
  T.eq((zy2 + 1) * 8, baseline, "and ends on the floor (" .. baseline .. ")")
  for _, ph in ipairs({ 24, 32, 40, 48, 56 }) do
    for _, inkH in ipairs({ ph, ph - 8, 16 }) do
      for _, inkY in ipairs({ 0, ph - inkH }) do
        local py = F("spriteY", ph, inkY, inkH, baseline)
        if py then
          T.check(py + inkY >= zy1 * 8 and py + inkY + inkH <= (zy2 + 1) * 8,
            ("%dpx pic, ink %d+%d, floor %d: ink %d..%d is inside the zone"):format(
              ph, inkY, inkH, baseline, py + inkY, py + inkY + inkH))
        end
      end
    end
  end
end

-- ------- B1: the pills are centred under the table
T.eq(L.STRIP_CX, 80, "the strip's centre is box B's interior centre")
local one = L.badgeSpans({ L.pillWidth(32) })
T.eq(one[1].x, 80 - 20, "one pill is centred on x=80")
T.eq(one[1].w, L.pillWidth(32), "and keeps its width")
local two = L.badgeSpans({ L.pillWidth(64), L.pillWidth(48) })
T.eq(two[2].x, two[1].x + two[1].w + L.BADGE_GAP, "two pills still sit a gap apart")
T.eq((two[1].x + two[2].x + two[2].w) / 2, 80, "and the pair is centred on x=80")
local zap = L.badgeSpans({ L.pillWidth(8 * 8), L.pillWidth(6 * 8) })
T.eq(zap[1].x, 14, "the widest pair (ELECTRIC/FLYING) starts at x=14")
T.eq(zap[2].x + zap[2].w, 146, "and ends at x=146, inside box B's interior (152)")
T.check(zap[1].x >= L.STATS_X, "never left of the strip's own edge")
-- an odd total (a proportional font pack) still lands on whole pixels
local odd = L.badgeSpans({ 41, 29 })
T.eq(odd[1].x, math.floor(odd[1].x), "an odd total lands on a whole pixel")

-- ------- the column grid
-- A hairline in the centre of each gap between two fields.  The gap is the air
-- the table already had; the line is drawn in it and moves nothing.
local g1 = F("gridLines", L.STATS_COLS, L.STATS_COL_W, nil, true)
T.eq(g1 and #g1, 3, "Gen 1's four columns have three gaps")
for i, want in ipairs({ 51, 83, 115 }) do
  T.eq(g1 and g1[i].x, want, "Gen 1 line " .. i .. " is at x=" .. want)
  T.eq(g1 and g1[i].y, L.STATS_Y, "and starts on the header row")
  T.eq(g1 and g1[i].h, 3 * L.ROW - 1, "and runs through the DV row")
end
local g1b = F("gridLines", L.STATS_COLS, L.STATS_COL_W, nil, false)
T.eq(g1b and g1b[1].h, 2 * L.ROW - 1, "with no DV row the lines stop at the values")

-- Gen 2: the shared Special DV is centred on the seam between SA and SD, so a
-- line through that gap would cut it.  Only that line gives up its DV segment.
local g2 = F("gridLines", L.STATS_COLS_5, L.STATS_COL_W, { L.STATS_DV_SHARED_CX }, true)
T.eq(g2 and #g2, 4, "Gen 2's five columns have four gaps")
for i, want in ipairs({ 33, 61, 89, 117 }) do
  T.eq(g2 and g2[i].x, want, "Gen 2 line " .. i .. " is at x=" .. want)
end
T.eq(g2 and g2[1].h, 3 * L.ROW - 1, "lines 1-3 run through the DV row")
T.eq(g2 and g2[3].h, 3 * L.ROW - 1, "including the third")
T.eq(g2 and g2[4].h, 2 * L.ROW - 1, "the fourth stops above the shared DV it would cut")

-- every line sits in empty air: after one field and before the next
for _, spec in ipairs({
  { L.STATS_COLS, nil }, { L.STATS_COLS_5, { L.STATS_DV_SHARED_CX } } }) do
  local lines = F("gridLines", spec[1], L.STATS_COL_W, spec[2], true) or {}
  for i, ln in ipairs(lines) do
    T.check(ln.x >= spec[1][i] + L.STATS_COL_W - 1 and ln.x < spec[1][i + 1],
      "line " .. i .. " is inside the gap, not on a field")
  end
end

-- ------- the drawing (Gen 1)
local Data = require("tests.modkit.fixtures").fresh()
local Font = require("src.render.Font")
local gfx = love.graphics

local run = T.sdk.loadMod("mods/bills_pc_plus", { data = Data })
T.eq(#run.errors, 0, "loads clean (" .. tostring(run.errors[1]) .. ")")
local Screens = require("src.ui.Screens")
Screens.invalidate()

local function openGrid(g, rowLabel)
  local captured = {}
  local realStack = g.stack
  g.stack = { push = function(_, st) captured[#captured + 1] = st end,
              pop = function() end }
  local menu = Screens.get(g, "BoxMenu").new(g)
  for _, item in ipairs(menu.items) do
    if item.label == rowLabel and item.onSelect then item.onSelect() end
  end
  g.stack = realStack
  return captured[#captured]
end

local function gameWith(types, partyMon)
  Data.pokemon.FIXMON_A.types = types
  return {
    data = Data,
    save = { party = partyMon and { partyMon } or {}, boxes = {
      { { species = "FIXMON_A", level = 12, hp = 20,
          dvs = { attack = 15, defense = 10, speed = 10, special = 10 },
          statExp = {}, moves = {},
          stats = { hp = 20, attack = 12, defense = 12, speed = 12, special = 12 } } },
    }, currentBox = 1 },
    stack = { push = function() end, pop = function() end },
    input = { wasPressed = function() return false end,
              isDown = function() return false end },
  }
end

-- Every 1px-wide fill that starts on the header row: the strip's hairlines.
-- (The page squares are 3px wide, and their hollow sides sit on other rows.)
local function hairlines(grid)
  local out = {}
  local real = gfx.rectangle
  gfx.rectangle = function(mode, x, y, w, h)
    if mode == "fill" and w == 1 and y == L.STATS_Y and h > 1 then
      out[#out + 1] = { x = x, y = y, h = h }
    end
    return real(mode, x, y, w, h)
  end
  local ok, err = pcall(function() grid:draw() end)
  gfx.rectangle = real
  if not ok then error(err, 0) end
  table.sort(out, function(a, b) return a.x < b.x end)
  return out
end

run.loader.modOptions.bills_pc_plus = nil
local box = openGrid(gameWith({ "ELECTRIC" }), "WITHDRAW POKéMON")
box.counter = 0
local lines = hairlines(box)
T.eq(#lines, 3, "box view draws three hairlines")
for i, want in ipairs({ 51, 83, 115 }) do
  T.eq(lines[i] and lines[i].x, want, "line " .. i .. " is at x=" .. want)
  T.eq(lines[i] and lines[i].h, 3 * L.ROW - 1, "through the DV row")
end

run.loader.modOptions.bills_pc_plus = { dv_display = false }
lines = hairlines(box)
T.eq(lines[1] and lines[1].h, 2 * L.ROW - 1, "with the DVs hidden they stop at the values")
run.loader.modOptions.bills_pc_plus = nil

-- deposit mode: box C covers the DV row
local dep = openGrid(gameWith({ "ELECTRIC" }, {
  species = "FIXMON_A", level = 5, hp = 20, dvs = {}, statExp = {}, moves = {},
  stats = { hp = 20, attack = 12, defense = 12, speed = 12, special = 12 } }),
  "DEPOSIT POKéMON")
dep.counter = 0
lines = hairlines(dep)
T.eq(#lines, 3, "deposit mode draws the hairlines")
T.eq(lines[1] and lines[1].h, 2 * L.ROW - 1, "through the header and values only")

-- an empty cell has no table, so no lines
box.cursor = 2
lines = hairlines(box)
T.eq(#lines, 0, "an empty cell draws no hairlines")
box.cursor = 1

-- the moves page replaces the strip, so it shows no grid
box.stripPage = 2
lines = hairlines(box)
T.eq(#lines, 0, "the moves page is not gridded")
box.stripPage = 1

-- the pills follow the table's centre in the real strip
local d = {}
do
  local real = Font.draw
  Font.draw = function(text, x, y)
    d[#d + 1] = { text = tostring(text), x = x, y = y }
    return real(text, x, y)
  end
  local ok, err = pcall(function() box:draw() end)
  Font.draw = real
  if not ok then error(err, 0) end
end
local lab
for _, t in ipairs(d) do if t.text == "ELECTRIC" then lab = t end end
T.check(lab ~= nil, "the ELECTRIC pill is drawn")
if lab then
  local w = L.pillWidth(Font.width("ELECTRIC"))
  T.eq(lab.x, 80 - math.floor(w / 2) + math.floor((w - Font.width("ELECTRIC")) / 2),
    "its label sits in a pill centred on x=80")
end

-- ------- the pic is centred in the real panel
-- A fixture picture that reports its ink the way a canvas readback would.
local SummaryMenu = require("src.ui.SummaryMenu")
local Sound = require("src.core.Sound")
local Transition = require("src.render.Transition")
local realNew, realCry, realFlash = SummaryMenu.new, Sound.playCry, Transition.flashFrames
local nextArt
SummaryMenu.new = function(game, mon, ...)
  local summary = realNew(game, mon, ...)
  if nextArt then summary.sprite = nextArt; summary.spriteTrueColor = true end
  return summary
end
Sound.playCry = function() end
Transition.flashFrames = function() return 0 end

local function art(w, h, inkTop)
  return { art = true, getDimensions = function() return w, h end,
    alphaAt = function(_, y) return y >= (inkTop or 0) and 1 or 0 end }
end

-- the pic's top edge as drawn, through a canvas that can be read back
local function picTop(grid, opts)
  local realG = love.graphics
  local top, target, saved = nil, nil, {}
  local shim = setmetatable({
    -- push("all") / pop restore the canvas, as LOVE does; without this the
    -- readback's canvas would stay current and swallow the real blit
    push = function(...)
      saved[#saved + 1] = target or false
      return realG.push(...)
    end,
    pop = function(...)
      target = table.remove(saved) or nil
      return realG.pop(...)
    end,
    origin = function() end,
    draw = function(img, x, y, r, sx, sy)
      if type(img) ~= "table" or not img.art then return end
      if target then target.painted = img; return end
      top = math.min(y, y + select(2, img:getDimensions()) * (sy or sx or 1))
    end,
    clear = function() end,
    setCanvas = function(c) target = c end,
    getCanvas = function() return target end,
  }, { __index = realG })
  if not (opts and opts.noReadback) then
    shim.newCanvas = function(w, h)
      local canvas = { w = w, h = h }
      function canvas:newImageData()
        local painted = self.painted
        return {
          getDimensions = function() return w, h end,
          getPixel = function(_, px, py)
            return 1, 1, 1, painted and painted.alphaAt(px, py) or 0
          end,
        }
      end
      function canvas:release() end
      return canvas
    end
  else
    -- not nil: the shim's metatable would hand back the stub's own canvas
    shim.newCanvas = function() error("no canvas readback on this runtime") end
  end
  love.graphics = shim
  local ok, err = pcall(grid.draw, grid)
  love.graphics = realG
  if not ok then error(err, 0) end
  return top
end

local function gridWith(mon)
  local g = gameWith({ "NORMAL" })
  g.save.boxes[1] = { mon }
  local grid = openGrid(g, "WITHDRAW POKéMON")
  grid.counter = 0
  return grid
end

local function mon() return { species = "FIXMON_A", level = 12, hp = 20, dvs = {},
  statExp = {}, moves = {},
  stats = { hp = 20, attack = 12, defense = 12, speed = 12, special = 12 } } end

run.loader.modOptions.bills_pc_plus = nil              -- PC HEALS on: floor at 88
nextArt = art(40, 40, 10)                              -- Diglett: ink in rows 10..39
T.eq(picTop(gridWith(mon())), 31, "a measured pic is centred by its ink")

nextArt = art(56, 56, 0)
T.eq(picTop(gridWith(mon())), 28, "a 7x7 floats 4px off the floor")

nextArt = art(40, 40, 10)
T.eq(picTop(gridWith(mon()), { noReadback = true }), 88 - 40,
  "a runtime that cannot read pixels back keeps the old standing position")

run.loader.modOptions.bills_pc_plus = { pc_heals = false }   -- HP line kept: floor at 80
nextArt = art(40, 40, 10)
T.eq(picTop(gridWith(mon())), 27, "with the HP line kept the area is 56px and the pic centres in it")
nextArt = nil

SummaryMenu.new, Sound.playCry, Transition.flashFrames = realNew, realCry, realFlash
T.finish("bills_pc_plus polish")
