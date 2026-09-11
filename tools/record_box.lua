-- Box view demo: free paging, grab-and-place with gaps, stats panel.
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
-- Two ways to capture, and the difference is the whole point of this file:
--
--   roll(n, cs)  captures n *consecutive* engine frames.  Use it for anything
--                that moves -- the box page slide above all, which is
--                TRANSITION_FRAMES = 8 frames of real animation in main.lua
--                and is invisible in a demo that waits it out.
--   shot(cs)     captures one frame and rests on it.  Use it for the posed
--                beats a reader needs time to read: the stats panel, the
--                cursor menu, the moment a mon lands.
--
-- Which beats get which is not a matter of taste: an earlier cut of this
-- driver rolled everything, and a pixel diff of the resulting GIF showed the
-- page slide as the ONLY thing in this screen that moves over more than one
-- frame.  A cursor step, opening the cursor menu, picking MOVE and dropping a
-- carried mon all complete inside the single frame that acts on the press, so
-- rolling them just writes four identical pngs.  Those are tapped and rested
-- on; only the two page changes roll.
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
  -- One posed frame, held. U.shot spins until the png reaches disk and says
  -- so, which is worth the two engine frames it costs on a beat we are
  -- resting on anyway.
  local function shot(hold)
    U.shot(game, name(hold))
  end
  -- Press a button and roll from the very frame the press is acted on.
  -- U.tap would spend that frame uncaptured, which for a page change means
  -- losing the head of the slide.
  local function tapRoll(btn, n, hold)
    table.insert(game.input.pressQueue, btn)
    roll(1, hold)
    game.input.state[btn] = false
    if n > 1 then roll(n - 1, hold) end
  end

  shot(55) -- idle - shiny PIKACHU + type/DV panel + gaps (counter 0 = on)
  grid.counter = 16; shot(38) -- blink off (main.lua:518 cursorOn 16-frame half)
  grid.counter = 0; shot(38) -- blink on again
  U.tap(game, "right"); grid.counter = 0; shot(34)
  U.tap(game, "right"); grid.counter = 0; shot(34)
  U.tap(game, "a"); U.wait(2); shot(55) -- cursor menu MOVE/WITHDRAW/...
  U.tap(game, "a"); U.wait(2); grid = game.stack:top(); grid.counter = 0; shot(45) -- MOVE picked, carrying (solid cursor)
  grid.counter = 16; shot(38) -- carrying holds solid even at 16 (main.lua:519)
  U.tap(game, "down"); grid.counter = 0; shot(40) -- carry to empty cell 8 (free, same column)
  grid.counter = 16; shot(35) -- still solid while carrying
  U.tap(game, "a"); U.wait(2); grid.counter = 0; shot(60) -- drop to free cell, gaps preserved (BoxSession.lua:211 placed)
  grid.counter = 16; shot(38) -- now blinks off again (not carrying)
  grid.cursor = 5; U.wait(1); grid.counter = 0; shot(42)
  -- Right edge -> page to box 2, and this is what the whole roll/shot split
  -- exists for.  The eight rolled frames are the slide itself: the frame that
  -- acts on the press, drawn at progress 0, then main.lua's seven
  -- intermediate offsets at 10px a frame.  The shot after it rests on the
  -- settled page.
  tapRoll("right", 8); grid.counter = 0; shot(55)
  tapRoll("left", 8); grid.counter = 0; shot(75) -- and slide box 1 back in
  U.log(string.format("box demo: %d frames -> %s", seq, DIR))
end
