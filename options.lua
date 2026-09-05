-- Read by the mod manager's auto-UI (through manifest.options_schema) and
-- by main.lua, so the launcher can show the row before the mod is loaded
-- and the mod can read the same default after it is.
--
-- The default is ON because the DV line is what the panel was built for:
-- the hidden numbers breeders sort boxes by, which the vanilla PC never
-- showed.  Turning it off is a preference, not a return to a baseline, so
-- an update must not spring it on anyone who already has the line.
--
-- The toggle covers the DV numbers only.  The shiny mark stays on the
-- plate either way: shininess is an identity fact about the mon -- the
-- thing you scan a box for -- not a stat readout, and it costs three
-- pixels rather than a row.
return {
  {
    key = "dv_display",
    type = "toggle",
    label = "DV DISPLAY",
    default = true,
  },
}
