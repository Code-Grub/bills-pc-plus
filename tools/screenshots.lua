-- README screenshot driver for Bill's PC Plus.
--
-- Run from the engine checkout with the mod installed in mods/ (the
-- tools/screenshots.ps1 wrapper sets all of this up):
--
--   POKEPORT_DRIVER=<abs path to this file> SHOT_DIR=<out dir> \
--   POKEPORT_IDENTITY=bills-pc-plus-shots POKEPORT_TOUCH=0 love .
--
-- Deterministic by construction: the teleport skips the intro, the save is
-- seeded with known mons and a known gap layout, the screen is opened
-- straight through the registry, and both frames are captured with the
-- cursor lit (counter 0 is the on-phase of the blink).
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local Screens = require("src.ui.Screens")
  local Stats = require("src.pokemon.Stats")
  local DIR = os.getenv("SHOT_DIR") or "shots"

  -- A quiet, proven map spot; the box screen is opaque, so the map itself
  -- never shows.  What matters is everything seeded below it.
  U.teleport(game, "SS_ANNE_1F", 31, 9, "up")

  local function mon(species, level, extra)
    if not game.data.pokemon[species] then
      U.log("WARNING: unknown species key ", species, " -- the cell will draw blank")
    end
    local m = {
      species = species, level = level or 10, hp = 20,
      dvs = { attack = 8, defense = 8, speed = 8, special = 8 },
      statExp = {}, moves = {},
    }
    if extra then for k, v in pairs(extra) do m[k] = v end end
    Stats.ensure(game.data.pokemon[species], m)
    return m
  end

  local save = game.save
  -- Box view composition: ten mons and scattered gaps.  Cell 1 is a shiny,
  -- paralyzed Pikachu, so the stats strip shows the type line, the status
  -- code and the shiny mark together, with the front sprite beside them.
  save.boxes = { {
    mon("PIKACHU", 21, {
      dvs = { attack = 15, defense = 10, speed = 10, special = 10 },
      status = "PAR",
    }),
    mon("CHARMANDER", 9),
    mon("SQUIRTLE", 12),
    mon("BULBASAUR", 13),
    mon("MEOWTH", 15),
    mon("GEODUDE", 18),
    mon("MAGIKARP", 5),
    mon("LAPRAS", 20),
    mon("SNORLAX", 30),
    mon("GENGAR", 25),
  } }
  -- ten occupied cells across the four rows: a full top row, a split
  -- second, a loner in the third, one in the corner.  The gaps are the
  -- feature; the layout is what commit would record.
  save.bpp_layout = { [1] = { 1, 2, 3, 4, 5, 6, 7, 9, 13, 20 } }
  save.party = {
    mon("PIDGEY", 4), mon("RATTATA", 6), mon("SPEAROW", 8),
    mon("JIGGLYPUFF", 7), mon("ABRA", 6), mon("MACHOP", 11),
  }

  -- straight through the registry: BoxMenu resolves to the mod's screen
  Screens.push(game, "BoxMenu")
  U.wait(5)
  local menu = game.stack:top()
  menu.items[1].onSelect()
  U.wait(5)
  local grid = game.stack:top()
  grid.cursor = 1
  grid.counter = 0
  U.wait(2)
  U.shot(game, DIR .. "/screen_box.png")

  -- deposit view: back to the menu, second row
  game.stack:pop()
  U.wait(2)
  menu.items[2].onSelect()
  U.wait(5)
  local dep = game.stack:top()
  dep.partyCursor = 1
  dep.counter = 0
  U.wait(2)
  U.shot(game, DIR .. "/screen_deposit.png")

  U.log("screenshots written to ", DIR)
end
