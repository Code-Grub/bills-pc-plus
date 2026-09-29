-- Standalone: luajit mods/bills_pc_plus/tests/pc_menu_test.lua
--
-- Gold's PC menu (src/ui/gen2/PcMenu.lua) lists CHANGE BOX between DEPOSIT
-- and MOVE.  The grid pages boxes itself (left and right on the header), so
-- the row is a second, worse way to do what the screen already does.  Gen 1
-- never shows it because the mod replaces vanilla's whole BoxMenu; on Gold
-- that menu is the engine's, so the mod drops the row through the
-- ui.pc.items hook.  Its own file: bills_pc_plus_test.lua is at LuaJIT's
-- 200-local ceiling.
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local T = require("tests.modkit")
local Data = require("tests.modkit.fixtures").fresh()
local Runtime = require("src.mods.Runtime")

local run = T.sdk.loadMod("mods/bills_pc_plus", { data = Data, generation = 2 })
T.eq(#run.errors, 0, "loads clean (" .. tostring(run.errors[1]) .. ")")
T.eq(run.mod and run.mod.state, "loaded", "and actually runs on a Gen 2 boot")
local Screens = require("src.ui.Screens")
Screens.invalidate()

local function ids(menu)
  local out = {}
  for i, entry in ipairs(menu.entries) do out[i] = entry.id end
  return out
end

local function openPc(opts)
  local game = {
    data = Data,
    save = { party = {}, boxes = {}, currentBox = 1 },
    stack = { push = function() end, pop = function() end },
    input = { wasPressed = function() return false end,
              isDown = function() return false end },
  }
  opts = opts or {}
  opts.save = game.save
  return Screens.get(game, "Gen2PcMenu").new(game, opts)
end

-- Bill's PC's own rows, the ones _BillsPC lists
local bills = ids(openPc({ bills = true }))
T.eq(table.concat(bills, ","), "withdraw,deposit,move,seeya",
  "Bill's PC loses CHANGE BOX and keeps the rest in the cart's order")

-- the folded menu (a directly constructed PcMenu) also carries MAIL BOX
local folded = ids(openPc())
local has = {}
for _, id in ipairs(folded) do has[id] = true end
T.check(not has.changebox, "the folded menu drops CHANGE BOX too")
T.check(has.withdraw and has.deposit and has.move and has.mailbox,
  "and keeps WITHDRAW, DEPOSIT, MOVE and MAIL BOX")
T.eq(folded[#folded], "seeya", "SEE YA! is still last: the way out cannot be orphaned")

-- The hook is shared by name with Gen 1, where it sees the which-PC list
-- and rows have no id.  It has to hand that list back untouched.
local rows = {
  { label = "SOMEONE'S PC" }, { label = "RED's PC" }, { label = "LOG OFF" },
}
local out = Runtime.call("ui.pc.items", function(_, items) return items end, {}, rows)
T.eq(#out, 3, "a Gen 1 shaped list keeps all its rows")
for i = 1, 3 do
  T.check(out[i] == rows[i], "and the very same row " .. i .. ", not a copy")
end

run.release()
Screens.invalidate()
T.finish("bills_pc_plus pc_menu")
