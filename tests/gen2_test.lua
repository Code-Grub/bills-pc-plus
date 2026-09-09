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

T.finish("bills_pc_plus gen2")
