-- Standalone: luajit mods/bills_pc_plus/tests/bills_pc_plus_test.lua
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local T = require("tests.modkit")
local Data = require("tests.modkit.fixtures").fresh()

local run = T.sdk.loadMod("mods/bills_pc_plus", { data = Data })
T.eq(#run.errors, 0, "loads clean (" .. tostring(run.errors[1]) .. ")")

local Screens = require("src.ui.Screens")
local L = dofile("mods/bills_pc_plus/Layout.lua")
Screens.invalidate()

local game = {
  data = Data,
  save = { party = {}, boxes = nil, currentBox = 1 },
  stack = { push = function() end },
  input = { wasPressed = function() return false end, isDown = function() return false end },
}

-- The registered factory now returns the WITHDRAW/DEPOSIT menu, matching
-- vanilla src/ui/BoxMenu.lua.  The grid is what a menu row pushes, so every
-- grid test reaches it the way a player does: open the menu, pick a row,
-- take what landed on the stack.
local function openGrid(g, rowLabel)
  local captured = {}
  local realStack = g.stack
  g.stack = { push = function(_, st) captured[#captured + 1] = st end,
              pop = function() end }
  local menu = Screens.get(g, "BoxMenu").new(g)
  for _, item in ipairs(menu.items) do
    if item.label == rowLabel and item.onSelect then item.onSelect() end
  end
  g.stack = realStack
  return captured[#captured], menu
end

local factory = Screens.get(game, "BoxMenu")
T.check(factory and factory.new, "BoxMenu resolves through the registry")
T.check(factory ~= require("src.ui.BoxMenu"),
  "the mod screen wins over the builtin BoxMenu")

local screen = openGrid(game, "WITHDRAW POKéMON")
T.check(screen.session ~= nil, "the screen owns a BoxSession")
T.eq(screen.cursor, 1, "the cursor starts on the first slot")
T.eq(screen.mode, "box", "the screen starts in box view")
T.eq(#game.save.boxes, 12, "opening the screen ensured the boxes")

-- drawing an empty box must not error
local okDraw, drawErr = pcall(function() screen:draw() end)
T.check(okDraw, "drawing an empty box succeeds: " .. tostring(drawErr))

-- and drawing a populated one must not either
game.save.boxes[1] = {
  { species = "FIXMON_A", level = 12, hp = 20, dvs = {}, statExp = {}, moves = {},
    stats = { hp = 20, attack = 12, defense = 12, speed = 12, special = 12 } },
}
local okDraw2, drawErr2 = pcall(function() screen:draw() end)
T.check(okDraw2, "drawing a populated box succeeds: " .. tostring(drawErr2))

-- a mon decoded from an imported save can lack a stats block entirely
-- (box_struct stops before MON_STATS); drawStats must guard that, not nil-index it
game.save.boxes[1][1] = {
  species = "FIXMON_A", level = 12, hp = 20, dvs = {}, statExp = {}, moves = {},
}
local okDraw3, drawErr3 = pcall(function() screen:draw() end)
T.check(okDraw3, "drawing a mon with no stats block succeeds: " .. tostring(drawErr3))

-- ------- cursor movement

-- the input double mirrors tests/mod_ui_tests.lua's queue idiom, plus the
-- held state the dpad repeat reads: a tap is one frame of down AND pressed;
-- hold() keeps only down, so no further pressed edges fire
local function press(state, btn)
  state.game.input.queue = { [btn] = true }
  state.game.input.down = { [btn] = true }
  state:update(1 / 60)
  state.game.input.queue = {}
  state.game.input.down = {}
end

-- hold() keeps the button down for frames frames, the way a finger lands
-- and stays; edge=true also presses on the first frame.  Held-only frames
-- run no pressed edge, which is what distinguishes a hold from a tap.
local function hold(state, btn, frames, edge)
  for i = 1, frames do
    state.game.input.queue = (edge and i == 1) and { [btn] = true } or {}
    state.game.input.down = { [btn] = true }
    state:update(1 / 60)
  end
  state.game.input.queue, state.game.input.down = {}, {}
end

game.input = {
  queue = {},
  down = {},
  wasPressed = function(self, btn) return self.queue[btn] or false end,
  isDown = function(self, btn) return self.down[btn] or false end,
}

local nav = openGrid(game, "WITHDRAW POKéMON")
game.save.currentBox = 1

press(nav, "right")
T.eq(nav.cursor, 2, "right moves one column")
press(nav, "down")
T.eq(nav.cursor, 7, "down moves one row, five slots")
press(nav, "left")
T.eq(nav.cursor, 6, "left moves back one column")
press(nav, "up")
T.eq(nav.cursor, 1, "up moves back one row")

press(nav, "up")
T.eq(nav.cursor, 1, "up on the top row does not leave the grid")
press(nav, "down") press(nav, "down") press(nav, "down") press(nav, "down")
T.eq(nav.cursor, 16, "down stops on the bottom row")

-- left off the left edge pages back a box and lands on the right column
nav.cursor = 6
press(nav, "left")
T.eq(game.save.currentBox, 12, "left at the edge pages to the previous box")
T.eq(nav.cursor, 10, "the cursor wrapped to the rightmost column, same row")

-- right off the right edge pages forward
press(nav, "right")
T.eq(game.save.currentBox, 1, "right at the edge pages to the next box")
T.eq(nav.cursor, 6, "the cursor wrapped to the leftmost column, same row")
T.eq(nav.session.dirty, false, "paging with the cursor never dirties the session")

-- ------- the cursor menu

local pushed = {}
game.stack = {
  push = function(_, state) pushed[#pushed + 1] = state end,
  pop = function() pushed[#pushed] = nil end,
}

local act = openGrid(game, "WITHDRAW POKéMON")
game.save.currentBox = 1
game.save.boxes[1] = {
  { species = "FIXMON_A", level = 12, hp = 20, dvs = {}, statExp = {}, moves = {},
    stats = { hp = 20, attack = 12, defense = 12, speed = 12, special = 12 } },
}
act.cursor = 1

pushed = {}
press(act, "a")
T.eq(#pushed, 1, "A on a stored mon opens one menu")
local labels = {}
for _, item in ipairs(pushed[1].items or {}) do labels[#labels + 1] = item.label end
T.eq(table.concat(labels, ","), "MOVE,WITHDRAW,STATS,RELEASE,CANCEL",
  "the cursor menu carries the five verbs in order")

-- A on an empty slot opens nothing
act.cursor = 5
pushed = {}
press(act, "a")
T.eq(#pushed, 0, "A on an empty slot opens no menu")

-- while carrying, A drops instead of opening a menu
act.session:pickUp(1, 1)
act.cursor = 3
pushed = {}
press(act, "a")
T.eq(#pushed, 0, "A while carrying opens no menu")
T.eq(act.session.carry, nil, "A while carrying places the mon")
T.eq(act.session.sparse[1][3] ~= nil, true, "the placed mon took cell 3")

-- B cancels a carry rather than exiting
act.session:pickUp(1, 3)
press(act, "b")
T.eq(act.session.carry, nil, "B cancels the carry")
T.eq(act.session.sparse[1][3] ~= nil, true, "the cancelled mon returned to its cell")

-- ------- deposit mode

-- seeded before the grid opens: the sparse layer snapshots at construction
game.save.boxes[1] = {}
game.save.party = {
  { species = "FIXMON_A", level = 10, hp = 20, dvs = {}, statExp = {}, moves = {},
    stats = { hp = 20, attack = 12, defense = 12, speed = 12, special = 12 } },
  { species = "FIXMON_B", level = 12, hp = 20, dvs = {}, statExp = {}, moves = {},
    stats = { hp = 20, attack = 12, defense = 12, speed = 12, special = 12 } },
}
local dep = openGrid(game, "DEPOSIT POKéMON")
game.save.currentBox = 1

T.eq(dep.mode, "deposit", "the DEPOSIT row opens the grid in deposit mode")
T.eq(dep.partyCursor, 1, "the party cursor starts on the first mon")

press(dep, "right")
T.eq(dep.partyCursor, 2, "right moves along the party row")
press(dep, "left")
T.eq(dep.partyCursor, 1, "left moves back along the party row")

-- up and down page the destination rather than moving the cursor
press(dep, "down")
T.eq(game.save.currentBox, 2, "down pages to the next destination box")
T.eq(dep.partyCursor, 1, "paging leaves the party cursor alone")
press(dep, "up")
T.eq(game.save.currentBox, 1, "up pages to the previous destination box")

-- drawing in deposit mode must not error
local okDep, depErr = pcall(function() dep:draw() end)
T.check(okDep, "drawing deposit mode succeeds: " .. tostring(depErr))

dep.partyCursor = 2
press(dep, "a")
T.eq(#game.save.party, 1, "A deposited the highlighted party mon")
T.eq(dep.session:count(1), 1, "the mon landed in the destination box")
T.eq(dep.session.sparse[1][1] ~= nil, true, "in its first free cell")
T.eq(dep.session.dirty, true, "depositing dirties the session")

-- B in deposit mode must return to the WITHDRAW/DEPOSIT menu, exactly as
-- B in box mode does -- not silently switch the grid over to box mode,
-- which would strand the player in the other half of the PC with no way
-- back to the menu except pressing B a second time.
local depPops = 0
dep.game = {
  data = Data,
  save = game.save,
  stack = { push = function() end, pop = function() depPops = depPops + 1 end },
  input = { queue = {}, down = {},
            wasPressed = function(self, b) return self.queue[b] or false end,
            isDown = function(self, b) return self.down[b] or false end },
}
press(dep, "b")
T.eq(depPops, 1, "B in deposit mode pops back to the menu")
T.eq(dep.mode, "deposit", "B does not switch the grid over to box mode")

-- ------- the screen must be opaque (issue: overworld and the kept-open PC
-- menu both drew through the box view)
-- src/core/StateStack.lua:44 picks the draw floor from `isOpaque`, and
-- src/core/Game.lua:407-409 keys the canvas clear off the same choice: an
-- opaque full-screen state gets the classic white clear, while a transparent
-- one lets the world pass show through.  Every comparable vanilla screen
-- (ListMenu, PartyMenu, SummaryMenu) sets it.
local StateStack = require("src.core.StateStack")

local opaqueGame = {
  data = Data,
  save = { party = {}, boxes = nil, currentBox = 1 },
  input = { wasPressed = function() return false end, isDown = function() return false end },
}
local st = setmetatable({}, { __index = StateStack })
st:init()
opaqueGame.stack = st

local overworld = { name = "overworld", draw = function() end }
st:push(overworld)
-- OverworldController opens the PC main menu with keepOpen, so it stays on
-- the stack underneath the sub-PC screen it pushes
st:push({ name = "pc_main_menu", draw = function() end })
local opaqueScreen = openGrid(opaqueGame, "WITHDRAW POKéMON")
st:push(opaqueScreen)

T.eq(opaqueScreen.isOpaque, true, "the box screen declares itself opaque")
T.eq(st:visibleBase(), 3, "the box screen is the draw floor, not the overworld")
T.check(st.states[st:visibleBase()] ~= overworld,
  "the overworld is not the visible base, so the canvas gets the white clear")

-- ------- the WITHDRAW / DEPOSIT menu is the entry point

local menuGame = {
  data = Data,
  save = { party = {}, boxes = nil, currentBox = 1 },
  stack = { push = function() end, pop = function() end },
  input = { wasPressed = function() return false end, isDown = function() return false end },
  writeSave = function() end,
}
local entry = Screens.get(menuGame, "BoxMenu").new(menuGame)
local rows = {}
for _, item in ipairs(entry.items or {}) do rows[#rows + 1] = item.label end
T.eq(table.concat(rows, ","), "WITHDRAW POKéMON,DEPOSIT POKéMON,SEE YA!",
  "the entry screen is the three-row withdraw/deposit menu")
T.eq(entry.items[1].keepOpen, true, "WITHDRAW keeps the menu underneath")
T.eq(entry.items[2].keepOpen, true, "DEPOSIT keeps the menu underneath")
T.check(not entry.items[3].keepOpen, "SEE YA! closes the menu")

local wGrid = openGrid(menuGame, "WITHDRAW POKéMON")
T.check(wGrid ~= nil, "WITHDRAW pushes the grid")
T.eq(wGrid.mode, "box", "WITHDRAW opens the grid in box mode")

local dGrid = openGrid(menuGame, "DEPOSIT POKéMON")
T.check(dGrid ~= nil, "DEPOSIT pushes the grid")
T.eq(dGrid.mode, "deposit", "DEPOSIT opens the grid in deposit mode")

-- SEE YA! and cancelling both commit, but only when something moved
local writes = 0
local exitGame = {
  data = Data,
  save = { party = {}, boxes = nil, currentBox = 1 },
  stack = { push = function() end, pop = function() end },
  input = { wasPressed = function() return false end, isDown = function() return false end },
  writeSave = function() writes = writes + 1 end,
}
local clean = Screens.get(exitGame, "BoxMenu").new(exitGame)
clean.items[3].onSelect()
T.eq(writes, 0, "SEE YA! on a browse-only session does not write")
-- With a change pending, SEE YA! no longer writes on the spot: it opens the
-- saving dialog, and the write lands on that dialog's onDone.  The full
-- sequence is asserted further down.
clean.session.dirty = true
clean.items[3].onSelect()
T.eq(writes, 0, "SEE YA! defers the write to the saving dialog")
T.check(type(clean.onCancel) == "function", "backing out of the menu also commits")

-- B in the grid returns to the menu instead of exiting the PC
local backGame = {
  data = Data,
  save = { party = {}, boxes = nil, currentBox = 1 },
  input = { wasPressed = function() return false end, isDown = function() return false end },
  writeSave = function() error("the grid must not write; the menu owns exit") end,
}
local popped = 0
backGame.stack = { push = function() end, pop = function() popped = popped + 1 end }
local backGrid = openGrid(backGame, "WITHDRAW POKéMON")
backGrid.session.dirty = true
backGame.input = { queue = {}, down = {},
  wasPressed = function(self, b) return self.queue[b] or false end,
  isDown = function(self, b) return self.down[b] or false end }
backGrid.game = backGame
press(backGrid, "b")
T.eq(popped, 1, "B in the grid pops back to the menu")

-- START no longer toggles deposit mode
local noToggle = openGrid(menuGame, "WITHDRAW POKéMON")
noToggle.game = { data = Data, save = menuGame.save,
  stack = { push = function() end, pop = function() end },
  input = { queue = {}, down = {},
            wasPressed = function(self, b) return self.queue[b] or false end,
            isDown = function(self, b) return self.down[b] or false end } }
press(noToggle, "start")
T.eq(noToggle.mode, "box", "START no longer switches to deposit mode")

-- ------- the frames must be drawn BEFORE their contents
-- Font.drawBox fills its whole rect white before drawing the border
-- (src/render/Font.lua:417-418), so a frame drawn after the header or the
-- grid erases it.  Spying on textured draws alone cannot prove this: the
-- headless fixture has no `icons` table, so drawIcon returns before ever
-- reaching love.graphics.draw and the assertion would vacuously pass.
-- Spy on Font.draw instead -- the header is text, and it is always drawn.
local Font = require("src.render.Font")
local gfx = love.graphics
local realRect, realFontDraw = gfx.rectangle, Font.draw
local calls = {}
gfx.rectangle = function(mode, x, y, w, h)
  calls[#calls + 1] = { kind = "fill", x = x, y = y, w = w, h = h }
  return realRect(mode, x, y, w, h)
end
Font.draw = function(...)
  calls[#calls + 1] = { kind = "text" }
  return realFontDraw(...)
end

local frameGame = {
  data = Data,
  save = { party = {}, boxes = nil, currentBox = 1 },
  stack = { push = function() end, pop = function() end },
  input = { wasPressed = function() return false end, isDown = function() return false end },
}
local frameGrid = openGrid(frameGame, "WITHDRAW POKéMON")
frameGame.save.boxes[1] = {
  { species = "FIXMON_A", level = 12, hp = 20, dvs = {}, statExp = {}, moves = {},
    stats = { hp = 20, attack = 12, defense = 12, speed = 12, special = 12 } },
}
calls = {}
frameGrid:draw()
gfx.rectangle, Font.draw = realRect, realFontDraw

local fills, firstText = {}, nil
for i, c in ipairs(calls) do
  if c.kind == "fill" then fills[#fills + 1] = { i = i, c = c }
  elseif not firstText then firstText = i end
end

T.check(#fills >= 2, "draw() paints both frame fills")
T.eq(("%d,%d,%d,%d"):format(fills[1].c.x, fills[1].c.y, fills[1].c.w, fills[1].c.h),
  "0,0,160,88", "box A covers the top of the screen")
T.eq(("%d,%d,%d,%d"):format(fills[2].c.x, fills[2].c.y, fills[2].c.w, fills[2].c.h),
  "0,80,160,64", "box B covers the bottom, sharing box A's border row")
T.check(firstText ~= nil, "the header is drawn, so this test is not vacuous")
T.check(fills[2].i < firstText,
  "both frames are filled before the first text is drawn over them")

-- deposit mode adds a third frame, and it must land with the others
local depFrameGame = {
  data = Data,
  save = { party = {
    { species = "FIXMON_A", level = 10, hp = 20, dvs = {}, statExp = {}, moves = {},
      stats = { hp = 20, attack = 12, defense = 12, speed = 12, special = 12 } },
    { species = "FIXMON_B", level = 12, hp = 20, dvs = {}, statExp = {}, moves = {},
      stats = { hp = 20, attack = 12, defense = 12, speed = 12, special = 12 } },
  }, boxes = nil, currentBox = 1 },
  stack = { push = function() end, pop = function() end },
  input = { wasPressed = function() return false end, isDown = function() return false end },
}
local depFrameGrid = openGrid(depFrameGame, "DEPOSIT POKéMON")
gfx.rectangle = function(mode, x, y, w, h)
  calls[#calls + 1] = { kind = "fill", x = x, y = y, w = w, h = h }
  return realRect(mode, x, y, w, h)
end
Font.draw = function(...)
  calls[#calls + 1] = { kind = "text" }
  return realFontDraw(...)
end
calls = {}
depFrameGrid:draw()
gfx.rectangle, Font.draw = realRect, realFontDraw

local dFills, dFirstText = {}, nil
for i, c in ipairs(calls) do
  if c.kind == "fill" then dFills[#dFills + 1] = { i = i, c = c }
  elseif not dFirstText then dFirstText = i end
end
T.check(#dFills >= 3, "deposit mode paints three frame fills")
T.eq(("%d,%d,%d,%d"):format(dFills[3].c.x, dFills[3].c.y, dFills[3].c.w, dFills[3].c.h),
  "0,112,160,32", "box C frames the party row at the bottom of the screen")
T.check(dFills[3].i < dFirstText,
  "the party frame is filled before any text is drawn over it")

-- ------- the cursor indicator
-- A 1px outline on the selected cell.  It must be drawn in BLACK: the
-- icons are painted during the white stage, and rectangle("line") uses the
-- current colour, so an outline drawn there would be white on white.
local function captureCursor(g, row, prep)
  local grid = openGrid(g, row)
  if prep then prep(grid) end
  local stubs, strokes = {}, 0
  local rRect, rSetColor = gfx.rectangle, gfx.setColor
  local current = { 1, 1, 1, 1 }
  gfx.setColor = function(r, gg, b, a)
    current = { r, gg, b, a }
    return rSetColor(r, gg, b, a)
  end
  gfx.rectangle = function(mode, x, y, w, h)
    if mode == "line" then
      strokes = strokes + 1
    elseif w <= 8 or h <= 8 then
      -- the frames fill 160px-wide rects; only cursor stubs are this small
      stubs[#stubs + 1] = { x = x, y = y, w = w, h = h,
                            dark = current[1] == 0 and current[2] == 0 }
    end
    return rRect(mode, x, y, w, h)
  end
  grid:draw()
  gfx.rectangle, gfx.setColor = rRect, rSetColor
  return grid, stubs, strokes
end

local curGame = {
  data = Data,
  save = { party = {}, boxes = nil, currentBox = 1 },
  stack = { push = function() end, pop = function() end },
  input = { wasPressed = function() return false end, isDown = function() return false end },
}
local curGrid, stubs, strokes = captureCursor(curGame, "WITHDRAW POKéMON",
  function(g)
    g.cursor = 7
    g.counter = 0
  end)

-- Stroked rects are the bug this replaced: rectangle("line") on integer
-- coords straddles pixel boundaries, and LOVE's default smooth line style
-- leaves partial-coverage greys.  PaletteFX buckets by red channel, so
-- those greys land in a lighter shade than black and the palette renders
-- them blue.  Every 160x144 screen in this engine fills instead.
T.eq(strokes, 0, "the cursor never uses a stroked rect")
T.eq(#stubs, 8, "the cursor is eight filled stubs, two per corner")

local ex, ey = L.slotXY(7)
local allDark, allInside = true, true
for _, st in ipairs(stubs) do
  if not st.dark then allDark = false end
  if st.x < ex or st.y < ey
     or st.x + st.w > ex + L.CELL or st.y + st.h > ey + L.CELL then
    allInside = false
  end
end
T.check(allDark, "every stub is drawn black, so it maps to the darkest shade")
T.check(allInside, "every stub stays inside the selected cell")

-- corners only: nothing is drawn across the middle of any edge
local mid = ex + L.CELL / 2
local touchesMiddle = false
for _, st in ipairs(stubs) do
  if st.x < mid and st.x + st.w > mid and st.h == 1 then touchesMiddle = true end
end
T.check(not touchesMiddle, "the edges are open in the middle, not a full square")

-- it follows the cursor
local _, moved = captureCursor(curGame, "WITHDRAW POKéMON", function(g)
  g.cursor = 20
  g.counter = 0
end)
local mx, my = L.slotXY(20)
T.eq(("%d,%d"):format(moved[1].x, moved[1].y), ("%d,%d"):format(mx, my),
  "the first stub anchors to the selected cell's top-left corner")

-- deposit mode outlines the party row instead
local depCurGame = {
  data = Data,
  save = { party = {
    { species = "FIXMON_A", level = 10, hp = 20, dvs = {}, statExp = {}, moves = {},
      stats = { hp = 20, attack = 12, defense = 12, speed = 12, special = 12 } },
    { species = "FIXMON_B", level = 12, hp = 20, dvs = {}, statExp = {}, moves = {},
      stats = { hp = 20, attack = 12, defense = 12, speed = 12, special = 12 } },
  }, boxes = nil, currentBox = 1 },
  stack = { push = function() end, pop = function() end },
  input = { wasPressed = function() return false end, isDown = function() return false end },
}
local _, depStubs = captureCursor(depCurGame, "DEPOSIT POKéMON", function(g)
  g.partyCursor = 2
  g.counter = 0
end)
local dx, dy = L.partyXY(2)
T.eq(("%d,%d"):format(depStubs[1].x, depStubs[1].y), ("%d,%d"):format(dx, dy),
  "deposit mode marks the highlighted party slot")

-- blinking off-phase hides it, but carrying keeps it solid
local _, offPhase = captureCursor(curGame, "WITHDRAW POKéMON", function(g)
  g.cursor = 1
  g.counter = 16
end)
T.eq(#offPhase, 0, "the cursor blinks off on the dark half of the cadence")

local _, carrying = captureCursor(curGame, "WITHDRAW POKéMON", function(g)
  g.cursor = 1
  g.counter = 16
  g.session.carry = { mon = {}, box = 1, slot = 1 }
end)
T.eq(#carrying, 8, "while carrying the cursor stays solid, marking the drop target")

-- ------- a carried Pokemon stays on the panel
-- pickUp removes the mon from the box, so reading the cell under the cursor
-- shows either nothing or -- worse -- whichever mon compacted into that
-- slot, which looks like you picked up the wrong one.  The carried mon is
-- what the player is manipulating, so it is what the panel describes.
local function monOfSpecies(sp, lvl)
  return { species = sp, level = lvl, hp = 20, dvs = {}, statExp = {}, moves = {},
           stats = { hp = 20, attack = 12, defense = 12, speed = 12, special = 12 } }
end

local carryGame = {
  data = Data,
  save = { party = {}, boxes = nil, currentBox = 1 },
  stack = { push = function() end, pop = function() end },
  input = { wasPressed = function() return false end, isDown = function() return false end },
}
-- the sparse layer snapshots the save at construction, so the box is
-- seeded before the grid opens
carryGame.save.boxes = {
  {
    monOfSpecies("FIXMON_A", 5),
    monOfSpecies("FIXMON_B", 10),
    monOfSpecies("FIXMON_C", 15),
  },
}
local carryGrid = openGrid(carryGame, "WITHDRAW POKéMON")

carryGrid.cursor = 2
T.eq(carryGrid:focused().species, "FIXMON_B", "the panel shows the mon under the cursor")

carryGrid.session:pickUp(1, 2)
T.eq(carryGrid.session.sparse[1][2], nil, "picking up opened a visible gap")
T.eq(carryGame.save.boxes[1][2].species, "FIXMON_B",
  "the packed layer is untouched until commit")
T.eq(carryGrid:focused().species, "FIXMON_B",
  "the panel still shows the CARRIED mon, not the gap under the cursor")

-- moving the cursor while carrying does not change what the panel shows
carryGrid.cursor = 5
T.eq(carryGrid:focused().species, "FIXMON_B",
  "the carried mon stays on the panel wherever the cursor goes")

-- and the panel goes back to reading the cell once the mon is placed
carryGrid.session:drop(1, 4)
T.eq(carryGrid.session.carry, nil, "the drop emptied the hand")
T.eq(carryGrid.session.sparse[1][4] ~= nil, true, "the mon took the free cell")
carryGrid.cursor = 1
T.eq(carryGrid:focused().species, "FIXMON_A",
  "with an empty hand the panel reads the cell again")

-- ------- the divider column between the grid and the sprite panel
-- Drawn with Font.BORDER.v, the same glyph the frames are built from, so
-- it reads as part of the chrome rather than a line laid over it.
local dividerGame = {
  data = Data,
  save = { party = {}, boxes = nil, currentBox = 1 },
  stack = { push = function() end, pop = function() end },
  input = { wasPressed = function() return false end, isDown = function() return false end },
}
local dividerGrid = openGrid(dividerGame, "WITHDRAW POKéMON")
local codes = {}
local realDrawCode = Font.drawCode
Font.drawCode = function(code, x, y)
  codes[#codes + 1] = { code = code, x = x, y = y }
  return realDrawCode(code, x, y)
end
dividerGrid:draw()
Font.drawCode = realDrawCode

local column = {}
for _, c in ipairs(codes) do
  if c.x == L.DIVIDER_X and c.code == Font.BORDER.v then column[#column + 1] = c end
end
T.eq(#column, L.DIVIDER_ROWS, "the divider is a full column of vertical border glyphs")
table.sort(column, function(a, b) return a.y < b.y end)
T.eq(column[1].y, L.DIVIDER_TOP, "it starts at box A's interior top")
T.eq(column[#column].y + L.ROW, (L.BOX_A_TILES[2] + L.BOX_A_TILES[4] - 1) * 8,
  "it ends at box A's interior floor, which the sprite now sits clear of")
local contiguous = true
for i = 2, #column do
  if column[i].y - column[i - 1].y ~= L.ROW then contiguous = false end
end
T.check(contiguous, "the column has no gaps")

-- ------- leaving the PC announces the save
-- The player should never have the game written under them silently.  This
-- is the engine's own SaveMenu .save sequence (src/ui/StartMenu.lua:70-86,
-- engine/menus/save.asm:164-181): a "Now saving..." page, the write on its
-- onDone, then a confirmation page with the save jingle.  Neither page
-- takes a button press.
local function exitWith(dirty, row)
  local writes, pushed = 0, {}
  local g = {
    data = Data,
    save = { party = {}, boxes = nil, currentBox = 1, player = { name = "RED" } },
    input = { wasPressed = function() return false end, isDown = function() return false end },
    writeSave = function() writes = writes + 1 end,
  }
  g.stack = { push = function(_, st) pushed[#pushed + 1] = st end,
              pop = function() end }
  local menu = Screens.get(g, "BoxMenu").new(g)
  menu.session.dirty = dirty
  if row == "cancel" then menu.onCancel() else menu.items[3].onSelect() end
  return g, menu, pushed, function() return writes end
end

-- nothing moved: no dialog, no write
local _, _, quietPushed, quietWrites = exitWith(false, "seeya")
T.eq(#quietPushed, 0, "a browse-only visit shows no save dialog")
T.eq(quietWrites(), 0, "and writes nothing")

-- something moved: the dialog appears BEFORE the write
local g1, _, pushed1, writes1 = exitWith(true, "seeya")
T.eq(#pushed1, 1, "SEE YA! after a change opens the saving dialog")
T.eq(writes1(), 0, "the write has not happened yet -- the dialog comes first")
T.check(pushed1[1].auto ~= nil, "the first page auto-advances, taking no button press")

-- advancing the first page performs the write and shows the confirmation
pushed1[1].onDone()
T.eq(writes1(), 1, "the write happens on the first page's onDone")
T.eq(#pushed1, 2, "and the confirmation page follows")
T.check(pushed1[2].auto ~= nil, "the confirmation also auto-advances")
T.eq(g1.save.player.name, "RED", "the confirmation names the player")

-- backing out of the menu announces it too
local _, _, pushed2, writes2 = exitWith(true, "cancel")
T.eq(#pushed2, 1, "backing out after a change also opens the dialog")
pushed2[1].onDone()
T.eq(writes2(), 1, "and writes once")

-- the session is clean afterwards, so a second exit does not write again
local _, menu3, pushed3, writes3 = exitWith(true, "seeya")
pushed3[1].onDone()
T.eq(writes3(), 1, "one write")
T.eq(menu3.session.dirty, false, "the session is clean after committing")

-- ------- dpad repeat
-- A held direction acts on the press frame, then after HELD_DELAY frames
-- again, then once every HELD_EVERY.  Every nav assertion above is a tap
-- and must behave exactly as before; this pins the hold cadence.  The two
-- constants below mirror main.lua's, which are closure locals.
local HELD_DELAY, HELD_EVERY = 20, 6
local rep = openGrid(game, "WITHDRAW POKéMON")
game.save.currentBox = 1
rep.cursor = 1

hold(rep, "right", 1, true)
T.eq(rep.cursor, 2, "the press frame acts at once")
hold(rep, "right", HELD_DELAY - 1)
T.eq(rep.cursor, 2, "a hold does not repeat inside the initial delay")
hold(rep, "right", 1)
T.eq(rep.cursor, 3, "the first repeat lands on the HELD_DELAY frame")
hold(rep, "right", HELD_EVERY)
T.eq(rep.cursor, 4, "and further repeats land every HELD_EVERY frames")

-- holding a direction at a grid edge pages one box per repeat, no faster
rep.cursor = 5
game.save.currentBox = 1
hold(rep, "right", 1, true)
T.eq(game.save.currentBox, 2, "the press frame at the edge pages once")
hold(rep, "right", HELD_DELAY - 1)
T.eq(game.save.currentBox, 2, "the hold delay applies to paging too")
hold(rep, "right", 1)
T.eq(rep.cursor, 2,
  "after the page the hold walks the new box in from its wrapped column")
T.eq(game.save.currentBox, 2,
  "and does not page again until the cursor reaches the far edge")

-- A held down opens its menu exactly once
local pushedA = {}
local heldGame = {
  data = Data,
  save = { party = {}, boxes = {
    { monOfSpecies("FIXMON_A", 5) },
  }, currentBox = 1 },
  stack = { push = function(_, st) pushedA[#pushedA + 1] = st end,
            pop = function() end },
  input = { queue = {}, down = {},
            wasPressed = function(self, b) return self.queue[b] or false end,
            isDown = function(self, b) return self.down[b] or false end },
}
local heldGrid = openGrid(heldGame, "WITHDRAW POKéMON")
heldGrid.cursor = 1
heldGame.input.queue = { a = true }
heldGame.input.down = { a = true }
heldGrid:update(1 / 60)
T.eq(#pushedA, 1, "A opens its menu on the press frame")
for _ = 1, 24 do
  heldGame.input.queue = {}
  heldGame.input.down = { a = true }
  heldGrid:update(1 / 60)
end
T.eq(#pushedA, 1, "and A held down never opens another")
heldGame.input.queue, heldGame.input.down = {}, {}

-- ------- the cursor survives the menu round-trip
local perGame = {
  data = Data,
  save = { party = {}, boxes = nil, currentBox = 1 },
  stack = { push = function() end, pop = function() end },
  input = { queue = {}, down = {},
            wasPressed = function(self, b) return self.queue[b] or false end,
            isDown = function(self, b) return self.down[b] or false end },
}
local perGrid, perMenu = openGrid(perGame, "WITHDRAW POKéMON")
press(perGrid, "down")
press(perGrid, "right")
T.eq(perGrid.cursor, 7, "the cursor moved two steps")
local reopened = {}
perGame.stack = { push = function(_, st) reopened[#reopened + 1] = st end,
                  pop = function() end }
perMenu.items[1].onSelect()
T.eq(reopened[1].cursor, 7, "a reopened grid resumes at the cursor it left off")

-- the party cursor comes back too, clamped to the party that is there
perGame.save.party = {
  monOfSpecies("FIXMON_A", 5), monOfSpecies("FIXMON_B", 6),
  monOfSpecies("FIXMON_C", 7),
}
local depPer, depPerMenu = openGrid(perGame, "DEPOSIT POKéMON")
press(depPer, "right")
press(depPer, "right")
T.eq(depPer.partyCursor, 3, "the party cursor moved to the last mon")
depPerMenu.session.partyCursor = 9
local depAgain = {}
perGame.stack = { push = function(_, st) depAgain[#depAgain + 1] = st end,
                  pop = function() end }
depPerMenu.items[2].onSelect()
T.eq(depAgain[1].partyCursor, 3,
  "a party cursor past the party clamps back to its end")

-- ------- the stats strip shows type, status and shininess
Data.pokemon.FIXMON_A = Data.pokemon.FIXMON_A or {}
Data.pokemon.FIXMON_A.types = { "NORMAL", "FLYING" }
local stripGame = {
  data = Data,
  save = { party = {}, boxes = {
    {
      { species = "FIXMON_A", level = 12, hp = 20,
        dvs = { attack = 15, defense = 10, speed = 10, special = 10 },
        statExp = {}, moves = {}, status = "PAR",
        stats = { hp = 20, attack = 12, defense = 12, speed = 12, special = 12 } },
    },
  }, currentBox = 1 },
  stack = { push = function() end, pop = function() end },
  input = { wasPressed = function() return false end,
            isDown = function() return false end },
}
local stripGrid = openGrid(stripGame, "WITHDRAW POKéMON")
stripGrid.counter = 0
local texts = {}
local realDraw = Font.draw
Font.draw = function(text, x, ty)
  texts[#texts + 1] = { text = tostring(text), x = x, y = ty }
  return realDraw(text, x, ty)
end
stripGrid:draw()
Font.draw = realDraw

local function drew(t)
  for _, d in ipairs(texts) do
    if d.text == t then return d end
  end
  return nil
end
T.check(drew("NORMAL/FLYING") ~= nil, "both types print on one slash-joined line")
T.check(drew("PAR") ~= nil, "the status condition prints")
T.check(drew("*") ~= nil, "a shiny DV spread prints the shiny mark")

-- a plain mon draws the type line but neither mark
stripGrid.session.sparse[1][1] = monOfSpecies("FIXMON_A", 5)
stripGrid.counter = 0
texts = {}
Font.draw = function(text, x, ty)
  texts[#texts + 1] = { text = tostring(text), x = x, y = ty }
  return realDraw(text, x, ty)
end
stripGrid:draw()
Font.draw = realDraw
T.check(drew("NORMAL/FLYING") ~= nil, "types still print for a plain mon")
T.check(drew("*") == nil, "no shiny mark without the DV spread")
T.check(drew("PAR") == nil, "no status without a condition")

-- and in deposit mode the type line stays hidden under box C
stripGame.save.party = { monOfSpecies("FIXMON_A", 5) }
stripGame.save.boxes[1] = {}
local depStrip = openGrid(stripGame, "DEPOSIT POKéMON")
texts = {}
Font.draw = function(text, x, ty)
  texts[#texts + 1] = { text = tostring(text), x = x, y = ty }
  return realDraw(text, x, ty)
end
depStrip:draw()
Font.draw = realDraw
T.check(drew("NORMAL/FLYING") == nil, "deposit mode hides the type line under box C")

-- ------- the screen declares its own palette zones
-- Without sgbPalettes the grid inherits the overworld's map palette through
-- the PC menu chain (src/ui/Menu declares none), so the icons colored with
-- wherever the player was standing when they opened the PC.  MEWMON
-- whole-screen is what ListMenu's generic full-screen menus get.  The
-- fixture dataset is ROM-free and ships no palette pack, so the test
-- injects the one palette the declaration names -- the same fallback path
-- PaletteFX.pack takes on a real load.
Data.palettes = Data.palettes or {}
Data.palettes.palettes = Data.palettes.palettes or {}
Data.palettes.palettes.MEWMON = Data.palettes.palettes.MEWMON
  or { { 255, 255, 255 }, { 170, 170, 170 }, { 85, 85, 85 }, { 0, 0, 0 } }
local palGame = {
  data = Data,
  save = { party = {}, boxes = nil, currentBox = 1 },
  stack = { push = function() end, pop = function() end },
  input = { wasPressed = function() return false end,
            isDown = function() return false end },
}
local palGrid = openGrid(palGame, "WITHDRAW POKéMON")
local zones = palGrid:sgbPalettes(palGame)
local expected = require("src.render.PaletteFX").wholeNamed(Data, "MEWMON")
T.check(zones ~= nil, "the grid declares palette zones")
T.eq(#zones, #expected, "one whole-screen zone, like ListMenu's generic")
T.eq(zones[1].x, 0, "the zone starts at the canvas edge")
T.eq(zones[1].w, 160, "the zone spans the full canvas width")

run.release()
Screens.invalidate()
T.finish("bills_pc_plus")
