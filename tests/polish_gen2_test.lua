-- Standalone: luajit mods/bills_pc_plus/tests/polish_gen2_test.lua
--
-- The Gen 2 half of polish_test.lua: the column grid on the five-column strip,
-- and the pills centred under it.  Its own file because one process loads one
-- generation.  The shared geometry is pinned in polish_test.lua; this is the
-- drawing, which is where Gen 2 differs: its shared Special DV straddles the
-- SA/SD gap, so one line has to stop above the DV row.
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local T = require("tests.modkit")
local Data = require("tests.modkit.fixtures").fresh()
local Font = require("src.render.Font")
local gfx = love.graphics
local L = dofile("mods/bills_pc_plus/Layout.lua")

local run = T.sdk.loadMod("mods/bills_pc_plus", { data = Data, generation = 2 })
T.eq(#run.errors, 0, "loads clean on gen 2 (" .. tostring(run.errors[1]) .. ")")
T.eq(run.mod and run.mod.state, "loaded", "the mod runs on gen 2")
local Screens = require("src.ui.Screens")
Screens.invalidate()

local function gen2Mon()
  return { species = "FIXMON_C", level = 50, hp = 20,
    dvs = { attack = 15, defense = 10, speed = 10, special = 10 },
    statExp = {}, moves = {},
    stats = { hp = 20, attack = 112, defense = 98, speed = 87,
              specialAttack = 140, specialDefense = 131 } }
end

local function openGrid(label)
  local g = {
    data = Data,
    save = { party = { gen2Mon() }, currentBox = 1, boxes = { { gen2Mon() } } },
    stack = { push = function() end, pop = function() end },
    input = { wasPressed = function() return false end,
              isDown = function() return false end },
  }
  Data.pokemon.FIXMON_C = Data.pokemon.FIXMON_C or {}
  Data.pokemon.FIXMON_C.types = { "ELECTRIC", "FLYING" }
  local captured
  g.stack = { push = function(_, st) captured = st end, pop = function() end }
  local menu = Screens.get(g, "Gen2BoxMenu").new(g)
  for _, item in ipairs(menu.items) do
    if item.label == label then item.onSelect() end
  end
  captured.counter = 0
  return captured
end

-- 1px-wide fills that start on the header row: the strip's hairlines
local function hairlines(grid)
  local out = {}
  local real = gfx.rectangle
  gfx.rectangle = function(mode, x, y, w, h)
    if mode == "fill" and w == 1 and y == L.STATS_Y and h > 1 then
      out[#out + 1] = { x = x, h = h }
    end
    return real(mode, x, y, w, h)
  end
  local ok, err = pcall(function() grid:draw() end)
  gfx.rectangle = real
  if not ok then error(err, 0) end
  table.sort(out, function(a, b) return a.x < b.x end)
  return out
end

local lines = hairlines(openGrid("WITHDRAW POKéMON"))
T.eq(#lines, 4, "five columns draw four hairlines")
for i, want in ipairs({ 33, 61, 89, 117 }) do
  T.eq(lines[i] and lines[i].x, want, "line " .. i .. " is at x=" .. want)
end
for i = 1, 3 do
  T.eq(lines[i] and lines[i].h, 3 * L.ROW - 1, "line " .. i .. " runs through the DV row")
end
T.eq(lines[4] and lines[4].h, 2 * L.ROW - 1,
  "the line through the SA/SD gap stops above the shared Special DV")

-- the shared DV is centred on the gap that line sits in, which is why
T.check(L.STATS_DV_SHARED_CX >= L.STATS_COLS_5[4] + L.STATS_COL_W
  and L.STATS_DV_SHARED_CX <= L.STATS_COLS_5[5],
  "the shared DV straddles the gap the fourth line is in")

-- deposit mode: the party frame covers the DV row, every line stops at the values
lines = hairlines(openGrid("DEPOSIT POKéMON"))
T.eq(#lines, 4, "deposit mode draws all four")
for i = 1, 4 do
  T.eq(lines[i] and lines[i].h, 2 * L.ROW - 1, "line " .. i .. " stops at the values")
end

-- the pills are centred under the five columns too
do
  local texts = {}
  local real = Font.draw
  Font.draw = function(text, x, y)
    texts[#texts + 1] = { text = tostring(text), x = x, y = y }
    return real(text, x, y)
  end
  local grid = openGrid("WITHDRAW POKéMON")
  local ok, err = pcall(function() grid:draw() end)
  Font.draw = real
  if not ok then error(err, 0) end
  local e, f
  for _, t in ipairs(texts) do
    if t.text == "ELECTRIC" then e = t end
    if t.text == "FLYING" then f = t end
  end
  T.check(e ~= nil and f ~= nil, "both type pills are drawn")
  if e and f then
    local we = L.pillWidth(Font.width("ELECTRIC"))
    local wf = L.pillWidth(Font.width("FLYING"))
    local first = e.x - math.floor((we - Font.width("ELECTRIC")) / 2)
    local last = f.x - math.floor((wf - Font.width("FLYING")) / 2) + wf
    T.eq(first, L.STRIP_CX - math.floor((we + L.BADGE_GAP + wf) / 2),
      "the pair starts centred on x=80")
    T.check(last <= 152, "and ends inside the frame")
  end
end

T.finish("bills_pc_plus polish gen2")
