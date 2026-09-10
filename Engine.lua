-- Per-generation seam.  Gold is a second engine beside Gen 1
-- (src/core/Game2.lua), and the mod API on top is deliberately one API, so
-- only a handful of places actually differ: the icon draw path, the screen
-- ids, and happiness.  They live here rather than as branches scattered
-- through main.lua.
--
-- The generation is passed IN, never sniffed.  The screens registry serves
-- both generations and Gold's screens carry Gen2-prefixed ids so a mod
-- replacing Gold's party menu does not also replace Red's -- which means the
-- id this mod's factory was registered under already says which boot is
-- running.  A version allow-list would be the wrong answer twice over: it
-- excludes the mod from a future game by construction, and this already
-- knows.

local Engine = {}
Engine.__index = Engine

function Engine.new(gen2)
  return setmetatable({ gen2 = gen2 and true or false }, Engine)
end

-- STATS on a stored mon opens the summary screen, which is a different id
-- per generation (Screens.GEN2_IDS in src/ui/Screens.lua).
function Engine:summaryScreenId()
  return self.gen2 and "Gen2SummaryMenu" or "SummaryMenu"
end

local PartyMenu = require("src.ui.PartyMenu")
local Sprites = require("src.pokemon.Sprites")
local Assets = require("src.render.Assets")

-- Gold's icon sheets are 16px wide with the two animation frames stacked
-- vertically at a 16px pitch, which is how src/ui/gen2/PartyMenu.lua quads
-- them (newQuad(0, frame * 16, ...)).
local G2_ICON = 16

-- Resolve a Gen 2 mon's icon image.  Gold keys per-species sheets off
-- data.gen2Icons.species and stores the path at
-- data.gen2Icons.icons[id].image -- NOT data.icons, which is the Gen 1
-- table of nine shared CLASS names with the path stored directly.
-- src/core/Game2.lua:1036-1037 namespaces the whole family (gen2Icons,
-- gen2Palettes, ...) precisely so it cannot collide with the Gen 1 keys of
-- the same idea; src/ui/gen2/PartyMenu.lua:144 reads the same field
-- (`opts.icons or data.gen2Icons`), which this mirrors.
--
-- ReadMonMenuIcon (engine/gfx/mon_icons.asm): an EGG slot draws ICON_EGG --
-- the `cp EGG / jr z, .egg` arm -- before any species lookup runs, so a
-- stored egg must resolve to the egg sheet rather than the species it will
-- hatch into.  Mirrors src/ui/gen2/PartyMenu.lua:752-757.
--
-- The path goes out through Sprites.iconPath before loading, which is the
-- one icon API both generations genuinely share: Gold's own iconFor makes
-- the same call with the same ctx, precisely so a skin mod repaints icons in
-- both games.  Skipping it would make this the one screen an icon pack
-- cannot touch.
function Engine:iconImageFor(game, mon)
  local data = game and game.data
  local icons = data and data.gen2Icons
  if not (icons and mon and mon.species) then return nil end
  local iconId = mon.isEgg and "ICON_EGG"
    or (icons.species and icons.species[mon.species])
  local entry = iconId and icons.icons and icons.icons[iconId]
  local path = entry and entry.image
  path = Sprites.iconPath(data, mon, path, { name = iconId })
  if not path then return nil end
  local cache = self._iconCache
  if not cache then cache = {}; self._iconCache = cache end
  local cached = cache[path]
  if cached == nil then
    local ok, img = pcall(Assets.image, path)
    cached = ok and img or false
    cache[path] = cached
  end
  if not cached then return nil end
  return cached
end

-- Draw a mon's icon with its top-left at (x, y).
--
-- Gen 1 delegates rather than reimplementing: PartyMenu.drawIcon does an
-- OBP0 bake for built-in icon classes but loads mod-supplied art untouched,
-- and duplicating that split here would be a palette regression on art that
-- already works.  selected=false and counter=0 are deliberate and carried
-- over verbatim from the old call site -- with selected true, drawIcon reads
-- mon.stats.hp to pick an animation speed from HP-bar colour, meaningless
-- for a stored mon; forceAlt animates instead.
function Engine:drawIcon(game, mon, x, y, animated)
  if not self.gen2 then
    PartyMenu.drawIcon(game, mon, x, y, false, 0, animated)
    return
  end
  local image = self:iconImageFor(game, mon)
  if not image then return end
  local iw, ih = image:getDimensions()
  local frame = animated and 1 or 0
  local quad = love.graphics.newQuad(0, frame * G2_ICON,
    G2_ICON, G2_ICON, iw, ih)
  love.graphics.draw(image, quad, x, y)
end

return Engine
