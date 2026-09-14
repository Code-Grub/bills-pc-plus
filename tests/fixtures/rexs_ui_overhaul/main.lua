-- Test double for Rex's UI Overhaul.  The real mod's public export is
-- registerAdapter(spec) -> true | false, reason (its main.lua:3570, which
-- hands the spec to _rexUiCompatibility:register).  This one keeps every spec
-- it is given so tests/rex_ui_test.lua can inspect exactly what
-- Bill's PC Plus registers.
local mod = ...
local registered = {}
mod.exports.registered = registered
mod.exports.registerAdapter = function(spec)
  registered[#registered + 1] = spec
  return true
end
