-- Model layer for the modern box screen.  Pure with respect to rendering:
-- no love.graphics, no stack pushes, no text.  Every mutating call returns
-- ok, reason so the screen turns a reason into a message and the model
-- never learns that a TextBox exists.
--
-- Two representations of storage live side by side:
--
--   packed  save.boxes[b]   {mon1..monN} contiguous, N <= CAPACITY.  The
--                           cartridge's shape -- count byte, that many
--                           contiguous mons, $FF -- which has no encoding
--                           for a hole (src/save_convert/GenSave.lua
--                           encodeBoxRegion).  This is what .sav export
--                           reads, and it only ever changes on commit.
--   sparse  self.sparse[b]  CAPACITY cells, mon or nil, one per visual
--                           grid cell (Layout.slotXY is 1:1).  The working
--                           copy every operation manipulates; a nil is a
--                           visible gap, and nothing shifts.
--
-- On commit the sparse cells pack back in ascending order -- which is why
-- the gap layout needs no mon identity to survive a restart:
-- save.bpp_layout[b] lists the occupied cells ascending, and packed mon k
-- sits at the kth of those cells.  bpp_layout is an engine-save extension,
-- outside the cartridge region: SaveData serializes the whole save table,
-- so it rides along, and GenSave never reads it.

local Boxes = require("src.pokemon.Boxes")
local Party = require("src.pokemon.Party")
local Stats = require("src.pokemon.Stats")

local BoxSession = {}
BoxSession.__index = BoxSession

-- Order-sensitive digest of the mons a layout was recorded against.
--
-- Only fields that cannot change while a mon sits in a box are fed in: a
-- boxed mon leaves through the PC, which re-records the layout, or it does
-- not change at all.  Deliberately excluded are ot/otId, which restoreSave
-- backfills on saves written before OT stamping (src/battle/BattleState.lua
-- stampOT), and moves, which SaveData.validate prunes against the merged
-- data -- either would break the digest on load for reasons that have
-- nothing to do with the box changing.  dvs and level are clamped by
-- scrubKnownMon, which is a no-op on values that were already in range.
local DV_ORDER = { "attack", "defense", "speed", "special" }

local function digest(packed, n)
  local h = 2166136261
  local function feed(v)
    local sv = tostring(v)
    for i = 1, #sv do
      h = (h * 33 + sv:byte(i)) % 4294967296
    end
    h = (h * 33 + 1) % 4294967296 -- field separator: "1","2" must not read as "12"
  end
  for k = 1, n do
    local mon = packed[k]
    if type(mon) ~= "table" then return nil end
    feed(mon.species)
    feed(mon.level)
    feed(mon.exp)
    local dvs = type(mon.dvs) == "table" and mon.dvs or {}
    for _, stat in ipairs(DV_ORDER) do feed(dvs[stat]) end
  end
  -- two halves: %x on a value above 2^31 is not portable across Lua builds
  return string.format("%04x%04x", math.floor(h / 65536), h % 65536)
end

-- The guard for one box: nil when there is nothing to check against, false
-- when what is there cannot be read, otherwise the { n, d } record.  Absent
-- and malformed are answered differently on purpose -- see unpackBox.
local function guardFor(save, b)
  local root = save.bpp_guard
  if root == nil then return nil end
  if type(root) ~= "table" then return false end
  local g = root[b]
  if g == nil then return nil end
  if type(g) ~= "table" or type(g.n) ~= "number" or type(g.d) ~= "string" then
    return false
  end
  return g
end

-- sparse -> packed: occupied cells in ascending order, no holes
local function toPacked(sparse)
  local t = {}
  for i = 1, Boxes.CAPACITY do
    if sparse[i] then t[#t + 1] = sparse[i] end
  end
  return t
end

-- how many cells of a sparse box hold a mon (# is meaningless with nils)
local function cellCount(sparse)
  local n = 0
  for i = 1, Boxes.CAPACITY do
    if sparse[i] then n = n + 1 end
  end
  return n
end

local function firstFree(sparse)
  for i = 1, Boxes.CAPACITY do
    if not sparse[i] then return i end
  end
  return nil
end

function BoxSession.new(game)
  Boxes.ensure(game.save)
  local self = setmetatable({
    game = game,
    save = game.save,
    data = game.data,
    carry = nil,
    dirty = false,
  }, BoxSession)
  self.sparse, self.overflow = {}, {}
  for b = 1, Boxes.COUNT do
    self.sparse[b], self.overflow[b] = self:unpackBox(b)
  end
  return self
end

-- packed -> sparse for one box.  The layout's remembered cells take the
-- packed mons in order; mons the layout does not know about -- caught,
-- traded or imported since the last PC visit -- fill the lowest free
-- cells, ascending.  A box holding more mons than the layout remembers
-- (a .sav imported over a gapped layout) simply packs solid.
function BoxSession:unpackBox(b)
  local packed = Boxes.ensure(self.save)[b] or {}
  -- The container is as untrusted as its cells.  SaveData serializes the
  -- whole save table, so anything that writes a save can leave a number or
  -- a string here, and ipairs on one throws inside BoxSession.new -- the
  -- moment the PC opens.  A layout that is not a table is simply no
  -- layout: the box packs solid, which is what a fresh save does anyway.
  local root = self.save.bpp_layout
  local layout = type(root) == "table" and root[b] or nil
  if type(layout) ~= "table" then layout = nil end
  -- The cells only mean anything for the exact mon list they were recorded
  -- against: packed mon k sits at the kth of them, so a mon removed from the
  -- middle of a box outside the PC shifts every later one down an index and
  -- the remembered cells land on the wrong mons.  SaveData.validate's scrub
  -- does exactly that (table.remove) when a species-adding mod is disabled.
  -- The guard is a digest of the mons the layout described; a box that no
  -- longer matches it packs solid, which is the honest answer once the
  -- layout has stopped describing the box.  A box that only GREW still
  -- matches -- the digest covers the first n only -- so a mon caught since
  -- the last visit still fills the leftmost gap and moves nobody.
  --
  -- No guard at all is not the same as one that will not read.  Saves from
  -- before the guard existed, and the demo tools, carry cells alone: there
  -- is nothing to verify them against, so they are trusted exactly as they
  -- were and re-guarded on the next commit.  A guard that is malformed is
  -- evidence something else wrote here, so that box packs solid.
  if layout then
    local guard = guardFor(self.save, b)
    if guard == false then
      layout = nil
    elseif guard and (#packed < guard.n or digest(packed, guard.n) ~= guard.d) then
      layout = nil
    end
  end
  local s = {}
  local k = 1
  if layout then
    for _, cell in ipairs(layout) do
      if k > #packed then break end
      if type(cell) == "number" and cell >= 1 and cell <= Boxes.CAPACITY and cell == math.floor(cell) and not s[cell] then
        s[cell] = packed[k]
        k = k + 1
      end
    end
  end
  for i = 1, Boxes.CAPACITY do
    if k > #packed then break end
    if not s[i] then
      s[i] = packed[k]
      k = k + 1
    end
  end
  -- A box holding more mons than the grid has cells has nowhere to put the
  -- rest.  The cartridge format cannot encode that, so it takes an outside
  -- writer to create -- but commit rewrites every box from its sparse copy,
  -- so leaving them here would delete them the moment another box is
  -- touched.  They ride along instead and commit appends them back.
  local overflow = {}
  while k <= #packed do
    overflow[#overflow + 1] = packed[k]
    k = k + 1
  end
  return s, overflow
end

function BoxSession:box(n)
  return self.sparse[n or self.save.currentBox]
end

-- occupied cells of a box, sparse-safe
function BoxSession:count(n)
  return cellCount(self:box(n))
end

-- Free paging is the point of the mod: no prompt, no write.  The original
-- saved here because only one box was resident in SRAM; every box is a
-- live Lua table now, so there is nothing to flush.
function BoxSession:pageBox(delta)
  local n = (self.save.currentBox or 1) + delta
  self.save.currentBox = ((n - 1) % Boxes.COUNT) + 1
  return true
end

-- Reconciles the sparse mirror back into the packed save, in memory.  The
-- mod initiates no saves of its own: this runs on the way out of the PC so
-- save.boxes is authoritative between visits, and again from main.lua's
-- save.write wrapper so a write landing mid-visit finds the same thing.
-- Browsing never sets dirty, so a browse-only visit stops at the guard.
function BoxSession:commit()
  if not self.dirty then return false end
  local layout, guard = {}, {}
  for b = 1, Boxes.COUNT do
    local s = self.sparse[b]
    local packed = toPacked(s)
    for _, mon in ipairs(self.overflow[b] or {}) do
      packed[#packed + 1] = mon
    end
    self.save.boxes[b] = packed
    local cells = {}
    for i = 1, Boxes.CAPACITY do
      if s[i] then cells[#cells + 1] = i end
    end
    layout[b] = cells
    -- The cells describe the sparse mons, which pack into the first #cells
    -- of the box; any overflow rides behind them and no cell claims it.
    guard[b] = { n = #cells, d = digest(packed, #cells) }
  end
  -- Engine-save extension, outside the cartridge region: GenSave's
  -- encodeBoxRegion reads only save.boxes and never sees this.
  self.save.bpp_layout = layout
  self.save.bpp_guard = guard
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
  local s = self.sparse[boxNum]
  local mon = s and s[slot]
  if not mon then return false, "no_mon" end
  if #self.save.party >= Party.MAX then return false, "party_full" end
  Stats.ensure(self.data.pokemon[mon.species], mon)
  s[slot] = nil
  table.insert(self.save.party, mon)
  self.dirty = true
  self:cry(mon)
  self.game.stringBuffer = self:nameOf(mon)
  return true
end

-- Deposits into the chosen box's first free cell -- gaps get used, which
-- is the point of the sparse layer.  Writes to the chosen box directly
-- rather than calling Boxes.deposit: that helper overflows into the next
-- box with room (a documented divergence, docs/known-differences.md),
-- which is right for a caught mon with nowhere to go and wrong here -- the
-- player paged to this box and pressed A, so silently filling a different
-- one is not what they asked.
function BoxSession:deposit(partySlot, boxNum)
  local mon = self.save.party[partySlot]
  if not mon then return false, "no_mon" end
  if #self.save.party <= 1 then return false, "last_mon" end
  -- default here rather than at the message below, where it read as a
  -- fallback but could never run: firstFree would already have thrown
  boxNum = boxNum or self.save.currentBox
  local s = self.sparse[boxNum]
  local slot = firstFree(s)
  if not slot then return false, "box_full" end
  s[slot] = mon
  table.remove(self.save.party, partySlot)
  -- PIKAHAPPY_DEPOSITED (engine/pokemon/bills_pc.asm:247)
  require("src.world.PikachuFollower")
    .modifyHappiness(self.save, "DEPOSITED", mon)
  self.dirty = true
  self:cry(mon)
  self.game.stringBuffer = self:nameOf(mon)
  self.game.boxNumString = tostring(boxNum)
  return true
end

function BoxSession:pickUp(boxNum, slot)
  if self.carry then return false, "already_carrying" end
  local s = self.sparse[boxNum]
  local mon = s and s[slot]
  if not mon then return false, "no_mon" end
  s[slot] = nil
  -- wasDirty is what the flag returns to if this mon ends up back in the
  -- cell it came out of: lifting a mon to look at it and putting it down
  -- is browsing, and browsing must not write
  self.carry = { mon = mon, box = boxNum, slot = slot, wasDirty = self.dirty }
  return true
end

-- A drop lands on any cell: occupied means swap (the occupant comes up
-- into the hand), free means place.  There is no past-the-end any more and
-- no compaction, so a placement never reorders anything.  The box_full
-- guard is belt-and-braces: a box with all CAPACITY cells occupied has no
-- free cell to name, so the swap branch already handled it.
function BoxSession:drop(boxNum, slot)
  if not self.carry then return false, "not_carrying" end
  local s = self.sparse[boxNum]
  local held = self.carry.mon
  local occupant = s[slot]
  if occupant then
    s[slot] = held
    -- The swap moved the occupant, so it is a change in its own right:
    -- the mon now in hand has no clean cell to return to.
    self.carry = { mon = occupant, box = boxNum, slot = slot, wasDirty = true }
    self.dirty = true
    return true, "swapped"
  end
  if cellCount(s) >= Boxes.CAPACITY then return false, "box_full" end
  s[slot] = held
  local home = boxNum == self.carry.box and slot == self.carry.slot
  if home then self.dirty = self.carry.wasDirty else self.dirty = true end
  self.carry = nil
  return true, "placed"
end

-- A carried mon must never be strandable.  Its origin cell is normally
-- still free -- pickUp only emptied it -- so that is where it goes back;
-- a swap can have filled it since, and the origin box can have filled up,
-- hence the fallbacks: first free cell of the origin box, then of any
-- box, and only when all 12 x 20 cells are full does the hand stay full.
-- Nothing reorders: a restore is one cell write.
function BoxSession:cancelCarry()
  if not self.carry then return false, "not_carrying" end
  local origin = self.sparse[self.carry.box]
  local slot = origin[self.carry.slot] == nil
    and self.carry.slot
    or firstFree(origin)
  local dest = origin
  if not slot then
    for b = 1, Boxes.COUNT do
      local s = self.sparse[b]
      local free = firstFree(s)
      if free then dest, slot = s, free break end
    end
    if not slot then return false, "storage_full" end
  end
  dest[slot] = self.carry.mon
  local home = dest == origin and slot == self.carry.slot
  if home then self.dirty = self.carry.wasDirty else self.dirty = true end
  self.carry = nil
  return true
end

-- Blocked while carrying: a hand holding a mon plus a confirm prompt is
-- the one place a mis-press could destroy the wrong one.  Releasing leaves
-- a gap -- the sparse layer's whole point -- which commit packs over
-- without reordering the survivors.
function BoxSession:release(boxNum, slot)
  if self.carry then return false, "carrying" end
  local s = self.sparse[boxNum]
  local mon = s and s[slot]
  if not mon then return false, "no_mon" end
  s[slot] = nil
  self.dirty = true
  self:cry(mon)
  self.game.stringBuffer = self:nameOf(mon)
  return true
end

return BoxSession
