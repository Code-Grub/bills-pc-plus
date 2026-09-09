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

return Engine
