-- Deposit view demo: party row, destination paging, deposit to first free cell.
--
-- Frame naming -- tools/make_demos.ps1 parses this, so the two sides have to
-- agree:
--
--     frame_<seq>_h<cs>.png        e.g. frame_014_h006.png, frame_015_h055.png
--
-- <seq> is a zero-padded 3-digit sequence number and leads the name so the
-- script's plain name sort is the playback order.  <cs> is how long that one
-- frame is held in the GIF, in centiseconds (the unit GIF itself uses).  A
-- name with no _h falls back to the script's -Delay.
--
-- roll(n, cs) captures n consecutive engine frames -- use it for motion, in
-- particular the destination page slide, which is main.lua's
-- TRANSITION_FRAMES = 8 frames of real animation on the y axis.  shot(cs)
-- captures one frame and rests on it, for the beats a reader has to read.
--
-- Which beats get which was measured, not guessed: an earlier cut rolled
-- everything and a pixel diff of the GIF showed the page slide as the only
-- thing here that moves across more than one frame.  Walking the party row
-- and the deposit itself both finish inside the single frame that acts on
-- the press, so rolling them writes identical pngs.  They are tapped and
-- rested on; the three destination page changes roll.
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

  local MOTION = 6 -- 60ms: the pace movement rolls at
  local seq = 0
  local function name(hold)
    seq = seq + 1
    return string.format("%s/frame_%03d_h%03d.png", DIR, seq, hold)
  end
  -- Capture n consecutive engine frames.  Writing capturePath and yielding
  -- once is exactly one rendered frame (main.lua resumes the driver, steps
  -- the game, then draws and consumes the path), so nothing is skipped.
  local function roll(n, hold)
    for _ = 1, n do
      game.capturePath = name(hold or MOTION)
      coroutine.yield()
    end
  end
  local function shot(hold)
    U.shot(game, name(hold))
  end
  -- Press a button and roll from the very frame the press is acted on --
  -- U.tap would spend that frame uncaptured, losing the head of a slide.
  local function tapRoll(btn, n, hold)
    table.insert(game.input.pressQueue, btn)
    roll(1, hold)
    game.input.state[btn] = false
    if n > 1 then roll(n - 1, hold) end
  end

  shot(55) -- deposit view idle - party row + box C frame (on)
  dep.counter = 16; shot(38) -- blink off
  dep.counter = 0; shot(38) -- on
  U.tap(game, "right"); dep.counter = 0; shot(34)
  dep.counter = 16; shot(35)
  U.tap(game, "right"); dep.counter = 0; shot(34) -- walk party row
  U.tap(game, "left"); dep.counter = 0; shot(34)
  dep.counter = 16; shot(35)
  -- Page the destination down (header arrows).  The eight rolled frames are
  -- the slide itself: the frame that acts on the press, drawn at progress 0,
  -- then main.lua's seven intermediate offsets on the y axis at 8px a frame.
  -- This first one is the one with something to carry -- box 1's icons march
  -- up and off it.  The two after it page between empty boxes, so all that
  -- travels is the empty-slot dot grid; they roll anyway, because a reader
  -- who has just been shown that paging slides should not then see it cut.
  tapRoll("down", 8); dep.counter = 0; shot(48)
  tapRoll("down", 8); dep.counter = 0; shot(45)
  dep.counter = 16; shot(35)
  tapRoll("up", 8); dep.counter = 0; shot(45) -- back
  U.tap(game, "a"); U.wait(2); dep.counter = 0; shot(60) -- deposit to first free cell
  dep.counter = 16; shot(38)
  U.tap(game, "right"); dep.counter = 0; shot(75) -- next party mon highlighted
  U.log(string.format("deposit demo: %d frames -> %s", seq, DIR))
end
