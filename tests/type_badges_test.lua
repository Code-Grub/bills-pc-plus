-- Standalone: luajit mods/bills_pc_plus/tests/type_badges_test.lua
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local T = require("tests.modkit")
local L = dofile("mods/bills_pc_plus/Layout.lua")
local B = dofile("mods/bills_pc_plus/TypeBadges.lua")

-- every type either generation can print, spelled as TypeChart.displayName
-- returns it
local ALL = { "NORMAL", "FIRE", "WATER", "ELECTRIC", "GRASS", "ICE", "FIGHTING",
  "POISON", "GROUND", "FLYING", "PSYCHIC", "BUG", "ROCK", "GHOST", "DRAGON",
  "DARK", "STEEL" }

for _, name in ipairs(ALL) do
  local c = B.color(name)
  T.check(type(c) == "table" and #c == 3, name .. " has an rgb colour")
  for i = 1, 3 do
    T.check(c[i] >= 0 and c[i] <= 255, name .. " channel " .. i .. " is 0..255")
  end
end
T.eq(table.concat(B.color("BOGUS"), ","), table.concat(B.color("NORMAL"), ","),
  "an unknown type falls back to NORMAL's colour rather than erroring")

-- Label colour is a per-type decision made by looking at the pills, not a
-- luminance cutoff: BUG and FLYING differ by 0.001 in luma and want opposite
-- answers.
for _, name in ipairs({ "FLYING", "GHOST", "DRAGON", "DARK", "FIGHTING",
  "POISON", "WATER", "FIRE", "PSYCHIC", "ROCK" }) do
  T.check(B.whiteText(name), name .. " takes a white label")
end
for _, name in ipairs({ "ELECTRIC", "GROUND", "ICE", "NORMAL", "STEEL", "BUG",
  "GRASS" }) do
  T.check(not B.whiteText(name), name .. " takes a black label")
end
T.check(not B.whiteText("BOGUS"), "an unknown type takes the black label")

-- Geometry.  Widths are whatever the label measures plus the pill's padding.
T.eq(L.pillWidth(64), 64 + 2 * L.BADGE_PAD, "a pill is its label plus padding each side")

-- one pill starts at the strip's left edge plus the margin
local one = L.badgeSpans({ L.pillWidth(32) })
T.eq(#one, 1, "one type, one span")
T.eq(one[1].x, L.STATS_X + L.BADGE_MARGIN, "the first pill starts at the margin")
T.eq(one[1].w, L.pillWidth(32), "and keeps its width")

-- two pills sit on one line, a gap apart, never overlapping
local two = L.badgeSpans({ L.pillWidth(64), L.pillWidth(48) })
T.eq(#two, 2, "two types, two spans")
T.eq(two[2].x, two[1].x + two[1].w + L.BADGE_GAP, "the second follows after the gap")

-- The worst pair either generation prints is ELECTRIC/FLYING (Zapdos); at
-- 8px a glyph it has to end inside box B's interior (x=152).
local zap = L.badgeSpans({ L.pillWidth(8 * 8), L.pillWidth(6 * 8) })
local right = zap[2].x + zap[2].w
T.check(right <= 152, "the widest pair ends inside the frame (" .. right .. ")")
T.eq(right, 144, "and on the stats columns' right edge, not tighter")

-- the pill is 12px tall, and fits the blank row plus the type row (16px)
T.eq(L.BADGE_H, 12, "a pill is 12px tall")
T.check(L.BADGE_H <= 2 * L.ROW, "and fits the two rows it spans")
T.eq(L.badgeY(false), L.STATS_Y + 4 * L.ROW - L.ROW + (2 * L.ROW - L.BADGE_H) / 2,
  "centred in the blank+type rows when DVs show")
T.eq(L.badgeY(true), L.badgeY(false) - L.ROW, "one row higher when DVs are hidden")

T.finish("bills_pc_plus type badges")
