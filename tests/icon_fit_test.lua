-- Standalone: luajit mods/bills_pc_plus/tests/icon_fit_test.lua
--
-- Oversized mod icons are scaled into their 16px cell, not cropped by it.
-- Separate from bills_pc_plus_test.lua because that file sits at LuaJIT's
-- 200-local ceiling and cannot take another top-level local.
--
-- The break this pins reached a player through HGSS Visual Overhaul, which
-- replaces PartyMenu.drawIcon with one that draws a padded 32x32 frame whole
-- at (x, y) (hgss_sprites/main.lua:5680).  The per-cell scissor kept only
-- that frame's top-left quarter -- mostly padding -- so every box and party
-- icon showed as a sliver of art in the corner of its cell.
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local T = require("tests.modkit")
local Data = require("tests.modkit.fixtures").fresh()

local run = T.sdk.loadMod("mods/bills_pc_plus", { data = Data })
T.eq(#run.errors, 0, "loads clean (" .. tostring(run.errors[1]) .. ")")

local Screens = require("src.ui.Screens")
local PartyMenu = require("src.ui.PartyMenu")
Screens.invalidate()

local function newMon()
  return { species = "FIXMON_A", level = 12, hp = 20, dvs = {}, statExp = {},
    moves = {},
    stats = { hp = 20, attack = 12, defense = 12, speed = 12, special = 12 } }
end

local function openGrid(g, rowLabel)
  local captured = {}
  g.stack = { push = function(_, st) captured[#captured + 1] = st end,
              pop = function() end }
  local menu = Screens.get(g, "BoxMenu").new(g)
  for _, item in ipairs(menu.items) do
    if item.label == rowLabel and item.onSelect then item.onSelect() end
  end
  return captured[#captured]
end

-- The stub's newQuad discards its viewport, so the fake icon carries its own.
local ICON = { getDimensions = function() return 32, 64 end }
local function quad(w, h)
  return { getViewport = function() return 0, 0, w, h end }
end

-- Draws the screen with `painter` standing in for PartyMenu.drawIcon and
-- returns every blit of ICON as the window rect it actually covers, through
-- whatever translate/scale was live.  Other draws (frames, text, the front
-- sprite) pass through untouched and are not recorded.
-- opts.readback lets the screen read an image's pixels back: the stub's own
-- canvases cannot (no newImageData), so the default run is the no-readback
-- case, and a readback run hands out canvases that report the alpha of
-- whatever fixture image was last drawn onto them.  Returns the recorded
-- blits and how many canvases were created.
local function iconRects(grid, painter, opts)
  local realG, realIcon = love.graphics, PartyMenu.drawIcon
  local tx, ty, kx, ky = 0, 0, 1, 1
  local saved, rects = {}, {}
  local target, canvases = nil, 0
  local shim = setmetatable({
    push = function(...)
      saved[#saved + 1] = { tx, ty, kx, ky, target }
      return realG.push(...)
    end,
    pop = function(...)
      local s = table.remove(saved)
      if s then tx, ty, kx, ky, target = s[1], s[2], s[3], s[4], s[5] end
      return realG.pop(...)
    end,
    origin = function() tx, ty, kx, ky = 0, 0, 1, 1 end,
    translate = function(dx, dy) tx, ty = tx + dx * kx, ty + dy * ky end,
    scale = function(sx, sy) kx, ky = kx * sx, ky * (sy or sx) end,
    transformPoint = function(x, y) return tx + x * kx, ty + y * ky end,
    clear = function() end,
    draw = function(img, q, x, y, r, sx, sy)
      if target then
        target.painted = img
        return
      end
      if not (img == ICON or (type(img) == "table" and img.alphaAt)) then
        return
      end
      if type(q) ~= "table" then return end
      local _, _, w, h = q:getViewport()
      sx = sx or 1
      sy = sy or sx
      local ax, bx = x, x + w * sx
      local ay, by = y, y + h * sy
      rects[#rects + 1] = {
        tx + math.min(ax, bx) * kx, ty + math.min(ay, by) * ky,
        math.abs(bx - ax) * kx, math.abs(by - ay) * ky,
        shader = realG.getShader(),
        x = x, y = y, tx = tx, ty = ty, kx = kx, ky = ky,
      }
    end,
  }, { __index = realG })
  if opts and opts.readback then
    shim.newCanvas = function(w, h)
      canvases = canvases + 1
      local canvas = { w = w, h = h }
      function canvas:newImageData()
        local painted = self.painted
        return {
          getPixel = function(_, px, py)
            local a = painted and painted.alphaAt and painted.alphaAt(px, py)
            return 1, 1, 1, a or 0
          end,
        }
      end
      function canvas:release() end
      return canvas
    end
    shim.setCanvas = function(c) target = c end
    shim.getCanvas = function() return target end
  end
  PartyMenu.drawIcon = painter
  love.graphics = shim
  local ok, err = pcall(grid.draw, grid)
  love.graphics, PartyMenu.drawIcon = realG, realIcon
  if not ok then error(err, 0) end
  return rects, canvases
end

local function fmt(r)
  return r and ("%g,%g %gx%g"):format(r[1], r[2], r[3], r[4]) or "none"
end

-- HGSS's draw, reduced to what matters here: one 32x32 frame, whole, at
-- the cell's top-left.
local function hgss(game, mon, x, y)
  love.graphics.draw(ICON, quad(32, 32), x, y)
  return true
end

-- The engine's own 16x16 frame (src/ui/PartyMenu.lua:287).
local function vanilla(game, mon, x, y)
  love.graphics.draw(ICON, quad(16, 16), x, y)
  return true
end

-- The engine's symmetric icons: the left 8px column, then the same column
-- flipped about the block's right edge (src/ui/PartyMenu.lua:281-285).
local function mirrored(game, mon, x, y)
  local half = quad(8, 16)
  love.graphics.draw(ICON, half, x, y)
  love.graphics.draw(ICON, half, x + 16, y, 0, -1, 1)
  return true
end

-- The mon goes in before the grid opens: BoxSession.new mirrors every box
-- into its sparse layout once, at construction (BoxSession.lua:161-163), so
-- a mon written into save.boxes afterwards is never drawn.
local function boxGrid()
  local g = { data = Data, save = { party = {}, boxes = nil, currentBox = 1 },
    input = { wasPressed = function() return false end,
              isDown = function() return false end } }
  require("src.pokemon.Boxes").ensure(g.save)
  g.save.boxes[1] = { newMon() }
  return openGrid(g, "WITHDRAW POKéMON")
end

local function depositGrid()
  local g = { data = Data,
    save = { party = { newMon() }, boxes = nil, currentBox = 1 },
    input = { wasPressed = function() return false end,
              isDown = function() return false end } }
  return openGrid(g, "DEPOSIT POKéMON")
end

-- ------- a 32x32 box icon fills its cell at half size
do
  local rects = iconRects(boxGrid(), hgss)
  T.eq(#rects, 1, "an oversized box icon is blitted exactly once")
  T.eq(fmt(rects[1]), "8,16 16x16",
    "and lands scaled into box slot 1's cell, not cropped to its corner")
end

-- ------- the party row gets the same fit
do
  local rects = iconRects(depositGrid(), hgss)
  T.eq(#rects, 1, "an oversized party icon is blitted exactly once")
  T.eq(fmt(rects[1]), "8,120 16x16",
    "and lands scaled into party slot 1's cell")
end

-- ------- a vanilla 16x16 icon is left exactly as the engine drew it
do
  local rects = iconRects(boxGrid(), vanilla)
  T.eq(#rects, 1, "a cell-sized icon is blitted exactly once")
  T.eq(fmt(rects[1]), "8,16 16x16", "at its own size, unmoved")
end

-- ------- a mirrored icon's flipped half does not read as oversized
-- Its second blit has sx = -1 and an origin at the cell's right edge; a
-- bounds check that ignores the sign sees x..x+24 and would shrink a
-- perfectly sized icon.
do
  local rects = iconRects(boxGrid(), mirrored)
  T.eq(#rects, 2, "both halves of a mirrored icon are blitted")
  T.eq(fmt(rects[1]), "8,16 8x16", "the left half, unscaled")
  T.eq(fmt(rects[2]), "16,16 8x16", "and the flipped right half, unscaled")
end

-- ------- state bound around a blit is still bound when the blit lands
-- Gold's icon blit runs inside GbcPalette.with (Engine.lua:430), which binds
-- the palette shader for that body alone.  A fit that records blits and
-- issues them after the draw returns would issue them with no shader bound:
-- grey art, and no test that counts palette binds would notice.
do
  local SHADER = {}
  local function shaded(game, mon, x, y)
    love.graphics.setShader(SHADER)
    love.graphics.draw(ICON, quad(32, 32), x, y)
    love.graphics.setShader()
    return true
  end
  local rects = iconRects(boxGrid(), shaded)
  T.eq(#rects, 1, "a shaded oversized icon is blitted exactly once")
  T.eq(fmt(rects[1]), "8,16 16x16", "and still fits its cell")
  T.check(rects[1] and rects[1].shader == SHADER,
    "with the shader its painter bound around the blit still bound")
end

-- ------- the padding is cropped before the fit
-- HGSS frames are 32x32 with the art in the middle: 22px across on the
-- median icon.  Fitting the whole frame drew every icon at half size; fitting
-- the visible art draws most of them nearly twice that.

local L = dofile("mods/bills_pc_plus/Layout.lua")

-- Visible-art bounds are the union over every frame in the column, so an
-- animated icon keeps one size while it flips between its two poses.
do
  local boxes = { { 8, 10, 23, 29 }, { 6, 44, 25, 61 } }
  local function alphaAt(x, y)
    for _, r in ipairs(boxes) do
      if x >= r[1] and x <= r[3] and y >= r[2] and y <= r[4] then return 1 end
    end
    return 0
  end
  local function bounds(...) return table.concat({ L.artBounds(...) }, ",") end
  T.eq(bounds(32, 64, 0, 0, 32, 32, alphaAt), "6,10,20,20",
    "art bounds cover both frames of a 32x64 sheet, relative to the frame")
  T.eq(bounds(32, 64, 0, 32, 32, 32, alphaAt), "6,10,20,20",
    "and asking from the second frame gives the same answer")
  T.eq(L.artBounds(32, 32, 0, 0, 32, 32, function() return 0 end), nil,
    "a frame with nothing visible has no art bounds")
end

-- Placement in a cell: scale the art's larger side down to the cell (never
-- up), centre it across, stand it on the cell's floor.
do
  local function place(...) return table.concat({ L.artPlacement(...) }, ",") end
  T.eq(place(16, 20, 20), "0.8,0,0", "20x20 art scales to 16x16, flush")
  T.eq(place(16, 16, 20), "0.8,1.6,0",
    "16x20 art scales by its height and centres across")
  T.eq(place(16, 11, 16), "1,2,0", "11x16 art is not scaled, only centred")
  T.eq(place(16, 13, 15), "1,1,1", "13x15 art centres and stands on the floor")
end

local function region(qx, qy, w, h)
  return { getViewport = function() return qx, qy, w, h end }
end

-- A fixture image: its size, and which pixels are opaque ({x0, y0, x1, y1}
-- inclusive boxes in sheet coordinates).
local function sheet(w, h, boxes)
  return {
    getDimensions = function() return w, h end,
    alphaAt = function(x, y)
      for _, r in ipairs(boxes) do
        if x >= r[1] and x <= r[3] and y >= r[2] and y <= r[4] then return 1 end
      end
      return 0
    end,
  }
end

-- Where a region of a recorded blit landed on screen: (ax, ay) is the
-- region's offset inside the frame, through the blit's own transform.
local function landed(r, ax, ay, aw, ah)
  return fmt({ r.tx + (r.x + ax) * r.kx, r.ty + (r.y + ay) * r.ky,
    aw * r.kx, ah * r.ky })
end

do
  local SHEET = sheet(32, 64, { { 8, 10, 23, 29 }, { 6, 44, 25, 61 } })
  local function frame(n)
    return function(game, mon, x, y)
      love.graphics.draw(SHEET, region(0, n * 32, 32, 32), x, y)
      return true
    end
  end
  local r0, made0 = iconRects(boxGrid(), frame(0), { readback = true })
  T.eq(#r0, 1, "a padded icon is blitted exactly once")
  T.eq(r0[1] and landed(r0[1], 6, 10, 20, 20), "8,16 16x16",
    "its visible art, not its padded frame, fills box slot 1's cell")
  T.eq(made0, 1, "its pixels are read once")

  local r1, made1 = iconRects(boxGrid(), frame(1), { readback = true })
  T.eq(r1[1] and fmt(r1[1]), r0[1] and fmt(r0[1]),
    "the second animation frame lands at the same size and place")
  T.eq(made1, 0, "and reuses the first frame's reading")
end

do
  local SMALL = sheet(32, 32, { { 9, 17, 21, 31 } })
  local rects = iconRects(boxGrid(), function(game, mon, x, y)
    love.graphics.draw(SMALL, region(0, 0, 32, 32), x, y)
    return true
  end, { readback = true })
  T.eq(rects[1] and landed(rects[1], 9, 17, 13, 15), "9,17 13x15",
    "art smaller than the cell is never enlarged, and stands centred on its floor")
end

do
  local EMPTY = sheet(32, 32, {})
  local rects = iconRects(boxGrid(), function(game, mon, x, y)
    love.graphics.draw(EMPTY, region(0, 0, 32, 32), x, y)
    return true
  end, { readback = true })
  T.eq(rects[1] and fmt(rects[1]), "8,16 16x16",
    "a frame with no visible art falls back to fitting the whole frame")
end

T.finish("bills_pc_plus icon_fit")
