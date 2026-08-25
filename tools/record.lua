-- GIF demo driver for Bill's PC Plus.
-- Captures a deterministic sequence as PNG frames; record.ps1 crops and
-- assembles them into a GIF.
--   POKEPORT_DRIVER=<abs path to this file> SHOT_DIR=<out dir> love .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local Screens = require("src.ui.Screens")
  local Stats = require("src.pokemon.Stats")
  local DIR = os.getenv("SHOT_DIR") or "frames"

  U.teleport(game, "SS_ANNE_1F", 31, 9, "up")

  local function mon(species, level, extra)
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
  save.boxes = { {
    mon("PIKACHU", 21, { dvs = { attack = 15, defense = 10, speed = 10, special = 10 }, status = "PAR" }),
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
  save.bpp_layout = { [1] = { 1, 2, 3, 4, 5, 6, 7, 9, 13, 20 } }
  save.party = {
    mon("PIDGEY", 4), mon("RATTATA", 6), mon("SPEAROW", 8),
    mon("JIGGLYPUFF", 7), mon("ABRA", 6),
  }
  save.currentBox = 1

  Screens.push(game, "BoxMenu")
  U.wait(5)
  local menu = game.stack:top()
  menu.items[1].onSelect() -- WITHDRAW
  U.wait(5)
  local grid = game.stack:top()
  grid.cursor = 1
  grid.counter = 0
  U.wait(2)

  local seq = 1
  local function shot()
    local path = string.format("%s/frame_%03d.png", DIR, seq)
    seq = seq + 1
    U.shot(game, path)
    U.wait(2)
  end

  -- 1: box view idle, shiny PIKACHU on panel
  shot()
  -- 2: move cursor right
  U.tap(game, "right"); U.wait(4); grid.counter = 0; shot()
  -- 3: move again
  U.tap(game, "right"); U.wait(4); grid.counter = 0; shot()
  -- 4: open cursor menu (A)
  U.tap(game, "a"); U.wait(8); shot()
  -- 5: pick MOVE (first item) - tap A to let Menu pop correctly, then show carrying
  U.tap(game, "a"); U.wait(8); grid.counter = 0; shot()
  -- refresh grid ref after menu pop (stack top is grid again)
  grid = game.stack:top()
  -- 6: walk while carrying to an empty cell (cell 8 is free)
  U.tap(game, "right"); U.wait(4); grid.counter = 0; shot()
  U.tap(game, "down"); U.wait(4); grid.counter = 0; shot()
  -- 7: drop (A) - places into free cell, others stay
  U.tap(game, "a"); U.wait(5); grid.counter = 0; shot()
  -- 8: page to next box (right off edge)
  grid.cursor = 5
  U.wait(2); grid.counter = 0; shot()
  U.tap(game, "right"); U.wait(4); grid.counter = 0; shot() -- pages to box 2 (empty)
  U.tap(game, "left"); U.wait(4); grid.counter = 0; shot() -- back to box 1

  -- 9: back to WITHDRAW/DEPOSIT menu
  game.stack:pop(); U.wait(5)
  menu = game.stack:top()
  menu.items[2].onSelect() -- DEPOSIT
  U.wait(5)
  local dep = game.stack:top()
  dep.partyCursor = 1; dep.counter = 0; U.wait(2); shot()
  -- 10: walk party row
  U.tap(game, "right"); U.wait(4); dep.counter = 0; shot()
  U.tap(game, "right"); U.wait(4); dep.counter = 0; shot()
  -- 11: page destination box (up/down) - header arrows visible
  U.tap(game, "down"); U.wait(4); dep.counter = 0; shot()
  U.tap(game, "up"); U.wait(4); dep.counter = 0; shot()
  -- 12: deposit (A) -> first free cell
  U.tap(game, "a"); U.wait(8); dep.counter = 0; shot()

  U.log(string.format("record: %d frames written to %s", seq - 1, DIR))
end
