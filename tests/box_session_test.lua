-- Standalone: luajit mods/bills_pc_plus/tests/box_session_test.lua
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local T = require("tests.modkit")
local Data = require("tests.modkit.fixtures").fresh()
local Boxes = require("src.pokemon.Boxes")

local BoxSession = dofile("mods/bills_pc_plus/BoxSession.lua")

-- a game double: the session only ever touches save, data and writeSave
local function newGame()
  local writes = 0
  local game = {
    data = Data,
    save = { party = {}, boxes = nil, currentBox = 1 },
    writeSave = function() writes = writes + 1 end,
  }
  return game, function() return writes end
end

local function monOf(species, level)
  return { species = species, level = level or 5, hp = 10,
           dvs = { attack = 8, defense = 8, speed = 8, special = 8 },
           statExp = {}, moves = {} }
end

-- the occupied cells of a sparse box as "cell:species" pairs, in cell
-- order -- the one-line shape of a layout
local function layoutOf(s, b)
  local names = {}
  for i = 1, Boxes.CAPACITY do
    if s.sparse[b][i] then
      names[#names + 1] = i .. ":" .. s.sparse[b][i].species
    end
  end
  return table.concat(names, ",")
end

-- ------- construction

local game = newGame()
BoxSession.new(game)
game.save.boxes[1] = { monOf("FIXMON_A"), monOf("FIXMON_B") }
local s = BoxSession.new(game)
T.eq(#game.save.boxes, 12, "construction ensures all twelve boxes")
T.eq(s.dirty, false, "a fresh session is clean")
T.eq(s.carry, nil, "a fresh session carries nothing")
T.eq(s.sparse[1][1].species, "FIXMON_A",
  "with no saved layout the packed mons fill from the first cell")
T.eq(s.sparse[1][2].species, "FIXMON_B", "and keep their packed order")
T.eq(s.sparse[1][3], nil, "cells past the mons are gaps")
T.eq(s.sparse[7][1], nil, "an untouched box is all gaps")
T.eq(s:count(1), 2, "count reads occupied cells, where # reads nils")

-- ------- a saved gap layout restores the exact cells

local gL = newGame()
BoxSession.new(gL)
gL.save.boxes[2] = { monOf("FIXMON_A"), monOf("FIXMON_B"), monOf("FIXMON_C") }
gL.save.bpp_layout = { [2] = { 1, 3, 10 } }
local sL = BoxSession.new(gL)
T.eq(layoutOf(sL, 2), "1:FIXMON_A,3:FIXMON_B,10:FIXMON_C",
  "the layout's remembered cells take the packed mons in order")

-- mons the layout does not know about -- caught or traded since the last
-- PC visit -- take the lowest free cells, ascending
gL.save.boxes[2] = { monOf("FIXMON_A"), monOf("FIXMON_B"), monOf("FIXMON_C"),
                     monOf("FIXMON_D") }
local sL2 = BoxSession.new(gL)
T.eq(layoutOf(sL2, 2), "1:FIXMON_A,2:FIXMON_D,3:FIXMON_B,10:FIXMON_C",
  "an unknown mon fills the first gap")

-- a box holding more mons than the layout remembers (a .sav imported over
-- a gapped layout) packs solid rather than losing mons
local full = {}
for i = 1, Boxes.CAPACITY do full[i] = monOf("FIXMON_B") end
gL.save.boxes[2] = full
local sL3 = BoxSession.new(gL)
T.eq(sL3:count(2), Boxes.CAPACITY,
  "more mons than remembered cells fills the box solid")
T.eq(sL3.sparse[2][1] ~= nil and sL3.sparse[2][20] ~= nil, true,
  "every cell from 1 to CAPACITY is occupied")

-- ------- paging wraps both ways and never dirties

game.save.currentBox = 12
s:pageBox(1)
T.eq(game.save.currentBox, 1, "paging forward off box 12 wraps to 1")
s:pageBox(-1)
T.eq(game.save.currentBox, 12, "paging back off box 1 wraps to 12")
T.eq(s.dirty, false, "paging never sets dirty")

-- ------- commit only writes when dirty

local g2, writes = newGame()
local s2 = BoxSession.new(g2)
T.eq(s2:commit(), false, "a clean session does not commit")
T.eq(writes(), 0, "a clean commit never calls writeSave")

s2.dirty = true
T.eq(s2:commit(), true, "a dirty session commits")
T.eq(writes(), 1, "commit calls writeSave exactly once")
T.eq(s2.dirty, false, "commit clears the dirty flag")
T.eq(s2:commit(), false, "committing twice writes once")
T.eq(writes(), 1, "the second commit is a no-op")

-- ------- commit packs the sparse layer and records the layout

local gC, writesC = newGame()
BoxSession.new(gC)
gC.save.boxes[1] = { monOf("FIXMON_A"), monOf("FIXMON_B"), monOf("FIXMON_C") }
local sC = BoxSession.new(gC)
sC:pickUp(1, 2)
T.eq(gC.save.boxes[1][2].species, "FIXMON_B",
  "the packed layer is untouched while the mon is in hand")
sC:drop(1, 6)
T.eq(sC:commit(), true, "commit packs")
T.eq(#gC.save.boxes[1], 3, "the packed box holds every mon, no holes")
T.eq(gC.save.boxes[1][1].species, "FIXMON_A", "cell 1 packs first")
T.eq(gC.save.boxes[1][2].species, "FIXMON_C", "cell 3 packs second")
T.eq(gC.save.boxes[1][3].species, "FIXMON_B", "cell 6 packs third")
T.eq(table.concat(gC.save.bpp_layout[1], ","), "1,3,6",
  "the layout records the occupied cells ascending")
T.eq(writesC(), 1, "the commit wrote once")

-- and a fresh session over the same save restores the exact gaps
local sC2 = BoxSession.new(gC)
T.eq(layoutOf(sC2, 1), "1:FIXMON_A,3:FIXMON_C,6:FIXMON_B",
  "the gaps survive a save round-trip")

-- ------- withdraw

-- Sound is required inline at call time, so swapping the loaded module
-- makes the cry observable without touching the audio stack.
local cries = {}
package.loaded["src.core.Sound"] = {
  playCry = function(_, species) cries[#cries + 1] = species end,
}

local g3 = newGame()
local s3 = BoxSession.new(g3)
s3.sparse[1][1] = monOf("FIXMON_A", 12)

local ok, reason = s3:withdraw(1, 2)
T.eq(ok, false, "withdrawing an empty cell is refused")
T.eq(reason, "no_mon", "the refusal names the reason")

cries = {}
T.eq(s3:withdraw(1, 1), true, "withdrawing a stored mon succeeds")
T.eq(#g3.save.party, 1, "the mon reached the party")
T.eq(s3.sparse[1][1], nil, "its cell is a gap")
T.eq(g3.save.boxes[1][1], nil, "the packed layer waits for commit")
T.eq(s3.dirty, true, "withdraw sets dirty")
T.eq(#cries, 1, "withdraw plays exactly one cry")
T.eq(cries[1], "FIXMON_A", "the cry is the withdrawn species")
T.eq(g3.save.party[1].stats ~= nil, true,
  "Stats.ensure gave the party copy a stat block")
T.eq(g3.stringBuffer, "FIXMON A", "stringBuffer carries the name for messages")

-- party full refuses
local g4 = newGame()
local s4 = BoxSession.new(g4)
for i = 1, 6 do g4.save.party[i] = monOf("FIXMON_B") end
s4.sparse[1][1] = monOf("FIXMON_A")
local ok4, reason4 = s4:withdraw(1, 1)
T.eq(ok4, false, "a full party refuses a withdrawal")
T.eq(reason4, "party_full", "the refusal names the reason")
T.eq(s4.sparse[1][1] ~= nil, true, "the refused mon stays in its cell")
T.eq(s4.dirty, false, "a refused withdrawal does not dirty the session")

-- ------- deposit

local happiness = {}
package.loaded["src.world.PikachuFollower"] = {
  modifyHappiness = function(_, event, _) happiness[#happiness + 1] = event end,
}

local g5 = newGame()
local s5 = BoxSession.new(g5)
g5.save.party = { monOf("FIXMON_A"), monOf("FIXMON_B") }
g5.save.currentBox = 3

cries, happiness = {}, {}
T.eq(s5:deposit(2, 3), true, "depositing into the chosen box succeeds")
T.eq(#g5.save.party, 1, "the mon left the party")
T.eq(s5:count(3), 1, "the mon landed in box 3, not the current box by accident")
T.eq(s5.sparse[3][1] ~= nil, true, "in the box's first free cell")
T.eq(s5.dirty, true, "deposit sets dirty")
T.eq(#cries, 1, "deposit plays exactly one cry")
T.eq(#happiness, 1, "deposit fires the Pikachu happiness event once")
T.eq(happiness[1], "DEPOSITED", "the event is DEPOSITED")
T.eq(g5.boxNumString, "3", "boxNumString carries the destination for messages")

-- a gap gets used before the tail
g5.save.boxes[3] = { monOf("FIXMON_C") }
local s5b = BoxSession.new(g5)
local c = s5b.sparse[3][1]
s5b.sparse[3][1] = nil
s5b.sparse[3][4] = c
T.eq(layoutOf(s5b, 3), "4:FIXMON_C", "the box now has a gap at cell 1")
table.insert(g5.save.party, monOf("FIXMON_B"))
T.eq(s5b:deposit(1, 3), true, "depositing into a gapped box succeeds")
T.eq(s5b.sparse[3][1] ~= nil, true, "the mon took cell 1, the first free cell")
T.eq(s5b:count(3), 2, "the gap at 4 is still there")

-- the last party mon cannot leave
local ok5, reason5 = s5:deposit(1, 3)
T.eq(ok5, false, "depositing the last party mon is refused")
T.eq(reason5, "last_mon", "the refusal names the reason")
T.eq(#g5.save.party, 1, "the last mon stays in the party")

-- a full destination refuses rather than overflowing into the next box
local g6 = newGame()
local s6 = BoxSession.new(g6)
g6.save.party = { monOf("FIXMON_A"), monOf("FIXMON_B") }
for i = 1, Boxes.CAPACITY do s6.sparse[2][i] = monOf("FIXMON_B") end
local ok6, reason6 = s6:deposit(2, 2)
T.eq(ok6, false, "a full destination box refuses the deposit")
T.eq(reason6, "box_full", "the refusal names the reason")
T.eq(s6:count(3), 0, "the mon did not overflow into the next box")
T.eq(#g6.save.party, 2, "the party is unchanged")

-- ------- carry

local g7 = newGame()
local s7 = BoxSession.new(g7)
s7.sparse[1][1] = monOf("FIXMON_A")
s7.sparse[1][2] = monOf("FIXMON_B")
s7.sparse[1][3] = monOf("FIXMON_C")

local ok7, reason7 = s7:drop(1, 1)
T.eq(ok7, false, "dropping with an empty hand is refused")
T.eq(reason7, "not_carrying", "the refusal names the reason")

T.eq(s7:pickUp(1, 1), true, "picking up a stored mon succeeds")
T.eq(s7.carry.mon.species, "FIXMON_A", "the hand holds the picked-up mon")
T.eq(s7.sparse[1][1], nil, "its cell opened into a visible gap")
T.eq(s7.sparse[1][2].species, "FIXMON_B",
  "and nothing shifted -- the neighbours stay put")

local ok8, reason8 = s7:pickUp(1, 1)
T.eq(ok8, false, "picking up twice is refused")
T.eq(reason8, "already_carrying", "the refusal names the reason")

-- dropping on an occupied slot swaps: the occupant comes up into the hand
local okS, reasonS = s7:drop(1, 2)
T.eq(okS, true, "dropping on an occupied slot succeeds")
T.eq(reasonS, "swapped", "the result reports a swap")
T.eq(s7.sparse[1][2].species, "FIXMON_A", "the held mon took the slot")
T.eq(s7.carry.mon.species, "FIXMON_B", "the occupant is now held")

-- dropping on a free cell places and empties the hand -- any free cell,
-- gaps included, with nothing reordering.  The freed cell is free, so the
-- swapped occupant lands there.
local okP, reasonP = s7:drop(1, 1)
T.eq(okP, true, "dropping on the freed cell succeeds")
T.eq(reasonP, "placed", "the result reports a placement")
T.eq(s7.carry, nil, "the hand is empty after a placement")
T.eq(layoutOf(s7, 1), "1:FIXMON_B,2:FIXMON_A,3:FIXMON_C",
  "the box is whole again, in the cells the drops chose")

-- carrying across a box boundary
local g8 = newGame()
local s8 = BoxSession.new(g8)
s8.sparse[1][1] = monOf("FIXMON_A")
s8:pickUp(1, 1)
s8:pageBox(1)
T.eq(g8.save.currentBox, 2, "paging while carrying moves the view")
T.eq(s8:drop(2, 5), true, "the carried mon drops into a free cell of the new box")
T.eq(s8.sparse[1][1], nil, "it left a gap in the origin box")
T.eq(s8.sparse[2][5] ~= nil, true, "it arrived in the destination box")
T.eq(s8.dirty, true, "a cross-box move sets dirty")

-- a swap inside a completely full box still works: swapping is the only
-- move a full box has, and it needs no free cell
local gFull = newGame()
local sFull = BoxSession.new(gFull)
for i = 1, Boxes.CAPACITY do sFull.sparse[1][i] = monOf("FIXMON_B") end
sFull.sparse[1][7] = monOf("FIXMON_A")
sFull:pickUp(1, 7)
T.eq(sFull:drop(1, 8), true, "a swap inside a full box succeeds")
T.eq(sFull.sparse[1][8].species, "FIXMON_A", "the held mon took the swapped cell")
T.eq(sFull.carry.mon.species, "FIXMON_B", "the occupant moved into the hand")
T.eq(sFull.sparse[1][7], nil, "the swap opened a gap where the held mon sat")
T.eq(sFull:count(1), Boxes.CAPACITY - 1, "the box never exceeded capacity")

-- ------- cancelling returns the mon rather than stranding it

local g9 = newGame()
local s9 = BoxSession.new(g9)
s9.sparse[4][1] = monOf("FIXMON_A")
s9:pickUp(4, 1)
T.eq(s9:cancelCarry(), true, "cancelling a carry succeeds")
T.eq(s9.carry, nil, "the hand is empty after cancelling")
T.eq(s9.sparse[4][1] ~= nil, true, "the mon went back to its origin cell")

-- cancelling falls back when the origin cell filled up meanwhile
local g13 = newGame()
local s13 = BoxSession.new(g13)
s13.sparse[5][1] = monOf("FIXMON_A")
s13.sparse[5][2] = monOf("FIXMON_B")
s13.sparse[5][3] = monOf("FIXMON_C")
s13:pickUp(5, 2)
s13.sparse[5][2] = monOf("FIXMON_D")
T.eq(s13:cancelCarry(), true, "cancelling with the origin cell taken succeeds")
T.eq(s13.sparse[5][4] ~= nil, true,
  "the mon took the origin box's first free cell instead")

-- and falls back to another box when the origin filled up completely
local g10 = newGame()
local s10 = BoxSession.new(g10)
s10.sparse[4][1] = monOf("FIXMON_A")
s10:pickUp(4, 1)
for i = 1, Boxes.CAPACITY do s10.sparse[4][i] = monOf("FIXMON_B") end
T.eq(s10:count(4), Boxes.CAPACITY, "the origin box filled up while carrying")
T.eq(s10:cancelCarry(), true, "cancelling still succeeds via the fallback")
T.eq(s10.carry, nil, "the hand is empty after the fallback cancel")
T.eq(s10:count(4), Boxes.CAPACITY, "the full origin box was left alone")
T.eq(s10.sparse[1][1] ~= nil, true, "the mon landed in the first box with room")

-- cancelling refuses rather than overflow when every cell of every box is full
local g11 = newGame()
local s11 = BoxSession.new(g11)
s11.sparse[1][1] = monOf("FIXMON_A")
s11:pickUp(1, 1)
for i = 1, Boxes.COUNT do
  for j = 1, Boxes.CAPACITY do s11.sparse[i][j] = monOf("FIXMON_B") end
end
local okC, reasonC = s11:cancelCarry()
T.eq(okC, false, "cancelling refuses when every box is full")
T.eq(reasonC, "storage_full", "the refusal names the reason")
T.eq(s11.carry ~= nil, true, "the hand is still full")
T.eq(s11.carry.mon.species, "FIXMON_A", "the held mon is unchanged")
for i = 1, Boxes.COUNT do
  T.eq(s11:count(i), Boxes.CAPACITY, "box " .. i .. " did not exceed capacity")
end

-- ------- release

local gr = newGame()
local sr = BoxSession.new(gr)
sr.sparse[1][1] = monOf("FIXMON_A")
sr.sparse[1][2] = monOf("FIXMON_C")

cries = {}
T.eq(sr:release(1, 1), true, "releasing a stored mon succeeds")
T.eq(sr.sparse[1][1], nil, "the released mon's cell is a gap")
T.eq(sr.sparse[1][2].species, "FIXMON_C",
  "the survivor did not move -- release leaves a gap, not a shift")
T.eq(#cries, 1, "release plays exactly one cry")
T.eq(sr.dirty, true, "release sets dirty")

-- and commit packs over the gap without reordering the survivor
sr:commit()
T.eq(#gr.save.boxes[1], 1, "the packed box holds the survivor alone")
T.eq(gr.save.boxes[1][1].species, "FIXMON_C", "in its cell order")
T.eq(table.concat(gr.save.bpp_layout[1], ","), "2", "the layout remembers cell 2")

local okR, reasonR = sr:release(1, 9)
T.eq(okR, false, "releasing an empty cell is refused")
T.eq(reasonR, "no_mon", "the refusal names the reason")

sr:pickUp(1, 2)
local okC2, reasonC2 = sr:release(1, 2)
T.eq(okC2, false, "releasing while carrying is refused")
T.eq(reasonC2, "carrying", "the refusal names the reason")

-- ------- a carry that ends where it started is not a change

-- The module's contract is that browsing never writes (see the commit
-- comment): picking a mon up to look at it and putting it back is the
-- browsing case that still reached commit.  pickUp leaves dirty alone,
-- but drop and cancelCarry both set it unconditionally, so the PC ran its
-- whole "Now saving..." sequence over a box that had not changed.
local gPut, putWrites = newGame()
gPut.save.boxes = nil
Boxes.ensure(gPut.save)
gPut.save.boxes[1] = { monOf("FIXMON_A"), monOf("FIXMON_B") }
local sPut = BoxSession.new(gPut)

sPut:pickUp(1, 1)
sPut:drop(1, 1)
T.eq(sPut.dirty, false, "dropping a mon back on its own cell changes nothing")
T.eq(sPut:commit(), false, "so there is nothing to commit")
T.eq(putWrites(), 0, "and the save is never written")

sPut:pickUp(1, 2)
T.eq(sPut:cancelCarry(), true, "a carry cancels back to its origin")
T.eq(sPut.dirty, false, "cancelling back to the origin changes nothing either")

-- the fix must not blunt the flag: a mon that actually moves still writes
sPut:pickUp(1, 1)
sPut:drop(1, 5)
T.eq(sPut.dirty, true, "dropping a mon on a different cell is a change")
T.eq(sPut:commit(), true, "and it commits")

-- nor may an undone swap look clean: the swap itself moved the occupant
local gSwap = newGame()
Boxes.ensure(gSwap.save)
gSwap.save.boxes[1] = { monOf("FIXMON_A"), monOf("FIXMON_B") }
local sSwap = BoxSession.new(gSwap)
sSwap:pickUp(1, 1)
sSwap:drop(1, 2)             -- swap: A into cell 2, B comes up into the hand
sSwap:drop(1, 1)             -- B down into cell 1, the hand's origin
T.eq(sSwap.dirty, true, "an undone swap still moved both mons, so it writes")
T.eq(layoutOf(sSwap, 1), "1:FIXMON_B,2:FIXMON_A", "and the two really did trade cells")

-- ------- a corrupt bpp_layout cannot crash the PC

-- SaveData serializes the whole save table, so bpp_layout is reachable by
-- anything that writes a save -- another mod, a hand-repaired save file.
-- The per-cell loop already guards its entries; the container never was,
-- and ipairs on a number throws inside BoxSession.new, which is the
-- instant the player opens the PC.
local gBad = newGame()
Boxes.ensure(gBad.save)
gBad.save.boxes[1] = { monOf("FIXMON_A"), monOf("FIXMON_B") }
gBad.save.bpp_layout = 7
local okBad, sBad = pcall(BoxSession.new, gBad)
T.eq(okBad, true, "a bpp_layout that is not a table is ignored, not fatal")
T.eq(okBad and sBad:count(1) or -1, 2, "and the box still unpacks its mons")

local gBad2 = newGame()
Boxes.ensure(gBad2.save)
gBad2.save.boxes[1] = { monOf("FIXMON_A") }
gBad2.save.bpp_layout = { "not a layout" }
local okBad2, sBad2 = pcall(BoxSession.new, gBad2)
T.eq(okBad2, true, "nor is a per-box entry that is not a table")
T.eq(okBad2 and sBad2:count(1) or -1, 1, "and that box unpacks too")

-- ------- an over-capacity box keeps the mons the grid cannot show

-- commit rewrites every box from the sparse copy, so a box holding more
-- than CAPACITY loses the overflow the moment any other box is touched --
-- the grid has only CAPACITY cells to unpack into.  The cartridge format
-- caps a box at CAPACITY, so this needs an outside writer to create, but
-- silently dropping mons is the wrong answer to finding one.
local gOver = newGame()
Boxes.ensure(gOver.save)
gOver.save.boxes[1] = { monOf("FIXMON_A") }
local over = {}
for i = 1, Boxes.CAPACITY + 3 do over[i] = monOf("FIXMON_B") end
gOver.save.boxes[2] = over
local sOver = BoxSession.new(gOver)
T.eq(sOver:count(2), Boxes.CAPACITY, "the grid shows what its cells can hold")
sOver:release(1, 1)           -- touch box 1 only
sOver:commit()
T.eq(#gOver.save.boxes[2], Boxes.CAPACITY + 3,
  "an untouched over-capacity box keeps every mon through a commit")

-- and it has to stay stable: reopening the PC re-unpacks the same box, so
-- a session that keeps the overflow only once still bleeds mons per visit
local sOver2 = BoxSession.new(gOver)
sOver2:release(2, 1)
sOver2:commit()
T.eq(#gOver.save.boxes[2], Boxes.CAPACITY + 2,
  "a second visit loses exactly the one mon that was released, no more")

-- ------- deposit defaults to the box the player is looking at
local gDep = newGame()
Boxes.ensure(gDep.save)
gDep.save.party = { monOf("FIXMON_A"), monOf("FIXMON_B") }
gDep.save.currentBox = 3
local sDep = BoxSession.new(gDep)
local okDep = sDep:deposit(1)
T.eq(okDep, true, "deposit with no box named lands in the current box")
T.eq(sDep:count(3), 1, "the mon is in the box the player was paged to")

T.finish("bills_pc_plus box_session")
