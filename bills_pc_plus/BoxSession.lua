-- Model layer for the modern box screen.  Pure with respect to rendering:
-- no love.graphics, no stack pushes, no text.  Every mutating call returns
-- ok, reason so the screen turns a reason into a message and the model
-- never learns that a TextBox exists.
--
-- Packing invariant: a box's occupied slots always run 1..n with no holes,
-- because the cartridge format cannot encode a hole (a count byte plus
-- that many contiguous mons, src/save_convert/GenSave.lua:987-1001).

local Boxes = require("src.pokemon.Boxes")
local Party = require("src.pokemon.Party")
local Stats = require("src.pokemon.Stats")

local BoxSession = {}
BoxSession.__index = BoxSession

function BoxSession.new(game)
  Boxes.ensure(game.save)
  return setmetatable({
    game = game,
    save = game.save,
    data = game.data,
    carry = nil,
    dirty = false,
  }, BoxSession)
end

function BoxSession:box(n)
  return Boxes.ensure(self.save)[n or self.save.currentBox]
end

-- Free paging is the point of the mod: no prompt, no write.  The original
-- saved here because only one box was resident in SRAM; every box is a
-- live Lua table now, so there is nothing to flush.
function BoxSession:pageBox(delta)
  local n = (self.save.currentBox or 1) + delta
  self.save.currentBox = ((n - 1) % Boxes.COUNT) + 1
  return true
end

-- Runs on exit.  Browsing must never write, so only a content change
-- reaches here.  Guarded the way src/ui/BoxMenu.lua:205 guards it, which
-- also keeps the call headless-safe.
function BoxSession:commit()
  if not self.dirty then return false end
  if self.game.writeSave then self.game:writeSave() end
  self.dirty = false
  return true
end

function BoxSession:nameOf(mon)
  local def = self.data.pokemon[mon.species]
  return mon.nickname or (def and def.name) or tostring(mon.species)
end

-- required inline, matching src/ui/BoxMenu.lua:88, so a test can swap the
-- loaded module and observe the call
function BoxSession:cry(mon)
  require("src.core.Sound").playCry(self.data, mon.species)
end

-- add_mon.asm _MoveMon runs CalcStats on the way back to the party:
-- box_struct stops before MON_STATS, so a mon decoded out of an imported
-- .sav has no stat block and every later HP-bar draw nil-indexes it.
function BoxSession:withdraw(boxNum, slot)
  local box = self:box(boxNum)
  local mon = box[slot]
  if not mon then return false, "no_mon" end
  if #self.save.party >= Party.MAX then return false, "party_full" end
  Stats.ensure(self.data.pokemon[mon.species], mon)
  table.remove(box, slot)
  table.insert(self.save.party, mon)
  self.dirty = true
  self:cry(mon)
  self.game.stringBuffer = self:nameOf(mon)
  return true
end

-- Writes to the chosen box directly rather than calling Boxes.deposit.
-- That helper overflows into the next box with room (a documented
-- divergence, docs/known-differences.md), which is right for a caught mon
-- with nowhere to go and wrong here: the player paged to this box and
-- pressed A, so silently filling a different one is not what they asked.
function BoxSession:deposit(partySlot, boxNum)
  local mon = self.save.party[partySlot]
  if not mon then return false, "no_mon" end
  if #self.save.party <= 1 then return false, "last_mon" end
  local box = self:box(boxNum)
  if #box >= Boxes.CAPACITY then return false, "box_full" end
  table.remove(self.save.party, partySlot)
  table.insert(box, mon)
  -- PIKAHAPPY_DEPOSITED (engine/pokemon/bills_pc.asm:247)
  require("src.world.PikachuFollower")
    .modifyHappiness(self.save, "DEPOSITED", mon)
  self.dirty = true
  self:cry(mon)
  self.game.stringBuffer = self:nameOf(mon)
  self.game.boxNumString = tostring(boxNum or self.save.currentBox)
  return true
end

function BoxSession:pickUp(boxNum, slot)
  if self.carry then return false, "already_carrying" end
  local box = self:box(boxNum)
  local mon = box[slot]
  if not mon then return false, "no_mon" end
  table.remove(box, slot)
  self.carry = { mon = mon, box = boxNum, slot = slot }
  return true
end

-- Under the packing invariant an empty slot only ever appears after the
-- last mon, so a drop has exactly two meanings: land on someone (swap,
-- and their occupant comes up into the hand) or land past the end
-- (append, and the hand empties).
function BoxSession:drop(boxNum, slot)
  if not self.carry then return false, "not_carrying" end
  local box = self:box(boxNum)
  local held = self.carry.mon
  local occupant = box[slot]
  if occupant then
    box[slot] = held
    self.carry = { mon = occupant, box = boxNum, slot = slot }
    self.dirty = true
    return true, "swapped"
  end
  if #box >= Boxes.CAPACITY then return false, "box_full" end
  table.insert(box, held)
  self.carry = nil
  self.dirty = true
  return true, "placed"
end

-- A carried mon must never be strandable.  pickUp left a vacancy, so the
-- origin normally has room; a swap can have filled it since, hence the
-- fallback to the first box with space.  If every box is full there is
-- nowhere safe to put the mon down, so the hand stays full rather than
-- overflowing a box past Boxes.CAPACITY.
function BoxSession:cancelCarry()
  if not self.carry then return false, "not_carrying" end
  local box = self:box(self.carry.box)
  local restoring = true
  if #box >= Boxes.CAPACITY then
    local candidate = nil
    for i = 1, Boxes.COUNT do
      local b = self:box(i)
      if #b < Boxes.CAPACITY then candidate = b break end
    end
    if not candidate then return false, "storage_full" end
    box = candidate
    restoring = false
  end
  if restoring then
    local pos = self.carry.slot
    if pos < 1 then pos = 1 end
    if pos > #box + 1 then pos = #box + 1 end
    table.insert(box, pos, self.carry.mon)
  else
    -- The fallback box is not the origin, so the recorded slot is
    -- meaningless here; land the mon at the end like a fresh deposit.
    table.insert(box, self.carry.mon)
  end
  self.carry = nil
  self.dirty = true
  return true
end

-- Blocked while carrying: a hand holding a mon plus a confirm prompt is
-- the one place a mis-press could destroy the wrong one.
function BoxSession:release(boxNum, slot)
  if self.carry then return false, "carrying" end
  local box = self:box(boxNum)
  local mon = box[slot]
  if not mon then return false, "no_mon" end
  table.remove(box, slot)
  self.dirty = true
  self:cry(mon)
  self.game.stringBuffer = self:nameOf(mon)
  return true
end

return BoxSession
