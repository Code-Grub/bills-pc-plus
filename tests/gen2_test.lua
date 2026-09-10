-- Standalone: luajit mods/bills_pc_plus/tests/gen2_test.lua
--
-- Gen 2 (Gold/Silver/Crystal) load and seam behaviour.  Separate from
-- bills_pc_plus_test.lua because that file sits at LuaJIT's 200-local
-- ceiling and cannot take another top-level local.
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local T = require("tests.modkit")
local Data = require("tests.modkit.fixtures").fresh()

-- A gate skip is deliberately NOT an error, so #run.errors == 0 passes for a
-- mod that never ran a line.  Assert the state, not just the error count.
local run = T.sdk.loadMod("mods/bills_pc_plus", { data = Data, generation = 2 })
T.eq(#run.errors, 0,
  "loads with no boot errors on gen 2 (" .. tostring(run.errors[1]) .. ")")
T.eq(run.mod and run.mod.state, "loaded",
  "the mod runs on gen 2: " .. tostring(run.mod and run.mod.skipReason))

-- The seam is constructed with an explicit generation rather than sniffing
-- one: the screen id the factory was registered under is the signal, so
-- nothing here allow-lists a version.
local Engine = dofile("mods/bills_pc_plus/Engine.lua")

local gen1 = Engine.new(false)
T.eq(gen1.gen2, false, "a Gen 1 seam knows it is Gen 1")
T.eq(gen1:summaryScreenId(), "SummaryMenu", "and opens the Gen 1 summary")

local gen2 = Engine.new(true)
T.eq(gen2.gen2, true, "a Gen 2 seam knows it is Gen 2")
T.eq(gen2:summaryScreenId(), "Gen2SummaryMenu", "and opens Gold's summary")

-- ...and hands that screen the arguments its constructor actually takes.
-- Gen 1's SummaryMenu.new(game, mon) is positional; Gold's is
-- SummaryMenu.new(game, opts) and reads opts.mon, so the mon passed
-- positionally there landed nowhere and the screen fell back to the party --
-- showing the wrong Pokemon, with no onClose, so B could not leave it.
do
  local function capture(engine)
    local seen
    local ui = { push = function(g, id, arg) seen = { id = id, arg = arg } end }
    local game = { stack = { pop = function() end } }
    local mon = { species = "PIKACHU" }
    local save = { party = {} }
    engine:openSummary(ui, game, mon, save)
    return seen, mon, save
  end

  local g1, g1mon = capture(Engine.new(false))
  T.eq(g1 and g1.id, "SummaryMenu", "Gen 1 opens Red's summary")
  T.eq(g1 and g1.arg, g1mon,
    "with the mon passed positionally, the way src/ui/BoxMenu.lua does")

  local g2, g2mon, g2save = capture(Engine.new(true))
  T.eq(g2 and g2.id, "Gen2SummaryMenu", "Gen 2 opens Gold's")
  T.check(type(g2 and g2.arg) == "table" and g2.arg.mon ~= nil,
    "with an opts table, not the bare mon")
  T.eq(g2 and g2.arg and g2.arg.mon, g2mon,
    "carrying the mon the cursor was on under opts.mon")
  T.eq(g2 and g2.arg and g2.arg.save, g2save, "and the session's save")
  T.check(type(g2 and g2.arg and g2.arg.onClose) == "function",
    "and an onClose, the only thing SummaryMenu:close() calls")
end

-- The seam only reaches the Screen as newGrid's fourth argument -- newGrid is
-- defined outside the factory, so it cannot capture the upvalue.  A nil there
-- stays invisible until a stored mon's STATS row fires, so open the grid the
-- way a player does, through each registered id, and check what landed.
local Screens = require("src.ui.Screens")
Screens.invalidate()

local function gridFor(id)
  local g = {
    data = Data,
    save = { party = {}, boxes = nil, currentBox = 1 },
    stack = { push = function() end },
    input = { wasPressed = function() return false end,
              isDown = function() return false end },
  }
  local menu = Screens.get(g, id).new(g)
  local captured
  g.stack = { push = function(_, state) captured = state end,
              pop = function() end }
  for _, item in ipairs(menu.items) do
    if item.label == "WITHDRAW POKéMON" then item.onSelect() end
  end
  return captured
end

local boxGrid = gridFor("BoxMenu")
T.check(boxGrid and boxGrid.engine, "the grid behind BoxMenu carries a seam")
T.eq(boxGrid.engine:summaryScreenId(), "SummaryMenu",
  "the Gen 1 id's seam, so STATS there opens Red's summary")

local gen2Grid = gridFor("Gen2BoxMenu")
T.check(gen2Grid and gen2Grid.engine,
  "the grid behind Gen2BoxMenu carries a seam")
T.eq(gen2Grid.engine:summaryScreenId(), "Gen2SummaryMenu",
  "Gold's, so STATS there opens Gold's summary")

-- PrintMonTypes' .hide_type_2.  Gold's extracted pokemon.lua keeps BOTH type
-- bytes, exactly as the cart stores them, so a single-typed mon arrives as
-- { FIRE, FIRE } -- where Gen 1's extractor collapses the pair to one entry.
-- The strip printed t[1] .. "/" .. t[2] whenever t[2] existed, so every
-- mono-typed mon on a Gen 2 boot read "FIRE/FIRE".  The cart blanks the
-- second name when the two match (src/ui/gen2/SummaryMenu.lua:452), and so
-- does the strip now; Gen 1 has no t[2] at all, so nothing there moves.
do
  local Font = require("src.render.Font")

  local function typeLineFor(types)
    Data.pokemon.FIXMON_C = Data.pokemon.FIXMON_C or {}
    Data.pokemon.FIXMON_C.types = types
    local g = {
      data = Data,
      save = { party = {}, currentBox = 1, boxes = { {
        { species = "FIXMON_C", level = 12, hp = 20, dvs = {}, statExp = {},
          moves = {},
          stats = { hp = 20, attack = 12, defense = 12,
                    speed = 12, special = 12 } },
      } } },
      stack = { push = function() end, pop = function() end },
      input = { wasPressed = function() return false end,
                isDown = function() return false end },
    }
    local captured
    g.stack = { push = function(_, st) captured = st end,
                pop = function() end }
    local menu = Screens.get(g, "Gen2BoxMenu").new(g)
    for _, item in ipairs(menu.items) do
      if item.label == "WITHDRAW POKéMON" then item.onSelect() end
    end
    captured.counter = 0
    local seen = {}
    local real = Font.draw
    Font.draw = function(text, x, y)
      seen[#seen + 1] = tostring(text)
      return real(text, x, y)
    end
    local ok, err = pcall(captured.draw, captured)
    Font.draw = real
    if not ok then error(err, 0) end
    local line
    for _, t in ipairs(seen) do
      if t:find("^[A-Z]+/?[A-Z]*$") and t ~= "PARTY" and t ~= "DV"
        and t ~= "ATK" and t ~= "DEF" and t ~= "SPD" and t ~= "SPC" then
        line = t
      end
    end
    return line
  end

  T.eq(typeLineFor({ "GRASS", "GRASS" }), "GRASS",
    "a mon carrying its one type twice prints it once")
  T.eq(typeLineFor({ "GRASS", "POISON" }), "GRASS/POISON",
    "a genuinely dual-typed mon still prints both")
  T.eq(typeLineFor({ "GRASS" }), "GRASS",
    "and Gen 1's collapsed single entry is unchanged")
  Data.pokemon.FIXMON_C.types = nil
end

-- Gen 1 delegates to the engine's own drawIcon, unchanged, so Red/Blue/Yellow
-- keep today's output exactly -- including the OBP0 bake for built-in icon
-- classes, which only that path knows how to do.
do
  local PartyMenu = require("src.ui.PartyMenu")
  local realDraw = PartyMenu.drawIcon
  local seen
  PartyMenu.drawIcon = function(g, mon, x, y, selected, counter, forceAlt)
    seen = { g = g, mon = mon, x = x, y = y,
             selected = selected, counter = counter, forceAlt = forceAlt }
  end

  local fakeGame = { data = Data }
  local fakeMon = { species = "PIKACHU" }
  Engine.new(false):drawIcon(fakeGame, fakeMon, 24, 40, true)

  PartyMenu.drawIcon = realDraw

  T.check(seen, "the Gen 1 path still goes through PartyMenu.drawIcon")
  T.eq(seen and seen.x, 24, "at the x it was given")
  T.eq(seen and seen.y, 40, "and the y")
  T.eq(seen and seen.selected, false,
    "selected stays false: a stored mon has no meaningful HP-bar animation")
  T.eq(seen and seen.counter, 0, "counter stays 0 for the same reason")
  T.eq(seen and seen.forceAlt, true, "animation rides forceAlt instead")
end

-- Gen 2 resolves its own icon from data.gen2Icons -- per-species sheets,
-- not Gen 1's nine shared classes -- and Gold namespaces that table apart
-- from data.icons precisely so the two cannot collide (src/core/Game2.lua
-- :1036-1037, "Gen 2-only tables the menus read... nothing collides with
-- the Gen 1 keys of the same idea").  A fixture holding one real
-- species->sheet mapping, placed under BOTH keys, pins that the seam reads
-- only the one Gold actually populates: reading data.icons instead would
-- pass just as easily as reading gen2Icons if this test only checked for
-- a truthy image, which is exactly how the wrong key reached review once
-- already.
do
  local sheet = {
    species = { CYNDAQUIL = "ICON_FOX" },
    icons = { ICON_FOX = { image = "x/fox.png" } },
  }
  local e = Engine.new(true)

  local resolved = e:iconImageFor({ data = { gen2Icons = sheet } },
    { species = "CYNDAQUIL" })
  T.check(resolved, "a known species under gen2Icons resolves to an image")
  T.eq(resolved and resolved.path, "x/fox.png", "specifically its own sheet")

  local wrongKey = e:iconImageFor({ data = { icons = sheet } },
    { species = "CYNDAQUIL" })
  T.eq(wrongKey, nil,
    "the same table under the Gen 1 key (icons, not gen2Icons) resolves to " ..
    "nothing -- a regression back to that key must fail loudly here")

  local unknown = e:iconImageFor({ data = { gen2Icons = sheet } },
    { species = "NOSUCHMON" })
  T.eq(unknown, nil, "an unknown species resolves to no image, and does not raise")
end

-- ReadMonMenuIcon (engine/gfx/mon_icons.asm): an EGG slot draws ICON_EGG --
-- the `cp EGG / jr z, .egg` arm -- before any species lookup runs, so a
-- stored egg must draw the egg sheet, never the icon of whatever it will
-- hatch into.  Mirrors src/ui/gen2/PartyMenu.lua:752-757.
do
  local sheet = {
    species = { CYNDAQUIL = "ICON_FOX" },
    icons = { ICON_FOX = { image = "x/fox.png" },
              ICON_EGG = { image = "x/egg.png" } },
  }
  local e = Engine.new(true)
  local game = { data = { gen2Icons = sheet } }

  local egg = e:iconImageFor(game, { species = "CYNDAQUIL", isEgg = true })
  T.check(egg, "an egg resolves to an image")
  T.eq(egg and egg.path, "x/egg.png",
    "specifically the egg sheet, not CYNDAQUIL's own icon")
end

-- Depositing nudges happiness on Gen 1 (PIKAHAPPY_DEPOSITED,
-- bills_pc.asm:247), routed through the Pikachu follower.  Gold has no
-- storage event in its happiness enum at all, so the Gen 2 arm is a
-- deliberate no-op -- and must not raise, which the old direct call did:
-- src.world.gen2.Follower has no modifyHappiness.
do
  local mon = { species = "PIKACHU", happiness = 70 }
  local ok = pcall(function()
    Engine.new(true):modifyHappiness({ party = {} }, "DEPOSITED", mon)
  end)
  T.check(ok, "a Gen 2 deposit does not raise when nudging happiness")
  T.eq(mon.happiness, 70,
    "and leaves happiness alone: GSC has no deposit event to honour")

  local ok1 = pcall(function()
    Engine.new(false):modifyHappiness({ party = {} }, "DEPOSITED",
      { species = "PIKACHU" })
  end)
  T.check(ok1,
    "and the Gen 1 arm survives a follower module that cannot answer: it "
    .. "pcalls, because a deposit that already moved the mon must not fail "
    .. "afterwards over a cosmetic stat")
end

-- The same defect end to end, against the real Gold module table rather
-- than a hand-written double: BoxSession:deposit called
-- PikachuFollower.modifyHappiness directly, and the loadMod above has
-- already pointed that require at src.world.gen2.Follower, which has no
-- such member.  The call read nil and raised -- after table.remove had
-- taken the mon out of the party, so every Gold deposit died mid-move,
-- with the mon in neither place.
do
  local BoxSession = dofile("mods/bills_pc_plus/BoxSession.lua")
  local gold = {
    data = Data,
    save = {
      party = { { species = "FIXMON_A", level = 5, hp = 10, happiness = 70,
                  dvs = {}, statExp = {}, moves = {} },
                { species = "FIXMON_B", level = 5, hp = 10,
                  dvs = {}, statExp = {}, moves = {} } },
      boxes = nil,
      currentBox = 1,
    },
  }
  local mon = gold.save.party[1]
  local session = BoxSession.new(gold, Engine.new(true))
  local okGold, err = pcall(function() return session:deposit(1) end)
  T.check(okGold, okGold and "a Gold deposit completes"
    or ("a Gold deposit raised: " .. tostring(err)))
  T.eq(okGold and session:count(1), 1, "and the mon reaches the box")
  T.eq(gold.save.party[1] and gold.save.party[1].species, "FIXMON_B",
    "leaving the party behind it")
  T.eq(mon.happiness, 70, "with its happiness untouched")
end

-- ------- Gen 2 shaped data
--
-- Every case above this point runs on Fixtures.fresh(), whose species carry
-- Gen 1's baseStats = { hp, attack, defense, speed, special }.  Passing
-- `generation = 2` to loadMod swaps module FACADES, not the dataset, so a
-- case built on those fixtures runs Gold's code over Red's numbers -- which
-- is exactly how the WITHDRAW crash below reached review through a green
-- suite.
--
-- Gold's extracted data splits Special in two and keeps no `special` at all:
-- src/battle/gen2/Mon.lua:163-195 reads baseStats.specialAttack and
-- baseStats.specialDefense, and the stat block it returns has the same six
-- keys.  These fixtures are that shape, and carry no `special` anywhere on
-- purpose -- a "fix" that quietly writes a Gen-1-shaped block back over a
-- Gold mon has to fail here rather than pass quietly.
local function goldData()
  local function def(id, name, base)
    return { id = id, name = name, baseStats = base,
             growthRate = "MEDIUM_SLOW", types = { "NORMAL", "NORMAL" },
             genderRatio = 127, catchRate = 45, baseExp = 64,
             level1Moves = {} }
  end
  return {
    pokemon = {
      GOLDMON_A = def("GOLDMON_A", "GOLDMON A",
        { hp = 60, attack = 62, defense = 63, speed = 60,
          specialAttack = 80, specialDefense = 80 }),
      GOLDMON_B = def("GOLDMON_B", "GOLDMON B",
        { hp = 45, attack = 49, defense = 49, speed = 45,
          specialAttack = 65, specialDefense = 65 }),
    },
  }
end

-- A party/box mon in the same shape: five stat-exp words (the Gen 2 party
-- struct kept Gen 1's, ending at SpcExp) but a six-key stat block.
local function goldMon(species, over)
  local mon = {
    species = species, level = 10, hp = 24, maxHp = 24,
    dvs = { attack = 9, defense = 8, speed = 8, special = 8 },
    statExp = { hp = 0, attack = 0, defense = 0, speed = 0, special = 0 },
    moves = {},
    stats = { hp = 24, attack = 17, defense = 17, speed = 17,
              specialAttack = 20, specialDefense = 20 },
  }
  for k, v in pairs(over or {}) do mon[k] = v end
  return mon
end

-- WITHDRAW raised on every Gold mon.  BoxSession called
-- src.pokemon.Stats.ensure directly, and src.pokemon.Stats is NOT in
-- Gen2Compat's coverage table -- only src.pokemon.Boxes is -- so on Gold the
-- Gen 1 module ran over Gen 2 data: Stats.ORDER wants `special`, so
-- statsComplete was always false and it always recalculated, and Stats.calc
-- then read speciesDef.baseStats.special (nil on Gold) into arithmetic.  It
-- raised out of the WITHDRAW row's onSelect, which src/ui/Menu.lua:101 calls
-- unwrapped, so it reached the love loop as a hard error.
do
  local BoxSession = dofile("mods/bills_pc_plus/BoxSession.lua")
  local data = goldData()
  local game = {
    data = data,
    save = { party = {}, currentBox = 1,
             boxes = { { goldMon("GOLDMON_A") } } },
  }
  local session = BoxSession.new(game, Engine.new(true))
  local okW, errW = pcall(function() return session:withdraw(1, 1) end)
  T.check(okW, okW and "a Gold withdraw completes"
    or ("a Gold withdraw raised: " .. tostring(errW)))
  local mon = game.save.party[1]
  T.check(mon, "and the mon reaches the party")
  T.check(mon and mon.stats and mon.stats.specialAttack,
    "carrying Gold's own stat block: SpA is there")
  T.check(mon and mon.stats and mon.stats.specialDefense, "and SpD")
  T.eq(mon and mon.stats and mon.stats.special, nil,
    "and no Gen 1 `special` was written back over it")
  T.eq(session:count(1), 0, "and the cell it came out of is empty")
end

-- Why the call is there at all: box_struct stops before MON_STATS, so a mon
-- decoded out of an imported .sav has no stat block and every later HP-bar
-- draw nil-indexes it.  That has to still work on Gold.
do
  local BoxSession = dofile("mods/bills_pc_plus/BoxSession.lua")
  local data = goldData()
  local game = {
    data = data,
    save = { party = {}, currentBox = 1,
             boxes = { { goldMon("GOLDMON_B",
               { stats = nil, maxHp = nil, hp = nil }) } } },
  }
  local session = BoxSession.new(game, Engine.new(true))
  local okW, errW = pcall(function() return session:withdraw(1, 1) end)
  T.check(okW, okW and "a stat-less Gold mon withdraws"
    or ("a stat-less Gold mon raised: " .. tostring(errW)))
  local mon = game.save.party[1]
  T.check(mon and mon.stats and type(mon.stats.hp) == "number",
    "and gets a stat block on the way into the party")
  T.check(mon and mon.stats and type(mon.stats.specialAttack) == "number",
    "with SpA calculated from Gold's split base stats")
  T.eq(mon and mon.stats and mon.stats.special, nil, "and still no `special`")
end

-- The Gen 1 arm of the seam is the pre-existing call, verbatim: Stats.ensure
-- with the SPECIES DEF first (add_mon.asm _MoveMon's CalcStats tail).
do
  local Stats = require("src.pokemon.Stats")
  local real = Stats.ensure
  local seen
  Stats.ensure = function(a, b) seen = { def = a, mon = b } end
  local mon = { species = "FIXMON_A" }
  Engine.new(false):ensureStats(Data, mon)
  Stats.ensure = real
  T.check(seen, "the Gen 1 seam delegates to src.pokemon.Stats.ensure")
  T.eq(seen and seen.def, Data.pokemon.FIXMON_A, "with the species def first")
  T.eq(seen and seen.mon, mon, "and the mon second")
end

-- Gold refreshes a stat block through src/battle/gen2/Mon.refreshStats(mon,
-- data) -- the whole data table, not a def -- which is what
-- src/ui/gen2/SummaryMenu.lua:292 calls when the summary opens on a boxed
-- mon, and what src/ui/gen2/PartyMenu.lua:142 calls per party row.
do
  local Mon = require("src.battle.gen2.Mon")
  local real = Mon.refreshStats
  local seen
  Mon.refreshStats = function(a, b) seen = { mon = a, data = b } end
  local data = goldData()
  local mon = { species = "GOLDMON_A" }
  Engine.new(true):ensureStats(data, mon)
  Mon.refreshStats = real
  T.check(seen, "the Gen 2 seam delegates to src.battle.gen2.Mon.refreshStats")
  T.eq(seen and seen.mon, mon, "with the mon first")
  T.eq(seen and seen.data, data,
    "and the whole data table second, the way Gold's own callers pass it")
end

-- ------- deposit rules Gold enforces and Red has none of
--
-- BoxSession writes the sparse box directly instead of calling
-- Boxes.deposit -- deliberately, because that helper overflows into the next
-- box with room and the player paged to THIS box.  On Gen 1 that skips
-- nothing: src/pokemon/Boxes.lua has no rules.  On Gold src.pokemon.Boxes
-- facades src/core/gen2/Boxes.lua, which has some, and going around the
-- helper went around them too.
do
  local BoxSession = dofile("mods/bills_pc_plus/BoxSession.lua")
  local Mail = require("src.core.gen2.Mail")

  local function goldGame()
    return {
      data = goldData(),
      save = {
        party = { goldMon("GOLDMON_A"), goldMon("GOLDMON_B"),
                  goldMon("GOLDMON_A") },
        boxes = nil, currentBox = 1,
      },
    }
  end

  -- sPartyMail is six structs keyed by PARTY SLOT, so every letter behind a
  -- departing mon moves up one -- RemoveMonFromPartyOrBox's "Mail time!"
  -- tail, which Boxes.deposit calls immediately after its own table.remove.
  -- BoxSession's bare table.remove had no counterpart, so slot 2's letter
  -- stayed on slot 2 and landed on the mon that had been slot 3.
  do
    local game = goldGame()
    Mail.state(game.save).party[2] = { author = "MOM", message = "hi" }
    Mail.state(game.save).party[3] = { author = "BILL", message = "bye" }
    local session = BoxSession.new(game, Engine.new(true))
    T.eq(session:deposit(1, 1), true, "depositing party slot 1 succeeds")
    local letters = Mail.state(game.save).party
    T.eq(letters[1] and letters[1].author, "MOM",
      "the letter behind the deposited mon moved up with its mon")
    T.eq(letters[2] and letters[2].author, "BILL", "and so did the next one")
    T.eq(letters[3], nil, "leaving the tail slot empty")
    T.eq(game.save.party[1] and game.save.party[1].species, "GOLDMON_B",
      "and MOM's letter is still on the mon it belongs to")
  end

  -- BillsPC_CheckMon's .HasMail arm: a boxed mon has no sPartyMail slot, so
  -- the deposit is refused with PCString_RemoveMail rather than stranding
  -- the letter.  Checked last, after the box-full and last-mon refusals,
  -- which is where the cart checks it.
  do
    local game = goldGame()
    -- ItemIsMail is a linear search of MailItems and is the only definition
    -- of "this is mail" on the cart, so the fixture holds a real one.
    game.save.party[1].item = "FLOWER_MAIL"
    local session = BoxSession.new(game, Engine.new(true))
    local ok, reason = session:deposit(1, 1)
    T.eq(ok, false, "a mon holding MAIL is refused")
    T.eq(reason, "has_mail", "with the reason the screen turns into a message")
    T.eq(#game.save.party, 3, "and nothing left the party")
    T.eq(session:count(1), 0, "and nothing reached the box")
    T.eq(session.dirty, false, "and the refusal did not dirty the session")
  end

  -- Gold's box_struct has neither MON_HP nor MON_STATUS (macros/ram.asm
  -- :7-26), so SendGetMonIntoFromBox restores PP and CalcTempmonStats
  -- refills from MAXHP on the way in.  Gen 1's box_struct DOES hold current
  -- HP, so this must stay a no-op there.
  do
    local game = goldGame()
    local mon = game.save.party[1]
    mon.hp, mon.maxHp, mon.status = 3, 24, "PSN"
    mon.moves = { { id = "FIX_TACKLE", pp = 1, maxPp = 35 } }
    local session = BoxSession.new(game, Engine.new(true))
    T.eq(session:deposit(1, 1), true, "the deposit succeeds")
    T.eq(mon.hp, 24, "a mon entering a Gold box is refilled from MAXHP")
    T.eq(mon.status, nil, "its status is cleared")
    T.eq(mon.moves[1].pp, 35, "and its PP restored")
  end

  -- Gen 1 keeps exactly the behaviour it had: no mail rule, no heal.
  do
    local g1 = {
      data = Data,
      save = {
        party = { { species = "FIXMON_A", level = 5, hp = 3, maxHp = 20,
                    status = "PSN", dvs = {}, statExp = {},
                    moves = { { id = "FIX_TACKLE", pp = 1, maxPp = 35 } } },
                  { species = "FIXMON_B", level = 5, hp = 10, dvs = {},
                    statExp = {}, moves = {} } },
        boxes = nil, currentBox = 1,
      },
    }
    local mon = g1.save.party[1]
    mon.item = "FLOWER_MAIL"
    local session = BoxSession.new(g1, Engine.new(false))
    T.eq(session:deposit(1, 1), true,
      "Gen 1 deposits a mon holding what Gold would call mail: Red has none")
    T.eq(mon.hp, 3, "and does not refill it -- Gen 1's box_struct holds HP")
    T.eq(mon.status, "PSN", "nor clear its status")
    T.eq(mon.moves[1].pp, 1, "nor restore its PP")
  end

  -- The seam arms themselves, so a regression names which one moved.
  do
    local e1, e2 = Engine.new(false), Engine.new(true)
    local save = { party = { { species = "GOLDMON_A",
                               item = "FLOWER_MAIL" } } }
    T.eq(e1:canDeposit(save, 1), true, "the Gen 1 arm allows every deposit")
    local ok, reason = e2:canDeposit(save, 1)
    T.eq(ok, false, "the Gen 2 arm refuses a mail holder")
    T.eq(reason, "has_mail", "naming the reason")
    T.eq(e2:canDeposit({ party = { { species = "GOLDMON_A" } } }, 1), true,
      "and allows one without mail")

    local g1save = { mail = { party = { [1] = { author = "MOM" } }, box = {} } }
    e1:leaveParty(g1save, 1)
    T.eq(g1save.mail.party[1] and g1save.mail.party[1].author, "MOM",
      "the Gen 1 arm touches no mail: Red has none to shift")
    local g2save = { mail = { party = { [2] = { author = "MOM" } }, box = {} } }
    e2:leaveParty(g2save, 1)
    T.eq(g2save.mail.party[1] and g2save.mail.party[1].author, "MOM",
      "the Gen 2 arm shifts every letter behind the slot up one")

    local kept = { hp = 3, maxHp = 20, status = "PSN", moves = {} }
    e1:enterBox(kept)
    T.eq(kept.hp, 3, "the Gen 1 arm leaves a mon entering a box alone")
    T.eq(kept.status, "PSN", "status included")
  end
end

-- ------- clip/unclip map the scissor rect through the LIVE transform
--
-- This is the branch's riskiest change and it had no coverage at all.
-- love.graphics.setScissor takes WINDOW pixels and ignores the transform, so
-- the raw rect this replaced clipped a 16x16 patch of the top-left of the
-- window while the cell it meant to clip was somewhere else entirely --
-- which is why the whole Gen 2 grid drew nothing.
--
-- tests/love_stub.lua has setScissor = noop, getScissor returning nil, and
-- neither transformPoint nor intersectScissor, so under the shared stub both
-- branches take the identity fallback: reverting clip to a raw setScissor
-- would leave the suite green and re-break Gen 2 exactly as before.  The
-- stub is shared with the Gen 1 suites and is not the place to fix that, so
-- this swaps love.graphics for a local recorder around a real draw -- the
-- same monkeypatch-around-a-captured-draw shape the type-line case uses.
--
-- The assertion is coordinate-free on purpose: the same screen is drawn
-- twice, once with no transformPoint (the identity fallback) and once with a
-- translate+scale, and every rect from the second run has to be the first
-- run's rect put through that same transform.  A raw setScissor would
-- produce two identical runs and fail here.
do
  local realG = love.graphics
  local game = {
    data = Data,
    save = { party = {}, currentBox = 1, boxes = { {
      { species = "FIXMON_A", level = 12, hp = 20, dvs = {}, statExp = {},
        moves = {},
        stats = { hp = 20, attack = 12, defense = 12,
                  speed = 12, special = 12 } },
    } } },
    input = { wasPressed = function() return false end,
              isDown = function() return false end },
  }
  local screen
  game.stack = { push = function(_, st) screen = st end, pop = function() end }
  local menu = Screens.get(game, "Gen2BoxMenu").new(game)
  for _, item in ipairs(menu.items) do
    if item.label == "WITHDRAW POKéMON" then item.onSelect() end
  end
  screen.counter = 0

  local function recordRects(transformPoint, withIntersect)
    local rects, cleared = {}, 0
    local shim = setmetatable({
      getScissor = function() return nil end,
      setScissor = function(x, y, w, h)
        if x == nil then cleared = cleared + 1 return end
        rects[#rects + 1] = { x, y, w, h, via = "set" }
      end,
    }, { __index = realG })
    shim.transformPoint = transformPoint
    if withIntersect then
      shim.intersectScissor = function(x, y, w, h)
        rects[#rects + 1] = { x, y, w, h, via = "intersect" }
      end
    end
    love.graphics = shim
    local ok, err = pcall(screen.draw, screen)
    love.graphics = realG
    if not ok then error(err, 0) end
    return rects, cleared
  end

  local SCALE, TX, TY = 3, 40, 24
  local function scaled(x, y) return x * SCALE + TX, y * SCALE + TY end

  local raw, cleared = recordRects(nil, true)
  local mapped = recordRects(scaled, true)

  T.check(#raw > 0, "the box screen clips at least one rect while it draws")
  T.eq(#mapped, #raw, "and the same number of them under a live transform")
  T.check(cleared > 0,
    "unclip restores the rect that was there before, once per clip")

  local straight = true
  for _, r in ipairs(raw) do
    if r.via ~= "intersect" then straight = false end
  end
  T.check(straight,
    "through intersectScissor, so a clip the engine set around us still holds")

  local miss
  for i = 1, #raw do
    local r, m = raw[i], mapped[i]
    local ex, ey = scaled(r[1], r[2])
    if not (m[1] == ex and m[2] == ey
            and m[3] == r[3] * SCALE and m[4] == r[4] * SCALE) then
      miss = miss or string.format(
        "rect %d: %d,%d %dx%d became %d,%d %dx%d, wanted %d,%d %dx%d",
        i, r[1], r[2], r[3], r[4], m[1], m[2], m[3], m[4],
        ex, ey, r[3] * SCALE, r[4] * SCALE)
    end
  end
  T.check(miss == nil, miss and ("a rect missed the transform -- " .. miss)
    or "every rect is translated and scaled by the live transform")

  -- The other half of the same claim: under an identity transform the rect
  -- comes back exactly as it went in, which is what keeps the Gen 1 picture
  -- byte-identical while this runs on both generations.
  local ident = recordRects(function(x, y) return x, y end, true)
  local unchanged = #ident == #raw
  for i = 1, math.min(#ident, #raw) do
    local a, b = raw[i], ident[i]
    if not (a[1] == b[1] and a[2] == b[2]
            and a[3] == b[3] and a[4] == b[4]) then
      unchanged = false
    end
  end
  T.check(unchanged, "an identity transform hands every rect back unchanged")

  -- A runtime without intersectScissor still gets a MAPPED rect, just set
  -- rather than intersected.
  local viaSet = recordRects(scaled, false)
  local wantX, wantY = scaled(raw[1][1], raw[1][2])
  T.eq(#viaSet, #raw, "the setScissor fallback clips the same rects")
  T.eq(viaSet[1] and viaSet[1].via, "set", "through setScissor")
  T.eq(viaSet[1] and viaSet[1][1], wantX,
    "and mapped through the transform just the same")
  T.eq(viaSet[1] and viaSet[1][2], wantY, "on both axes")
end

-- ------- Gen 2 art is coloured by the palette it is DRAWN THROUGH
--
-- The bug this pins reached the repo owner through a green suite: all 91
-- checks passed while the whole screen rendered black and white on Crystal.
-- No unit test can see colour, so this asserts the MECHANISM instead --
-- that the Gen 2 draws are wrapped in a bound palette and the Gen 1 draws
-- are not, and that the wrapper is scoped to the image blits alone.
--
-- love_stub has no newShader, so GbcPalette.available() is false under it
-- and the production guard would take its fallback arm on every path,
-- observable and unobservable alike.  So GbcPalette itself is swapped for a
-- recorder around a real screen draw -- the same monkeypatch-around-a-
-- captured-draw shape the clip-rect cases above use.
do
  local GbcPalette = require("src.render.GbcPalette")

  -- data/pokemon/palettes.asm ships only the middle two colours of a pic;
  -- Palettes.monColors is what brackets them with white and black.
  local PALS = {
    partyMenu = {
      { { 255, 255, 255 }, { 255, 173, 82 }, { 173, 82, 0 }, { 0, 0, 0 } },
      { { 255, 255, 255 }, { 82, 173, 255 }, { 0, 82, 173 }, { 0, 0, 0 } },
    },
    pokemon = {
      FIXMON_A = { normal = { { 200, 100, 50 }, { 100, 50, 25 } },
                   shiny = { { 50, 200, 100 }, { 25, 100, 50 } } },
    },
  }
  local ICONS = {
    species = { FIXMON_A = "ICON_FOX" },
    icons = { ICON_FOX = { image = "x/fox.png" } },
  }

  -- ---- the two lookups, on both arms of the seam
  local seam1, seam2 = Engine.new(false), Engine.new(true)
  local palGame = { data = { gen2Palettes = PALS } }

  T.eq(seam1:iconColors(palGame), nil,
    "a Gen 1 seam names no icon palette, even over data that has one: " ..
    "Red's colour is an SGB zone applied after the frame, not at the draw")
  T.eq(seam2:iconColors(palGame), PALS.partyMenu[1],
    "the Gen 2 seam names PartyMenuOBPals' first entry, which is what " ..
    "InitPartyMenuOBPals puts in OBJ 0 for every icon in the list")
  T.eq(seam2:iconColors({ data = {} }), nil,
    "and nothing at all on a boot whose palettes never loaded")

  T.eq(seam1:monColors(palGame, { species = "FIXMON_A" }), nil,
    "a Gen 1 seam names no pic palette either")
  local mc = seam2:monColors(palGame, { species = "FIXMON_A" })
  T.eq(mc and #mc, 4, "the Gen 2 seam names a four-entry pic palette")
  T.eq(mc and mc[1][1], 255, "white brackets the pair the cart ships")
  T.eq(mc and mc[2][1], 200, "then the species' own two colours")
  T.eq(mc and mc[3][1], 100, "in order")
  T.eq(mc and mc[4][1], 0, "and black closes it")
  local shinyColors = seam2:monColors(palGame,
    { species = "FIXMON_A", shiny = true })
  T.eq(shinyColors and shinyColors[2][1], 50,
    "a shiny takes its own row, the way GetPlayerOrMonPalettePointer reads " ..
    "wTempMonDVs for the box pic")
  T.eq(seam2:monColors(palGame, {}), nil,
    "a mon with no species has no palette, and asking does not raise")
  T.eq(seam2:monColors({ data = {} }, { species = "FIXMON_A" }), nil,
    "nor does a boot with no palettes at all")

  -- ---- withColors: a nil palette is the Gen 1 case and must cost nothing
  local ran = false
  seam1:withColors(nil, function() ran = true end)
  T.check(ran, "a nil palette still runs the draw, unwrapped")
  T.eq(love.graphics.getShader(), nil, "and binds no shader to run it under")
  ran = false
  seam2:withColors(PALS.partyMenu[1], function() ran = true end)
  T.check(ran,
    "and a runtime that refused the shader draws grey art rather than none")

  -- ---- the same screen, drawn through both seams
  --
  -- Under a generation=2 load Gen2Compat facades src.ui.PartyMenu onto
  -- Gold's module, which carries no drawIcon STATIC -- the warning the
  -- loader prints -- so the Gen 1 arm's delegate is missing here, and only
  -- here: a real Red boot has no facade and calls the real one.  Standing
  -- one in costs the comparison nothing, because what is compared is
  -- whether a palette was BOUND, which happens above the delegate.
  -- Counting its calls is what keeps the Gen 1 run from passing by drawing
  -- no icons at all.
  local Delegate = require("src.ui.PartyMenu")
  local realDelegate = Delegate.drawIcon
  local realG = love.graphics
  local realAvailable, realWith = GbcPalette.available, GbcPalette.with
  local bound, depth, fillsInside, fills, delegated

  local function drawWith(screen)
    bound, depth, fillsInside, fills, delegated = {}, 0, 0, 0, 0
    Delegate.drawIcon = function() delegated = delegated + 1 end
    GbcPalette.available = function() return true end
    GbcPalette.with = function(colors, body)
      bound[#bound + 1] = colors
      depth = depth + 1
      local ok, err = pcall(body)
      depth = depth - 1
      if not ok then error(err, 0) end
      return true
    end
    local shim = setmetatable({
      rectangle = function()
        fills = fills + 1
        if depth > 0 then fillsInside = fillsInside + 1 end
      end,
    }, { __index = realG })
    love.graphics = shim
    local ok, err = pcall(screen.draw, screen)
    love.graphics = realG
    GbcPalette.available, GbcPalette.with = realAvailable, realWith
    Delegate.drawIcon = realDelegate
    if not ok then error(err, 0) end
  end

  Data.gen2Palettes, Data.gen2Icons = PALS, ICONS
  local function mon(level)
    return { species = "FIXMON_A", level = level, hp = 20, dvs = {},
             statExp = {}, moves = {},
             stats = { hp = 20, attack = 12, defense = 12, speed = 12,
                       special = 12 } }
  end
  local game = {
    data = Data,
    save = { party = { mon(9), mon(8) }, currentBox = 1,
             boxes = { { mon(12), mon(11), mon(10) } } },
    input = { wasPressed = function() return false end,
              isDown = function() return false end },
  }
  local function newScreen(id, row)
    local screen
    game.stack = { push = function(_, st) screen = st end,
                   pop = function() end }
    local menu = Screens.get(game, id).new(game)
    for _, item in ipairs(menu.items) do
      if item.label == row then item.onSelect() end
    end
    screen.counter = 0
    return screen
  end

  local function tally()
    local icons, pics, other = 0, 0, 0
    for _, colors in ipairs(bound) do
      if colors == PALS.partyMenu[1] then
        icons = icons + 1
      elseif colors and colors[2] and colors[2][1] == 200 then
        pics = pics + 1
      else
        other = other + 1
      end
    end
    return icons, pics, other
  end

  -- The mod registers BOTH ids on every boot (main.lua's two register
  -- calls), so the SAME screen can be built over the SAME data with each
  -- seam -- which makes the generation the only difference between these
  -- two runs.
  drawWith(newScreen("Gen2BoxMenu", "WITHDRAW POKéMON"))
  local g2Icons, g2Pics, g2Other = tally()
  local g2Fills, g2Inside = fills, fillsInside
  T.eq(g2Icons, 3,
    "the Gen 2 box view binds the icon palette once per icon it draws")
  T.eq(g2Pics, 1, "and the focused mon's own colours around the front pic")
  T.eq(g2Other, 0, "and nothing else")
  T.eq(delegated, 0,
    "drawing its own icons rather than through Red's delegate")

  drawWith(newScreen("BoxMenu", "WITHDRAW POKéMON"))
  T.eq(#bound, 0,
    "the Gen 1 box view binds no palette at all -- PaletteFX colours that " ..
    "frame afterwards, and a bound palette here would be a Red regression")
  T.eq(delegated, 3,
    "while drawing the same three icons, through the delegate that does " ..
    "Red's own OBP0 bake -- so the count above is not vacuous")
  T.check(fills > 0, "and the same fills")

  -- Deposit draws the party row through the same seam, and that row IS the
  -- party list PartyMenuOBPals was loaded for.
  drawWith(newScreen("Gen2BoxMenu", "DEPOSIT POKéMON"))
  local depIcons, depPics = tally()
  T.eq(depIcons, 5,
    "the Gen 2 deposit view binds the icon palette for the party row too")
  T.eq(depPics, 1, "with the focused party mon's colours on the pic")

  drawWith(newScreen("BoxMenu", "DEPOSIT POKéMON"))
  T.eq(#bound, 0, "and the Gen 1 deposit view binds none of it")
  T.eq(delegated, 5, "over the same five icons")

  -- The wrapper goes around the BLITS and nothing else.  The shader reads a
  -- shade index out of the red channel and love.graphics.rectangle samples a
  -- 1x1 white texture, so an empty-slot dot or a cursor stub drawn inside a
  -- bound palette would come back as that palette's colour 0 instead of
  -- black.
  T.check(g2Fills > 0, "the Gen 2 box view fills rectangles")
  T.eq(g2Inside, 0, "and not one of them lands inside a bound palette")

  Data.gen2Palettes, Data.gen2Icons = nil, nil
end

T.finish("bills_pc_plus gen2")
