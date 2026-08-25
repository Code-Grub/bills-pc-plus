-- Box view demo: free paging, grab-and-place with gaps, stats panel.
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local Screens = require("src.ui.Screens")
  local Stats = require("src.pokemon.Stats")
  local DIR = os.getenv("SHOT_DIR") or "frames_box"
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
  game.stack:top().items[1].onSelect() -- WITHDRAW
  U.wait(5)
  local grid = game.stack:top()
  grid.cursor = 1; grid.counter = 0; U.wait(2)
  local seq = 1
  local function shot() U.shot(game, string.format("%s/frame_%03d.png", DIR, seq)); seq = seq + 1; U.wait(2) end
  shot() -- idle - shiny PIKACHU + type/DV panel + gaps (counter 0 = on)
  grid.counter = 16; shot() -- blink off (main.lua:518 cursorOn 16-frame half)
  grid.counter = 0; shot() -- blink on again (12.5 fps shows both phases)
  U.tap(game, "right"); U.wait(4); grid.counter = 0; shot()
  U.tap(game, "right"); U.wait(4); grid.counter = 0; shot()
  U.tap(game, "a"); U.wait(8); shot() -- cursor menu MOVE/WITHDRAW/...
  U.tap(game, "a"); U.wait(8); grid = game.stack:top(); grid.counter = 0; shot() -- MOVE picked, carrying (solid cursor)
  grid.counter = 16; shot() -- carrying holds solid even at 16 (main.lua:519)
  U.tap(game, "down"); U.wait(4); grid.counter = 0; shot() -- carry to empty cell 8 (free, same column)
  grid.counter = 16; shot() -- still solid while carrying
  U.tap(game, "a"); U.wait(5); grid.counter = 0; shot() -- drop to free cell, gaps preserved (BoxSession.lua:211 placed)
  grid.counter = 16; shot() -- now blinks off again (not carrying)
  grid.counter = 0; shot()
  grid.cursor = 5; U.wait(2); grid.counter = 0; shot()
  U.tap(game, "right"); U.wait(4); grid.counter = 0; shot() -- right edge -> page box 2 (empty)
  grid.counter = 16; shot()
  U.tap(game, "left"); U.wait(4); grid.counter = 0; shot() -- back to box 1
  U.log(string.format("box demo: %d frames -> %s", seq - 1, DIR))
end
