-- The type line drawn as coloured pills (the TYPE BADGES option), in the
-- style of the later generations' summary screens.
--
-- The art those screens use is extracted from a player's own cartridge and
-- cannot ship, so these are drawn from rectangles.  This file holds the pure
-- parts -- the colour table and the label colour -- and the drawing, which needs
-- the engine.  The geometry (a pill's width, where it goes) lives in Layout
-- with the rest of the strip's arithmetic, and is passed in: a mod cannot
-- require its own files.

local TypeBadges = {}

-- Fill colours, rgb 0..255.  The Gen 3 set: it has all seventeen types the
-- two generations print, and pill and label read against each other on a
-- Game Boy palette's white.
local COLORS = {
  NORMAL   = { 0xa8, 0xa8, 0x78 }, FIRE     = { 0xf0, 0x80, 0x30 },
  WATER    = { 0x68, 0x90, 0xf0 }, ELECTRIC = { 0xf8, 0xd0, 0x30 },
  GRASS    = { 0x78, 0xc8, 0x50 }, ICE      = { 0x98, 0xd8, 0xd8 },
  FIGHTING = { 0xc0, 0x30, 0x28 }, POISON   = { 0xa0, 0x40, 0xa0 },
  GROUND   = { 0xe0, 0xc0, 0x68 }, FLYING   = { 0xa8, 0x90, 0xf0 },
  PSYCHIC  = { 0xf8, 0x58, 0x88 }, BUG      = { 0xa8, 0xb8, 0x20 },
  ROCK     = { 0xb8, 0xa0, 0x38 }, GHOST    = { 0x70, 0x58, 0x98 },
  DRAGON   = { 0x70, 0x38, 0xf8 }, DARK     = { 0x70, 0x58, 0x48 },
  STEEL    = { 0xb8, 0xb8, 0xd0 },
}

-- Which pills take a WHITE label.  Chosen by looking at each pill rendered
-- with the game's glyphs, not by a lightness cutoff: BUG (0.635) and FLYING
-- (0.636) are the same brightness and want opposite answers -- a thin black
-- glyph on FLYING's mid purple reads weak where the same glyph on BUG's
-- olive does not.
local WHITE_TEXT = {
  FLYING = true, GHOST = true, DRAGON = true, DARK = true, FIGHTING = true,
  POISON = true, WATER = true, FIRE = true, PSYCHIC = true, ROCK = true,
}

function TypeBadges.color(name)
  return COLORS[name] or COLORS.NORMAL
end

function TypeBadges.whiteText(name)
  return WHITE_TEXT[name] == true
end

-- ------- drawing
--
-- The font's glyphs are black tiles on a transparent ground, whatever colour
-- is set, so a WHITE label cannot be drawn directly.  It is drawn once into a
-- small canvas and put on the pill through a shader that keeps only the
-- glyphs' alpha, painted white.  One canvas per label, kept: a box shows the
-- same handful of names for as long as it is open.
--
-- The canvas is made with dpiscale = 1.  On a high-DPI phone LÖVE otherwise
-- gives a canvas the display's scale, and an 8px-tall label comes out at 2-3x
-- the texels the draw expects (src/render/PixelCanvas.lua documents the same
-- trap).  Any failure -- no shader, no canvas -- falls back to the plain tile
-- label in black: the pill still says what it is.
local Font = require("src.render.Font")

local WHITE_SHADER = [[
  vec4 effect(vec4 c, Image t, vec2 uv, vec2 sc) {
    return vec4(1.0, 1.0, 1.0, Texel(t, uv).a);
  }
]]

local shader, shaderFailed
local function whiteShader()
  if shader or shaderFailed then return shader end
  local ok, made = pcall(love.graphics.newShader, WHITE_SHADER)
  if ok and made then shader = made else shaderFailed = true end
  return shader
end

local labelCanvases = {}
local function labelCanvas(label)
  local cached = labelCanvases[label]
  if cached ~= nil then return cached or nil end
  local gfx = love.graphics
  local ok, canvas = pcall(gfx.newCanvas, Font.width(label), 8, { dpiscale = 1 })
  if not (ok and canvas) then
    labelCanvases[label] = false
    return nil
  end
  local previous = gfx.getCanvas()
  gfx.push("all")
  gfx.origin()
  gfx.setScissor()
  gfx.setCanvas(canvas)
  gfx.clear(0, 0, 0, 0)
  gfx.setColor(1, 1, 1, 1)
  Font.draw(label, 0, 0)
  gfx.pop()
  gfx.setCanvas(previous)
  labelCanvases[label] = canvas
  return canvas
end

-- One pill: a darker outline with its corner pixels cut, the type's fill, a
-- lighter top row, then the label centred.  (x, y, w, h) is the pill's box.
function TypeBadges.drawPill(name, label, x, y, w, h)
  local gfx = love.graphics
  local c = TypeBadges.color(name)
  local r, g, b = c[1] / 255, c[2] / 255, c[3] / 255
  gfx.setColor(r * 0.5, g * 0.5, b * 0.5, 1)
  gfx.rectangle("fill", x + 1, y, w - 2, h)
  gfx.rectangle("fill", x, y + 1, w, h - 2)
  gfx.setColor(r, g, b, 1)
  gfx.rectangle("fill", x + 2, y + 1, w - 4, h - 2)
  gfx.rectangle("fill", x + 1, y + 2, w - 2, h - 4)
  gfx.setColor(math.min(1, r + 0.18), math.min(1, g + 0.18),
    math.min(1, b + 0.18), 1)
  gfx.rectangle("fill", x + 2, y + 1, w - 4, 1)

  local tx = x + math.floor((w - Font.width(label)) / 2)
  local ty = y + math.floor((h - 8) / 2)
  local sh = TypeBadges.whiteText(name) and whiteShader() or nil
  local canvas = sh and labelCanvas(label) or nil
  if canvas then
    local previous = gfx.getShader()
    gfx.setShader(sh)
    gfx.setColor(1, 1, 1, 1)
    gfx.draw(canvas, tx, ty)
    gfx.setShader(previous)
  else
    gfx.setColor(0, 0, 0, 1)
    Font.draw(label, tx, ty)
  end
  gfx.setColor(1, 1, 1, 1)
end

return TypeBadges
