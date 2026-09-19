-- Test double for Gen 1 Modern UI.  Its real public export is
-- registerAdapter(spec) -> true | false, reason (its main.lua:3176, which
-- hands the spec to _gen1ModernCompatibility:register), the same signature
-- Rex uses.  This one keeps every spec so the test can inspect exactly
-- what Bill's PC Plus registers.
local mod = ...
local registered = {}
mod.exports.registered = registered
mod.exports.surfaceApiVersion = 2
mod.exports.registerAdapter = function(spec)
  registered[#registered + 1] = spec
  return true
end
