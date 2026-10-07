-- Standalone: luajit mods/bills_pc_plus/tests/held_item_test.lua
--
-- A Gen 2 Pokemon holding something draws the party menu's marker: the icon's
-- bottom-left 8x8 tile is REPLACED by the held-item tile (.SpawnItemIcon,
-- engine/gfx/mon_icons.asm), not covered by it.  Separate from
-- bills_pc_plus_test.lua because that file sits at LuaJIT's 200-local ceiling.
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local T = require("tests.modkit")
local Assets = require("src.render.Assets")
local Engine = dofile("mods/bills_pc_plus/Engine.lua")

-- Gold's PartyMenu.heldMarkerRow, standing in so the test pins OUR use of it:
-- nil for an empty hand, 0 for mail, 1 for an item.
local realGold = package.loaded["src.ui.gen2.PartyMenu"]
local function setGold(fn)
  package.loaded["src.ui.gen2.PartyMenu"] = { heldMarkerRow = fn }
end
local function rowOf(mon)
  if mon.item == nil or mon.item == "" then return nil end
  return mon.mail and 0 or 1
end

local ICON, MARKER = "fake/icon.png", "fake/held.png"
local function img(w, h)
  return { getDimensions = function() return w, h end,
    getWidth = function() return w end, getHeight = function() return h end }
end
local realImage = Assets.image
Assets.image = function(path)
  if path == ICON then return img(16, 32) end
  if path == MARKER then return img(8, 16) end
  error("unexpected asset " .. tostring(path))
end

local function gameWith(withMarker)
  local icons = {
    species = { PIKACHU = "ICON_PIKACHU" },
    icons = { ICON_PIKACHU = { image = ICON }, ICON_EGG = { image = ICON } },
  }
  if withMarker then icons.heldItem = { image = MARKER } end
  return { data = { gen2Icons = icons,
    gen2Palettes = { partyMenu = { { "p0", "p1", "p2", "p3" } } } } }
end

-- Record every blit: which image, which quad rectangle, where.
local function draw(engine, game, mon, animated)
  local blits = {}
  local realG = love.graphics
  love.graphics = setmetatable({
    newQuad = function(x, y, w, h) return { x = x, y = y, w = w, h = h } end,
    draw = function(image, quad, x, y)
      blits[#blits + 1] = { image = image, q = quad, x = x, y = y }
    end,
  }, { __index = realG })
  local ok, err = pcall(engine.drawIcon, engine, game, mon, 40, 24, animated)
  love.graphics = realG
  if not ok then error(err, 0) end
  return blits
end

local function find(blits, x, y)
  for _, b in ipairs(blits) do if b.x == x and b.y == y then return b end end
end

do
  setGold(rowOf)
  local engine = Engine.new(true)
  local game = gameWith(true)

  local plain = draw(engine, game, { species = "PIKACHU" })
  T.eq(#plain, 1, "an empty hand draws the icon as one whole blit")
  T.eq(plain[1] and plain[1].q.w, 16, "and it is the full 16px frame")

  local held = draw(engine, game, { species = "PIKACHU", item = "BERRY" })
  T.eq(#held, 4, "a holder draws four 8x8 blits: three icon tiles and a marker")
  local tl, tr, br = find(held, 40, 24), find(held, 48, 24), find(held, 48, 32)
  T.check(tl and tr and br, "the three icon tiles keep their corners")
  T.eq(tl and tl.q.y, 0, "top-left reads frame 0 of the sheet")
  T.eq(br and br.q.y, 8, "bottom-right reads the lower half of frame 0")
  local marker = find(held, 40, 32)
  T.check(marker ~= nil, "the marker sits in the bottom-left corner")
  T.eq(marker and marker.image.getHeight(), 16, "and it is the marker sheet")
  T.eq(marker and marker.q.y, 8, "an item uses row 1 of that sheet")
  local atCorner = 0
  for _, b in ipairs(held) do
    if b.x == 40 and b.y == 32 then atCorner = atCorner + 1 end
  end
  T.eq(atCorner, 1, "the icon's own bottom-left tile is replaced, not drawn under it")

  local anim = draw(engine, game, { species = "PIKACHU", item = "BERRY" }, true)
  T.eq(find(anim, 40, 24).q.y, 16,
    "an animated holder reads the second frame for its icon tiles")
  T.eq(find(anim, 40, 32).q.y, 8, "while the marker does not bob")

  local mail = draw(engine, game,
    { species = "PIKACHU", item = "FLOWER_MAIL", mail = true })
  T.eq(find(mail, 40, 32).q.y, 0, "mail uses row 0 of the marker sheet")
end

do
  setGold(function() return nil end)
  local engine = Engine.new(true)
  local egg = draw(engine, gameWith(true), { species = "PIKACHU", isEgg = true, item = "BERRY" })
  T.eq(#egg, 1, "Gold's answer decides: no marker, so the egg stays whole")
end

do
  setGold(rowOf)
  local engine = Engine.new(true)
  local old = draw(engine, gameWith(false), { species = "PIKACHU", item = "BERRY" })
  T.eq(#old, 1, "a cache with no heldItem sheet draws the icon whole, no error")
end

do
  package.loaded["src.ui.gen2.PartyMenu"] = nil
  local engine = Engine.new(true)
  local ok = pcall(draw, engine, gameWith(true),
    { species = "PIKACHU", item = "BERRY" })
  T.check(ok, "an engine with no Gold PartyMenu module draws without error")
end

do
  -- Gen 1 has no held items and no marker: the arm is the party menu's own.
  setGold(rowOf)
  local engine = Engine.new(false)
  T.eq(engine:heldMarkerFor(gameWith(true),
    { species = "PIKACHU", item = "BERRY" }), nil,
    "Gen 1 never asks for a marker")
end

Assets.image = realImage
package.loaded["src.ui.gen2.PartyMenu"] = realGold
T.finish("bills_pc_plus held_item")
