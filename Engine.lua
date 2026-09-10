-- Per-generation seam.  Gold is a second engine beside Gen 1
-- (src/core/Game2.lua), and the mod API on top is deliberately one API, so
-- only a handful of places actually differ: the icon draw path, the screen
-- ids, happiness, and the stat block a mon leaving storage is given.  They
-- live here rather than as branches scattered through main.lua.
--
-- The generation is passed IN, never sniffed.  The screens registry serves
-- both generations and Gold's screens carry Gen2-prefixed ids so a mod
-- replacing Gold's party menu does not also replace Red's -- which means the
-- id this mod's factory was registered under already says which boot is
-- running.  A version allow-list would be the wrong answer twice over: it
-- excludes the mod from a future game by construction, and this already
-- knows.

local PartyMenu = require("src.ui.PartyMenu")
local Screens = require("src.ui.Screens")
local Sprites = require("src.pokemon.Sprites")
local Stats = require("src.pokemon.Stats")
local Assets = require("src.render.Assets")

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

-- Open that screen on a stored mon.
--
-- The id alone is not enough, because the two constructors take different
-- arguments.  Gen 1's is SummaryMenu.new(game, mon) -- the mon table itself,
-- positionally (src/ui/SummaryMenu.lua:35), which is what src/ui/BoxMenu.lua's
-- own STATS row hands it.  Gold's is SummaryMenu.new(game, opts) and reads
-- opts.mon (src/ui/gen2/SummaryMenu.lua:262, :279), so passing the mon
-- positionally there does NOT raise -- it silently misses every field and
-- falls through to `opts.party or save.party`, putting the FIRST PARTY MEMBER
-- on screen instead of the mon the cursor was on.  Two further fields ride the
-- same table: opts.save, and opts.onClose, which is the only thing
-- SummaryMenu:close() calls (:716-718) -- without it B does nothing and the
-- summary can never be left.  src/ui/gen2/BoxMenu.lua:358-363 passes exactly
-- these three, and this mirrors it.
--
-- The PUSH goes through `ui` (mod.ui) rather than src.ui.Screens: a mod
-- reaches the registry through its own facade, so a mod that replaced the
-- summary screen still wins.
--
-- The id comes from summaryScreenId rather than being written out again
-- here: two copies of the same pair drift, and a method nothing calls is a
-- method nothing tests.
--
-- The existence check mirrors src/ui/gen2/BoxMenu.lua:358 -- Screens.get
-- RAISES for an unregistered id, and a mod may have pulled the summary
-- screen out from under this one.  A STATS row that does nothing beats one
-- that drops the player into the love loop's error screen.  The LOOKUP has
-- to go through src.ui.Screens directly: mod.ui exposes push and no lookup,
-- which is the one question that facade cannot answer.
function Engine:openSummary(ui, game, mon, save)
  local id = self:summaryScreenId()
  if not pcall(Screens.get, game, id) then return end
  if not self.gen2 then
    ui.push(game, id, mon)
    return
  end
  ui.push(game, id, {
    mon = mon,
    save = save,
    onClose = function() game.stack:pop() end,
  })
end

-- The stats table the strip tabulates: which columns, what to call them,
-- and which stat keys fill them.  drawStats loops over what this hands
-- back, so main.lua never asks which generation it is drawing.
--
-- Red's stat block is { hp, attack, defense, speed, special }; Gold's is
-- { hp, attack, defense, speed, specialAttack, specialDefense } and has no
-- `special` at all (src/battle/gen2/Mon.lua:163-195).  So the strip printed
-- "--" under SPC on every Gen 2 boot -- honest, but a whole stat missing
-- from a screen whose entire job is showing stats.
--
-- HP is in neither list: it reads on the count line under the sprite, where
-- a "100/100" needs the panel's whole width.
--
-- LAYOUT IS PASSED IN rather than required.  A mod cannot require its own
-- files (main.lua's `sibling`), so this chunk has no way to reach Layout on
-- its own -- and it should not want one: the pixel geometry belongs in the
-- geometry module, and what belongs HERE is the per-generation knowledge of
-- which geometry the table needs. The caller holds both.
--
-- The two headers rows differ in LENGTH, not just spelling.  Gen 1's fields
-- are separated by a whole glyph of air (Layout.STATS_COLS is pitched 32
-- for a 24px field); Gen 2's are separated by half of one (pitch 28),
-- because a fifth column had to come out of that air.  Two-letter headers
-- right-aligned into a three-glyph field keep a leading blank glyph, which
-- on Gen 2 buys the header row 12px of separation where the value row has
-- 4 -- so the headers shrank for the columns to fit, and three letters
-- there would leave the labels no better separated than the digits.
--
-- `dvLabel` is the gutter word, or false where there is no gutter.  Whether
-- the strip HAS a label column is a per-generation fact now: Gen 2 spent
-- x=8..24 on the gaps between its columns, so its DV row goes unlabelled
-- (Layout.STATS_COLS_5 records what that costs and why it was accepted).
-- The seam carries the word rather than main.lua, so the drawing code never
-- asks which generation it is drawing.
--
-- `dvs` is a separate list because the DV row is NOT one cell per stat.
-- Gen 2 kept Gen 1's DV structure through the stat split: the cartridge
-- stores four DVs (Attack/Defense/Speed/Special) and derives HP's from
-- their parity, and Mon.lua:169 reads a single `dvs.special` and feeds it
-- to BOTH specialAttack and specialDefense -- which is why SpA and SpD
-- always rise together.  There is no SpA DV and no SpD DV to print.
-- (Mon.lua:170-172's `dvs.specialAttack or dvs.specialDefense` fallback is
-- a migration path for records written before the shared field existed, not
-- a per-stat DV, and reading it as one would put two different numbers
-- under two stats that cannot differ.)
--
-- A cell names either `col` -- right-aligned into that field, which is what
-- makes the row self-labeling, the 15 sitting under ATK -- or `centre`, an
-- x to centre on.  The shared Special DV takes the second: centred on the
-- seam between the two special fields it straddles the pair and claims
-- neither, where right-aligning it into one would read as "the other has no
-- DV".
function Engine:statTable(layout)
  if not self.gen2 then
    return {
      cols = layout.STATS_COLS,
      width = layout.STATS_COL_W,
      headers = { "ATK", "DEF", "SPD", "SPC" },
      keys = { "attack", "defense", "speed", "special" },
      dvLabel = "DV",
      dvs = {
        { key = "attack", col = 1 },
        { key = "defense", col = 2 },
        { key = "speed", col = 3 },
        { key = "special", col = 4 },
      },
    }
  end
  return {
    cols = layout.STATS_COLS_5,
    width = layout.STATS_COL_W,
    headers = { "AT", "DF", "SP", "SA", "SD" },
    keys = { "attack", "defense", "speed",
             "specialAttack", "specialDefense" },
    dvLabel = false,
    dvs = {
      { key = "attack", col = 1 },
      { key = "defense", col = 2 },
      { key = "speed", col = 3 },
      { key = "special", centre = layout.STATS_DV_SHARED_CX },
    },
  }
end

-- Give a mon a stat block on the way back into the party.
--
-- Gen 1 delegates to src.pokemon.Stats.ensure, the pre-existing call:
-- add_mon.asm _MoveMon runs CalcStats on the way back to the party, because
-- box_struct stops before MON_STATS and a mon decoded out of an imported
-- .sav has no stat block at all.
--
-- That module is the reason this needs a seam.  src.pokemon.Stats is NOT in
-- Gen2Compat's coverage table -- src.pokemon.Boxes is the only member under
-- that prefix that is -- so on Gold the direct call ran RED's stat maths over
-- Gold's data.  Gen 2 has no `special`: the stat block is
-- { hp, attack, defense, speed, specialAttack, specialDefense }
-- (src/battle/gen2/Mon.lua:163-195), so Stats.ORDER's `special` was never
-- complete, Stats.calc always recalculated, and it read
-- speciesDef.baseStats.special -- nil on Gold -- straight into arithmetic.
-- Every WITHDRAW raised, out through the row's onSelect, which
-- src/ui/Menu.lua:101 calls unwrapped.
--
-- Teaching Stats.ensure to tolerate a missing `special` would have been the
-- wrong repair twice over: it would write a five-key Gen 1 block over a Gold
-- mon, and Gold's own numbers are not Red's anyway.  So the Gen 2 arm calls
-- what Gold calls -- Mon.refreshStats(mon, data), the whole data table rather
-- than one species def (src/ui/gen2/SummaryMenu.lua:292, and PartyMenu.lua
-- :142 per party row).  It also syncs name/types/gender/shiny, which is
-- exactly what Gold wants a mon leaving storage to have.
--
-- Required inline rather than in the preamble: a Gen 1 boot must not drag
-- Gold's battle module in to reach a branch it never takes.
function Engine:ensureStats(data, mon)
  if not (data and mon) then return end
  if not self.gen2 then
    Stats.ensure(data.pokemon and data.pokemon[mon.species], mon)
    return
  end
  require("src.battle.gen2.Mon").refreshStats(mon, data)
end

-- Rules Gold puts on a deposit that Red has none of.
--
-- BoxSession writes the sparse box directly rather than calling
-- Boxes.deposit, and that is deliberate: the helper overflows into the next
-- box with room, which is right for a caught mon with nowhere to go and
-- wrong here, because the player paged to THIS box and pressed A.  On Gen 1
-- going around it costs nothing -- src/pokemon/Boxes.lua has no rules to
-- skip.  On Gold src.pokemon.Boxes facades src/core/gen2/Boxes.lua, which
-- has three, and going around the helper went around them too.
--
-- MAIL is the one that matters here.  sPartyMail is six structs keyed by
-- PARTY SLOT (src/core/gen2/Mail.lua:84-96), so a boxed mon has nowhere to
-- keep a letter, and BillsPC_CheckMon's .HasMail arm refuses the deposit
-- with PCString_RemoveMail rather than stranding it
-- (src/core/gen2/Boxes.lua:94-97).  Red has no mail at all, so the Gen 1 arm
-- has nothing to say and the caller's own rules stand alone.
function Engine:canDeposit(save, partySlot)
  if not self.gen2 then return true end
  local mon = save and save.party and save.party[partySlot]
  if require("src.core.gen2.Mail").monHoldsMail(mon) then
    return false, "has_mail"
  end
  return true
end

-- Called the instant a mon is taken OUT of the party, by anything that takes
-- one out.
--
-- The refusal above only protects the DEPARTING mon's letter.  This protects
-- everyone else's: sPartyMail is keyed by slot, so RemoveMonFromPartyOrBox's
-- "Mail time!" tail moves every struct after the departing slot up one
-- (src/core/gen2/Mail.lua:131-143), and Boxes.deposit calls it immediately
-- after its own table.remove.  Skipping it left every letter behind the
-- deposited mon attached to the wrong Pokemon -- silent save-state
-- corruption, invisible until the player opened the mailbox.
function Engine:leaveParty(save, partySlot)
  if not self.gen2 then return end
  require("src.core.gen2.Mail").removeSlot(save, partySlot)
end

-- Called on a mon the instant it lands in a box.
--
-- SendGetMonIntoFromBox's PC_DEPOSIT arm ends in
-- RestorePPOfDepositedPokemon (engine/pokemon/move_mon.asm:633-635), and
-- CalcTempmonStats refills a BOXMON from MAXHP, because Gold's box_struct
-- has neither MON_HP nor MON_STATUS to store the difference in
-- (macros/ram.asm:7-26).  Gen 1's box_struct DOES hold current HP -- which
-- is why BoxSession:withdraw only has to rebuild the stat block -- so
-- healing on the way in is right on Gold and would be a behaviour change on
-- Red.  Hence the seam rather than an unconditional call.
function Engine:enterBox(mon)
  if not self.gen2 then return end
  require("src.core.gen2.Boxes").enterBox(mon)
end

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

-- --------------------------------------------------------------- palettes
--
-- The two generations get their colour from systems with nothing in common,
-- and this is where they meet.
--
-- Gen 1 colours a frame AFTER it is drawn: the screen declares an SGB
-- palette zone (Screen:sgbPalettes -> PaletteFX.wholeNamed(data, "MEWMON"))
-- and PaletteFX substitutes a colour per shade over the finished picture, so
-- every draw on that path is the plain draw it has always been.  Nothing
-- here may touch it.
--
-- A CGB has no such pass, because on that hardware the colour IS the palette
-- the art is drawn through.  Every 2bpp sheet the importer writes is the
-- same four greys (src/render/GbcPalette.lua), so art blitted raw on Gen 2
-- stays grey -- which is exactly what this screen did on Crystal: a
-- black-and-white grid and a black-and-white front pic beside Gen 1's
-- coloured ones.
--
-- So the Gen 1 arm of both lookups below returns nil, withColors hands a nil
-- palette straight to the draw, and Gen 1's picture cannot move.

-- The palette a mon MENU ICON draws through.
--
-- Every party icon OAM entry is PAL_OW_RED (data/sprite_anims/oam.asm
-- :315-355) and InitPartyMenuOBPals loads PartyMenuOBPals into OBJ palette 0
-- for the whole list, species and EGG alike (engine/gfx/color.asm:593-598,
-- :1228-1229) -- one palette for every icon on screen, whatever it is an
-- icon OF.  src/ui/gen2/PartyMenu.lua:872-873 reads exactly this entry, and
-- so does the Pokedex scrollbar thumb (src/ui/gen2/PokedexMenu.lua:780-781),
-- which wears OBJ 0 for the same reason.
--
-- The cart's own Bill's PC draws no icons at all -- it is a text list -- so
-- the party menu is the only authority for how a menu icon is coloured, and
-- the deposit view's party row IS that list.
function Engine:iconColors(game)
  if not self.gen2 then return nil end
  local pals = game and game.data and game.data.gen2Palettes
  pals = pals and pals.partyMenu
  return pals and pals[1] or nil
end

-- The palette a mon's FRONT PIC draws through: its own species colours, the
-- shiny row included.
--
-- GetPlayerOrMonPalettePointer hands a pic the row of the species being
-- shown and takes the shiny pair off wTempMonDVs, and every Gold screen that
-- puts a front pic up as "this Pokemon" goes through it: the summary screen
-- (src/ui/gen2/SummaryMenu.lua:1061-1067), the Pokedex entry
-- (src/ui/gen2/PokedexMenu.lua:523) and Gold's own box submenu
-- (src/ui/gen2/BoxMenu.lua:742-748, engine/gfx/cgb_layouts.asm:284-300).
--
-- Gold's box LIST paints its pic in gfx/pc/orange.pal instead
-- (BoxMenu:panelColors' other arm), and that is deliberately not what this
-- returns.  The orange belongs to the vanilla list layout this mod replaced
-- outright; the panel here is an identity plate -- name, level, pic, stats,
-- shiny mark -- which is what the submenu shows, not the list.  It is also
-- what keeps Gen 2 reading like Gen 1, where the pic is coloured rather than
-- flat.
function Engine:monColors(game, mon)
  if not (self.gen2 and mon and mon.species) then return nil end
  local pals = game and game.data and game.data.gen2Palettes
  if not pals then return nil end
  return require("src.world.gen2.Palettes")
    .monColors(pals, mon.species, mon.shiny)
end

-- Run `body` with `colors` bound, or just run it.
--
-- A nil palette is the Gen 1 case and costs nothing: no require, no shader,
-- no saved state -- the draw is the bare draw it was before any of this
-- existed.  The GbcPalette.available() guard is Gold's own; every .with call
-- site under src/ui/gen2 carries it, so a boot whose driver refused the
-- shader still shows grey art rather than no art.
--
-- Scoped per DRAW rather than around a whole screen, on purpose.  The shader
-- recovers a shade index from the red channel, and love.graphics.rectangle
-- samples a 1x1 white texture -- so a black fill made inside a bound palette
-- comes back as that palette's colour 0.  The grid's empty-slot dots and the
-- cursor stubs are exactly such fills, and they sit between the icon draws.
function Engine:withColors(colors, body)
  if not colors then return body() end
  local GbcPalette = require("src.render.GbcPalette")
  if not GbcPalette.available() then return body() end
  return GbcPalette.with(colors, body)
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
--
-- The Gen 2 arm quads its own sheet and so has to bind its own palette: the
-- sheet is grey until one is, and the raw blit this replaced is why the grid
-- and the deposit view came out black and white on Crystal.  The wrapper
-- goes around the DRAW only -- see withColors on why it must not go wider.
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
  self:withColors(self:iconColors(game), function()
    love.graphics.draw(image, quad, x, y)
  end)
end

-- Nudge a mon's happiness for a storage event.
--
-- Gen 1 has no general happiness stat at all -- only the Yellow Pikachu
-- follower's -- so this is PikachuFollower.modifyHappiness there, mirroring
-- PIKAHAPPY_DEPOSITED (engine/pokemon/bills_pc.asm:247).  On Gold the old
-- direct call read nil and raised: src.world.gen2.Follower has no
-- modifyHappiness.
--
-- Gold does NOT get a happiness nudge here, and that is faithful rather than
-- a gap.  Gold has real, general happiness (src/core/gen2/Happiness.lua,
-- Happiness.change(mon, event)), but its event enum is transcribed row for
-- row from data/events/happiness_changes.asm and has no storage event at
-- all -- GAINLEVEL, USEDITEM, GYMBATTLE, FAINTED, GROOMING and so on, with
-- nothing for depositing.  Depositing a mon does not change happiness in
-- GSC; the Gen 1 behaviour this mirrors is a Yellow follower quirk with no
-- Gen 2 counterpart.  Inventing one would be this mod making up game rules.
--
-- The Gen 1 arm is pcall'd: a deposit that already moved the mon must not
-- fail afterwards because a cosmetic stat could not be nudged.
function Engine:modifyHappiness(save, event, mon)
  if self.gen2 then return end
  pcall(function()
    require("src.world.PikachuFollower").modifyHappiness(save, event, mon)
  end)
end

return Engine
