-- Standalone: luajit mods/bills_pc_plus/tests/type_badges_draw_test.lua
--
-- The TYPE BADGES option and the pills it draws.  The pure parts (colours,
-- label colour, geometry) are in type_badges_test.lua; this file is the
-- drawing and the wiring into the strip.  It is its own file because
-- bills_pc_plus_test.lua is at LuaJIT's 200-local ceiling.
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local T = require("tests.modkit")
local Data = require("tests.modkit.fixtures").fresh()
local Font = require("src.render.Font")
local PaletteFX = require("src.render.PaletteFX")
local gfx = love.graphics
local L = dofile("mods/bills_pc_plus/Layout.lua")
local B = dofile("mods/bills_pc_plus/TypeBadges.lua")

-- ------- the pill itself
-- Spies on the graphics calls a pill makes.  Everything restores afterwards.
local function spy(fn)
  local rects, texts, canvases, colors = {}, {}, {}, {}
  local real = {
    rectangle = gfx.rectangle, setColor = gfx.setColor, newCanvas = gfx.newCanvas,
    newShader = gfx.newShader, draw = Font.draw,
  }
  local color = { 1, 1, 1, 1 }
  gfx.setColor = function(r, g, b, a)
    if type(r) == "table" then r, g, b, a = r[1], r[2], r[3], r[4] end
    color = { r, g, b, a or 1 }
    colors[#colors + 1] = color
  end
  gfx.rectangle = function(mode, x, y, w, h)
    rects[#rects + 1] = { mode = mode, x = x, y = y, w = w, h = h,
      color = { color[1], color[2], color[3] } }
  end
  Font.draw = function(text, x, y)
    texts[#texts + 1] = { text = text, x = x, y = y }
    return real.draw(text, x, y)
  end
  gfx.newCanvas = function(w, h, settings)
    canvases[#canvases + 1] = { w = w, h = h, settings = settings }
    return real.newCanvas(w, h, settings)
  end
  local ok, err = pcall(fn)
  gfx.rectangle, gfx.setColor, gfx.newCanvas = real.rectangle, real.setColor, real.newCanvas
  gfx.newShader, Font.draw = real.newShader, real.draw
  if not ok then error(err, 0) end
  return { rects = rects, texts = texts, canvases = canvases, last = color }
end

local function near(a, b) return math.abs(a - b) < 1e-6 end
local ELEC = B.color("ELECTRIC")

-- a black-label pill (ELECTRIC): outline, fill, then the label from the tiles
local s = spy(function() B.drawPill("ELECTRIC", "ELECTRIC", 12, 122, 72, 12) end)
T.check(#s.rects >= 4, "a pill is built from filled rectangles")
local fills = 0
for _, r in ipairs(s.rects) do
  if near(r.color[1], ELEC[1] / 255) and near(r.color[2], ELEC[2] / 255) then fills = fills + 1 end
end
T.check(fills >= 2, "the body is filled in the type's own colour")
local darker = false
for _, r in ipairs(s.rects) do
  if near(r.color[1], ELEC[1] / 255 * 0.5) then darker = true end
end
T.check(darker, "with a darker outline of the same hue")
for _, r in ipairs(s.rects) do
  T.check(r.x >= 12 and r.x + r.w <= 12 + 72 and r.y >= 122 and r.y + r.h <= 122 + 12,
    "no rectangle strays outside the pill's own box")
end
T.eq(#s.texts, 1, "a black label is one Font.draw of the tiles")
T.eq(s.texts[1].text, "ELECTRIC", "with the label text")
T.eq(s.texts[1].x, 12 + math.floor((72 - Font.width("ELECTRIC")) / 2), "centred across the pill")
T.eq(s.texts[1].y, 122 + 2, "and vertically: 2px above and below an 8px glyph")
T.eq(#s.canvases, 0, "no canvas is needed for a black label")
T.check(near(s.last[1], 1) and near(s.last[2], 1) and near(s.last[3], 1),
  "the draw colour is left white for whoever draws next")

-- a white label needs the shader path.  The stub has no newShader, so hand
-- it one: this file tests OUR use of it, not LÖVE's.
local shaders = 0
local function fakeShader() shaders = shaders + 1 return { fake = true } end
local s2 = spy(function()
  gfx.newShader = fakeShader
  B.drawPill("FLYING", "FLYING", 12, 122, 56, 12)
  B.drawPill("FLYING", "FLYING", 100, 122, 56, 12)
end)
T.check(#s2.canvases >= 1, "a white label is rendered through a canvas")
for _, c in ipairs(s2.canvases) do
  T.check(type(c.settings) == "table" and c.settings.dpiscale == 1,
    "that canvas is made with dpiscale = 1, so a high-DPI phone reads it back 1:1")
end
T.eq(#s2.canvases, 1, "and it is cached: the second FLYING pill made no new canvas")

-- with no shader available the pill still shows, label in black
-- (a fresh copy of the module: B has cached the shader s2 handed it)
local s3 = spy(function()
  gfx.newShader = function() error("no shaders here") end
  dofile("mods/bills_pc_plus/TypeBadges.lua").drawPill("GHOST", "GHOST", 12, 122, 40, 12)
end)
T.eq(#s3.canvases, 0, "with no shader no canvas is spent on a label that cannot use it")
T.check(#s3.rects >= 4, "a pill still draws when the shader cannot be built")
T.check(#s3.texts == 1 and s3.texts[1].text == "GHOST",
  "and falls back to the plain tile label rather than an unlabelled pill")

-- ------- the option and the strip
local run = T.sdk.loadMod("mods/bills_pc_plus", { data = Data })
T.eq(#run.errors, 0, "loads clean (" .. tostring(run.errors[1]) .. ")")
local Screens = require("src.ui.Screens")
Screens.invalidate()

local row
for _, r in ipairs(run.loader.optionSchemas.bills_pc_plus or {}) do
  if r.key == "type_badges" then row = r end
end
T.check(row ~= nil, "the mod defines a type_badges option row")
T.eq(row and row.type, "toggle", "it is a toggle, so the manager draws ON/OFF")
T.eq(row and row.label, "TYPE BADGES", "labelled TYPE BADGES")
T.eq(row and row.default, true, "and it defaults on")

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

-- draw once, recording the text, the fills at the type rows, and the marks
local function drawOnce(grid)
  local texts, rects, marks = {}, {}, {}
  local realDraw, realRect, realMark = Font.draw, gfx.rectangle, PaletteFX.markTrueColor
  Font.draw = function(text, x, y)
    texts[#texts + 1] = { text = tostring(text), x = x, y = y }
    return realDraw(text, x, y)
  end
  gfx.rectangle = function(mode, x, y, w, h)
    if mode == "fill" and y >= L.STATS_Y + 3 * L.ROW - L.ROW then
      rects[#rects + 1] = { x = x, y = y, w = w, h = h }
    end
    return realRect(mode, x, y, w, h)
  end
  PaletteFX.markTrueColor = function(x, y, w, h)
    marks[#marks + 1] = { x = x, y = y, w = w, h = h }
    return realMark(x, y, w, h)
  end
  local ok, err = pcall(function() grid:draw() end)
  Font.draw, gfx.rectangle, PaletteFX.markTrueColor = realDraw, realRect, realMark
  if not ok then error(err, 0) end
  local function drew(t)
    for _, d in ipairs(texts) do if d.text == t then return d end end
  end
  return { texts = texts, rects = rects, marks = marks, drew = drew }
end

-- default on: two pills, one line, no slash-joined text
run.loader.modOptions.bills_pc_plus = nil
local grid = openGrid(gameWith({ "ELECTRIC", "FLYING" }), "WITHDRAW POKéMON")
grid.counter = 0
local d = drawOnce(grid)
T.check(d.drew("ELECTRIC/FLYING") == nil, "with badges on the slash-joined text is gone")
local e, f = d.drew("ELECTRIC"), d.drew("FLYING")
T.check(e ~= nil and f ~= nil, "each type is its own label")
local py = L.badgeY(false)
if e and f then
  T.eq(e.y, py + 2, "the first label sits in its pill")
  T.eq(f.y, e.y, "both on one line")
  T.check(f.x > e.x + Font.width("ELECTRIC"), "the second follows the first, not over it")
  T.check(f.x + Font.width("FLYING") <= 152, "and ends inside the frame")
end
T.eq(#d.marks, 1, "the pills' rectangle is exempted from palette shading once")
if d.marks[1] then
  T.check(d.marks[1].x <= L.STATS_X + L.BADGE_MARGIN and d.marks[1].y <= py
    and d.marks[1].x + d.marks[1].w >= 144 and d.marks[1].y + d.marks[1].h >= py + L.BADGE_H,
    "and it covers both pills")
end

-- a single-type mon gets one pill and nothing where the second would be
grid = openGrid(gameWith({ "ELECTRIC" }), "WITHDRAW POKéMON")
grid.counter = 0
d = drawOnce(grid)
T.check(d.drew("ELECTRIC") ~= nil, "a single type draws one pill")
T.check(d.drew("FLYING") == nil, "and no second")
-- a mon whose two types match (Gen 2 stores the pair) draws one, not two
grid = openGrid(gameWith({ "FIRE", "FIRE" }), "WITHDRAW POKéMON")
grid.counter = 0
local n = 0
for _, t in ipairs(drawOnce(grid).texts) do if t.text == "FIRE" then n = n + 1 end end
T.eq(n, 1, "a doubled type prints once, as the text line does")

-- the option off: today's text line, byte for byte
run.loader.modOptions.bills_pc_plus = { type_badges = false }
grid = openGrid(gameWith({ "ELECTRIC", "FLYING" }), "WITHDRAW POKéMON")
grid.counter = 0
d = drawOnce(grid)
local line = d.drew("ELECTRIC/FLYING")
T.check(line ~= nil, "with the option off the plain text line returns")
T.eq(line and line.y, L.STATS_Y + 4 * L.ROW, "on the last row")
T.eq(line and line.x, L.STATS_X, "at the strip's left edge")
T.eq(#d.marks, 0, "and nothing is exempted from palette shading")

-- read per draw: flipping it lands on the next frame with no reload
run.loader.modOptions.bills_pc_plus = { type_badges = true }
d = drawOnce(grid)
T.check(d.drew("ELECTRIC/FLYING") == nil and d.drew("ELECTRIC") ~= nil,
  "turning it back on restores the pills on the very next draw")

-- DVs hidden: the pills rise a row with the line they replace
run.loader.modOptions.bills_pc_plus = { type_badges = true, dv_display = false }
d = drawOnce(grid)
T.eq(d.drew("ELECTRIC").y, L.badgeY(true) + 2, "the pills rise a row when the DVs are hidden")

-- deposit mode: box C covers this row, so no pills
run.loader.modOptions.bills_pc_plus = nil
local dep = openGrid(gameWith({ "ELECTRIC", "FLYING" }, {
  species = "FIXMON_A", level = 5, hp = 20, dvs = {}, statExp = {}, moves = {},
  stats = { hp = 20, attack = 12, defense = 12, speed = 12, special = 12 } }),
  "DEPOSIT POKéMON")
dep.counter = 0
d = drawOnce(dep)
T.check(d.drew("ELECTRIC") == nil and #d.marks == 0, "deposit mode draws no pills under box C")

run.loader.modOptions.bills_pc_plus = nil
run.release()
Screens.invalidate()
T.finish("bills_pc_plus type badges drawing")
