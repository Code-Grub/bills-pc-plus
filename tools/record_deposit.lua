-- Deposit view demo: party row, destination paging, deposit to first free cell.
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local Screens = require("src.ui.Screens")
  local Stats = require("src.pokemon.Stats")
  local DIR = os.getenv("SHOT_DIR") or "frames_deposit"
  U.teleport(game, "SS_ANNE_1F", 31, 9, "up")
  local function mon(species, level, extra)
    local m = { species = species, level = level or 10, hp = 20, dvs = { attack = 8, defense = 8, speed = 8, special = 8 }, statExp = {}, moves = {} }
    if extra then for k, v in pairs(extra) do m[k] = v end end
    Stats.ensure(game.data.pokemon[species], m)
    return m
  end
  local save = game.save
  save.boxes = { {
    mon("PIKACHU", 21, { dvs = { attack = 15, defense = 10, speed = 10, special = 10 }, status = "PAR" }),
    mon("CHARMANDER", 9), mon("SQUIRTLE", 12), mon("BULBASAUR", 13), mon("MEOWTH", 15),
    mon("GEODUDE", 18), mon("MAGIKARP", 5), mon("LAPRAS", 20), mon("SNORLAX", 30), mon("GENGAR", 25),
  } }
  save.bpp_layout = { [1] = { 1, 2, 3, 4, 5, 6, 7, 9, 13, 20 } }
  save.party = { mon("PIDGEY", 4), mon("RATTATA", 6), mon("SPEAROW", 8), mon("JIGGLYPUFF", 7), mon("ABRA", 6) }
  save.currentBox = 1
  Screens.push(game, "BoxMenu")
  U.wait(5)
  game.stack:top().items[2].onSelect() -- DEPOSIT
  U.wait(5)
  local dep = game.stack:top()
  dep.partyCursor = 1; dep.counter = 0; U.wait(2)
  local seq = 1
  local function shot() U.shot(game, string.format("%s/frame_%03d.png", DIR, seq)); seq = seq + 1; U.wait(2) end
  shot() -- deposit view idle - party row + box C frame (on)
  dep.counter = 16; shot() -- blink off
  dep.counter = 0; shot() -- on
  U.tap(game, "right"); U.wait(4); dep.counter = 0; shot()
  dep.counter = 16; shot()
  U.tap(game, "right"); U.wait(4); dep.counter = 0; shot() -- walk party row
  U.tap(game, "left"); U.wait(4); dep.counter = 0; shot()
  dep.counter = 16; shot()
  U.tap(game, "down"); U.wait(4); dep.counter = 0; shot() -- page destination down (header arrows)
  U.tap(game, "down"); U.wait(4); dep.counter = 0; shot()
  dep.counter = 16; shot()
  U.tap(game, "up"); U.wait(4); dep.counter = 0; shot() -- back
  U.tap(game, "a"); U.wait(8); dep.counter = 0; shot() -- deposit to first free cell
  dep.counter = 16; shot()
  U.tap(game, "right"); U.wait(4); dep.counter = 0; shot() -- next party mon highlighted
  U.log(string.format("deposit demo: %d frames -> %s", seq - 1, DIR))
end
