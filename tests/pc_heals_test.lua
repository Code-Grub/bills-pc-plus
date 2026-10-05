-- Standalone: luajit mods/bills_pc_plus/tests/pc_heals_test.lua
--
-- The PC HEALS option: a mon entering a box comes out whole, as it does on
-- Gold, where box_struct has no HP or status to keep.  The screen consequence
-- (the HP line goes, the sprite drops onto the freed row) is Layout's half.
-- Its own file because bills_pc_plus_test.lua is at LuaJIT's 200-local ceiling.
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local T = require("tests.modkit")
local Data = require("tests.modkit.fixtures").fresh()

-- Pokemon.heal looks moves up in the core table, which the running engine
-- fills and the fixture world does not; hand it the fixture's.
local CoreData = require("src.core.Data")
CoreData.moves = Data.moves

local BoxSession = dofile("mods/bills_pc_plus/BoxSession.lua")
local Engine = dofile("mods/bills_pc_plus/Engine.lua")
local L = dofile("mods/bills_pc_plus/Layout.lua")

local function newGame()
  return {
    data = Data,
    save = { party = {}, boxes = nil, currentBox = 1 },
    writeSave = function() end,
  }
end

-- a hurt, poisoned mon with one move that has spent PP
local function hurt(species)
  return {
    species = species, level = 20, hp = 3, status = "PSN",
    stats = { hp = 50, attack = 30, defense = 30, speed = 30, special = 30 },
    dvs = { attack = 8, defense = 8, speed = 8, special = 8 },
    statExp = {},
    moves = { { id = "FIX_SCRATCH", pp = 1, ppUps = 0 } },
  }
end

local function session(heals)
  local g = newGame()
  BoxSession.new(g)
  g.save.party = { hurt("FIXMON_A"), hurt("FIXMON_B") }
  local s = BoxSession.new(g, Engine.new(false))
  s.heals = heals
  return s, g
end

-- ------- deposit heals on Gen 1 when the option is on

local s, g = session(function() return true end)
local mon = g.save.party[2]
T.eq(s:deposit(2, 1), true, "the deposit goes through")
T.eq(mon.hp, 50, "a deposited mon is restored to full HP")
T.eq(mon.status, nil, "and its status is cleared")
T.eq(mon.moves[1].pp > 1, true, "and its PP is restored, as on Gold")

-- ------- option off: Gen 1 keeps its stored HP

local s2, g2 = session(function() return false end)
local mon2 = g2.save.party[2]
T.eq(s2:deposit(2, 1), true, "the deposit goes through with the option off")
T.eq(mon2.hp, 3, "off: the stored HP is left alone")
T.eq(mon2.status, "PSN", "off: the status is left alone")
T.eq(mon2.moves[1].pp, 1, "off: PP is left alone")

-- a session nobody wired up behaves like the option being off
local s3, g3 = session(nil)
local mon3 = g3.save.party[2]
s3:deposit(2, 1)
T.eq(mon3.hp, 3, "no predicate means no healing")

-- ------- withdraw heals what was boxed before the option existed

local s4, g4 = session(function() return true end)
local old = hurt("FIXMON_C")
s4.sparse[1][5] = old
T.eq(s4:withdraw(1, 5), true, "withdrawing a legacy hurt mon works")
T.eq(old.hp, 50, "a mon boxed hurt before the option comes out whole")
T.eq(old.status, nil, "and cured")

local s5, g5 = session(function() return false end)
local old5 = hurt("FIXMON_C")
s5.sparse[1][5] = old5
s5:withdraw(1, 5)
T.eq(old5.hp, 3, "off: withdrawing leaves HP alone")

-- ------- the seam itself

local e = Engine.new(false)
local m = hurt("FIXMON_A")
e:enterBox(m, false)
T.eq(m.hp, 3, "Engine:enterBox(mon, false) on Gen 1 is still a no-op")
e:enterBox(m, true)
T.eq(m.hp, 50, "Engine:enterBox(mon, true) on Gen 1 heals")

-- ------- layout: the sprite drops onto the freed row

local _, y80 = L.spritePos(56, 56)
local _, y88 = L.spritePos(56, 56, L.SPRITE_BASELINE_NO_HP)
T.eq(y88 - y80, L.ROW, "without the HP line the sprite stands one row lower")
T.eq(L.SPRITE_BASELINE_NO_HP % 8, 0,
  "and still tile-aligned, so its SGB zone lands on the sprite")
local zx1, zy1, zx2, zy2 = L.spriteZone(L.SPRITE_BASELINE_NO_HP)
local _, py = L.spritePos(L.SPRITE_MAX, L.SPRITE_MAX, L.SPRITE_BASELINE_NO_HP)
T.eq(zy1 * 8, py, "the zone starts where the sprite does")
T.eq((zy2 + 1) * 8, py + L.SPRITE_MAX, "and ends where it ends")

T.finish("bills_pc_plus pc_heals")
