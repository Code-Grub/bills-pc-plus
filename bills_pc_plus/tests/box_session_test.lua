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

-- ------- construction

local game = newGame()
local s = BoxSession.new(game)
T.eq(#game.save.boxes, 12, "construction ensures all twelve boxes")
T.eq(s.dirty, false, "a fresh session is clean")
T.eq(s.carry, nil, "a fresh session carries nothing")

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

-- ------- withdraw

-- Sound is required inline at call time, so swapping the loaded module
-- makes the cry observable without touching the audio stack.
local cries = {}
package.loaded["src.core.Sound"] = {
  playCry = function(_, species) cries[#cries + 1] = species end,
}

local function monOf(species, level)
  return { species = species, level = level or 5, hp = 10,
           dvs = { attack = 8, defense = 8, speed = 8, special = 8 },
           statExp = {}, moves = {} }
end

local g3 = newGame()
local s3 = BoxSession.new(g3)
g3.save.boxes[1] = { monOf("FIXMON_A", 12) }

local ok, reason = s3:withdraw(1, 2)
T.eq(ok, false, "withdrawing an empty slot is refused")
T.eq(reason, "no_mon", "the refusal names the reason")

cries = {}
T.eq(s3:withdraw(1, 1), true, "withdrawing a stored mon succeeds")
T.eq(#g3.save.party, 1, "the mon reached the party")
T.eq(#g3.save.boxes[1], 0, "the box slot was vacated")
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
g4.save.boxes[1] = { monOf("FIXMON_A") }
local ok4, reason4 = s4:withdraw(1, 1)
T.eq(ok4, false, "a full party refuses a withdrawal")
T.eq(reason4, "party_full", "the refusal names the reason")
T.eq(#g4.save.boxes[1], 1, "the refused mon stays in the box")
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
T.eq(#g5.save.boxes[3], 1, "the mon landed in box 3, not the current box by accident")
T.eq(s5.dirty, true, "deposit sets dirty")
T.eq(#cries, 1, "deposit plays exactly one cry")
T.eq(#happiness, 1, "deposit fires the Pikachu happiness event once")
T.eq(happiness[1], "DEPOSITED", "the event is DEPOSITED")
T.eq(g5.boxNumString, "3", "boxNumString carries the destination for messages")

-- the last party mon cannot leave
local ok5, reason5 = s5:deposit(1, 3)
T.eq(ok5, false, "depositing the last party mon is refused")
T.eq(reason5, "last_mon", "the refusal names the reason")
T.eq(#g5.save.party, 1, "the last mon stays in the party")

-- a full destination refuses rather than overflowing into the next box
local g6 = newGame()
local s6 = BoxSession.new(g6)
g6.save.party = { monOf("FIXMON_A"), monOf("FIXMON_B") }
for i = 1, 20 do g6.save.boxes[2][i] = monOf("FIXMON_B") end
local ok6, reason6 = s6:deposit(2, 2)
T.eq(ok6, false, "a full destination box refuses the deposit")
T.eq(reason6, "box_full", "the refusal names the reason")
T.eq(#g6.save.boxes[3], 0, "the mon did not overflow into the next box")
T.eq(#g6.save.party, 2, "the party is unchanged")

-- ------- carry

local function packed(box)
  for i = 1, #box do if box[i] == nil then return false end end
  return true
end

local g7 = newGame()
local s7 = BoxSession.new(g7)
g7.save.boxes[1] = { monOf("FIXMON_A"), monOf("FIXMON_B"), monOf("FIXMON_C") }

local ok7, reason7 = s7:drop(1, 1)
T.eq(ok7, false, "dropping with an empty hand is refused")
T.eq(reason7, "not_carrying", "the refusal names the reason")

T.eq(s7:pickUp(1, 1), true, "picking up a stored mon succeeds")
T.eq(s7.carry.mon.species, "FIXMON_A", "the hand holds the picked-up mon")
T.eq(#g7.save.boxes[1], 2, "the source box compacted")
T.eq(packed(g7.save.boxes[1]), true, "the source box has no hole")
T.eq(g7.save.boxes[1][1].species, "FIXMON_B", "the remainder shifted down")

local ok8, reason8 = s7:pickUp(1, 1)
T.eq(ok8, false, "picking up twice is refused")
T.eq(reason8, "already_carrying", "the refusal names the reason")

-- dropping on an occupied slot swaps: the occupant comes up into the hand
local okS, reasonS = s7:drop(1, 1)
T.eq(okS, true, "dropping on an occupied slot succeeds")
T.eq(reasonS, "swapped", "the result reports a swap")
T.eq(g7.save.boxes[1][1].species, "FIXMON_A", "the held mon took the slot")
T.eq(s7.carry.mon.species, "FIXMON_B", "the occupant is now held")

-- dropping past the end appends and empties the hand
local okP, reasonP = s7:drop(1, 99)
T.eq(okP, true, "dropping past the end succeeds")
T.eq(reasonP, "placed", "the result reports a placement")
T.eq(s7.carry, nil, "the hand is empty after a placement")
T.eq(#g7.save.boxes[1], 3, "the box is whole again")
T.eq(packed(g7.save.boxes[1]), true, "the box still has no hole")

-- carrying across a box boundary
local g8 = newGame()
local s8 = BoxSession.new(g8)
g8.save.boxes[1] = { monOf("FIXMON_A") }
s8:pickUp(1, 1)
s8:pageBox(1)
T.eq(g8.save.currentBox, 2, "paging while carrying moves the view")
T.eq(s8:drop(2, 1), true, "the carried mon drops into the new box")
T.eq(#g8.save.boxes[1], 0, "it left the origin box")
T.eq(#g8.save.boxes[2], 1, "it arrived in the destination box")
T.eq(s8.dirty, true, "a cross-box move sets dirty")

-- cancelling returns the mon rather than stranding it
local g9 = newGame()
local s9 = BoxSession.new(g9)
g9.save.boxes[4] = { monOf("FIXMON_A") }
s9:pickUp(4, 1)
T.eq(s9:cancelCarry(), true, "cancelling a carry succeeds")
T.eq(s9.carry, nil, "the hand is empty after cancelling")
T.eq(#g9.save.boxes[4], 1, "the mon went back to its origin box")

-- cancelling falls back to another box when the origin filled up meanwhile
local g10 = newGame()
local s10 = BoxSession.new(g10)
g10.save.boxes[4] = { monOf("FIXMON_A") }
s10:pickUp(4, 1)
for i = 1, Boxes.CAPACITY do g10.save.boxes[4][i] = monOf("FIXMON_B") end
T.eq(#g10.save.boxes[4], Boxes.CAPACITY, "the origin box filled up while carrying")
T.eq(s10:cancelCarry(), true, "cancelling still succeeds via the fallback")
T.eq(s10.carry, nil, "the hand is empty after the fallback cancel")
T.eq(#g10.save.boxes[4], Boxes.CAPACITY, "the full origin box was left alone")
T.eq(#g10.save.boxes[1], 1, "the mon landed in the first box with room")
T.eq(packed(g10.save.boxes[1]), true, "the destination box has no hole")

-- cancelling restores the mon to its original slot, not the end of the box
local g13 = newGame()
local s13 = BoxSession.new(g13)
g13.save.boxes[5] = { monOf("FIXMON_A"), monOf("FIXMON_B"), monOf("FIXMON_C") }
s13:pickUp(5, 2)
T.eq(s13:cancelCarry(), true, "cancelling a mid-box pickup succeeds")
T.eq(s13.carry, nil, "the hand is empty after cancelling")
local names13 = {}
for i = 1, #g13.save.boxes[5] do names13[i] = g13.save.boxes[5][i].species end
T.eq(table.concat(names13, ","), "FIXMON_A,FIXMON_B,FIXMON_C",
  "the box order is restored, not reordered to A,C,B")

-- cancelling restores a pickup from the first slot to the first slot
local g14 = newGame()
local s14 = BoxSession.new(g14)
g14.save.boxes[5] = { monOf("FIXMON_A"), monOf("FIXMON_B"), monOf("FIXMON_C") }
s14:pickUp(5, 1)
T.eq(s14:cancelCarry(), true, "cancelling a first-slot pickup succeeds")
local names14 = {}
for i = 1, #g14.save.boxes[5] do names14[i] = g14.save.boxes[5][i].species end
T.eq(table.concat(names14, ","), "FIXMON_A,FIXMON_B,FIXMON_C",
  "the box order is restored with the mon back in slot 1")

-- cancelling refuses rather than overflow a box when every box is full
local g11 = newGame()
local s11 = BoxSession.new(g11)
g11.save.boxes[1] = { monOf("FIXMON_A") }
s11:pickUp(1, 1)
for i = 1, Boxes.COUNT do
  local full = {}
  for j = 1, Boxes.CAPACITY do full[j] = monOf("FIXMON_B") end
  g11.save.boxes[i] = full
end
local okC, reasonC = s11:cancelCarry()
T.eq(okC, false, "cancelling refuses when every box is full")
T.eq(reasonC, "storage_full", "the refusal names the reason")
T.eq(s11.carry ~= nil, true, "the hand is still full")
T.eq(s11.carry.mon.species, "FIXMON_A", "the held mon is unchanged")
for i = 1, Boxes.COUNT do
  T.eq(#g11.save.boxes[i], Boxes.CAPACITY, "box " .. i .. " did not exceed capacity")
end

-- dropping past the end of a full box is refused, not overflowed
local g12 = newGame()
local s12 = BoxSession.new(g12)
g12.save.boxes[6] = { monOf("FIXMON_A") }
s12:pickUp(6, 1)
for i = 1, Boxes.CAPACITY do g12.save.boxes[6][i] = monOf("FIXMON_B") end
local okF, reasonF = s12:drop(6, 99)
T.eq(okF, false, "dropping past the end of a full box is refused")
T.eq(reasonF, "box_full", "the refusal names the reason")
T.eq(s12.carry ~= nil, true, "the hand is still full after the refusal")
T.eq(#g12.save.boxes[6], Boxes.CAPACITY, "the box did not exceed capacity")

-- ------- release

local g10 = newGame()
local s10 = BoxSession.new(g10)
g10.save.boxes[1] = { monOf("FIXMON_A"), monOf("FIXMON_C") }

cries = {}
T.eq(s10:release(1, 1), true, "releasing a stored mon succeeds")
T.eq(#g10.save.boxes[1], 1, "the box lost the released mon")
T.eq(g10.save.boxes[1][1].species, "FIXMON_C", "the remainder shifted down")
T.eq(packed(g10.save.boxes[1]), true, "the box has no hole after a release")
T.eq(#cries, 1, "release plays exactly one cry")
T.eq(s10.dirty, true, "release sets dirty")

local okR, reasonR = s10:release(1, 9)
T.eq(okR, false, "releasing an empty slot is refused")
T.eq(reasonR, "no_mon", "the refusal names the reason")

s10:pickUp(1, 1)
local okC, reasonC = s10:release(1, 1)
T.eq(okC, false, "releasing while carrying is refused")
T.eq(reasonC, "carrying", "the refusal names the reason")

T.finish("bills_pc_plus box_session")
