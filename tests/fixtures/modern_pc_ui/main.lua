-- Test double for Modern PC UI.  It claims one screen and nothing else:
-- its main.lua:38-41 takes the override branch when BoxMenu is already
-- registered and the register branch when it is not, at priority 1100 --
-- above ours, so it always runs second.  That is the whole of what Bill's
-- PC Plus has to notice, so that is all this double does.
local mod = ...
local screen = { new = function() return { modernPcUi = true } end }
if mod.content.screens:get("BoxMenu") then
  mod.content.screens:override("BoxMenu", screen)
else
  mod.content.screens:register("BoxMenu", screen)
end
