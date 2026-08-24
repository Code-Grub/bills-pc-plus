-- Replaces the Bill's PC storage screen (src/ui/BoxMenu.lua) with a grid.
-- The screen id is claimed through the registry, so every PC entry point
-- resolves here instead of to the builtin.
--
-- A mod cannot require its own files, so the two sibling modules load
-- through mod:read + load, the same way example_jukebox loads its song.

local Font = require("src.render.Font")
local PartyMenu = require("src.ui.PartyMenu")
local Sprites = require("src.pokemon.Sprites")
local Boxes = require("src.pokemon.Boxes")
local Stats = require("src.pokemon.Stats")
local TypeChart = require("src.battle.TypeChart")
local PaletteFX = require("src.render.PaletteFX")

return function(mod)
  local function sibling(name)
    local source = mod:read(name)
    if not source then
      mod.log:error("%s missing from %s -- reinstall the mod", name, mod.path)
      return nil
    end
    local chunk, compileErr = load(source, "@" .. mod.path .. "/" .. name)
    if not chunk then
      mod.log:error("%s did not compile: %s", name, tostring(compileErr))
      return nil
    end
    local ok, result = pcall(chunk)
    if not ok then
      mod.log:error("%s failed to load: %s", name, tostring(result))
      return nil
    end
    return result
  end

  local BoxSession = sibling("BoxSession.lua")
  local Layout = sibling("Layout.lua")
  if not (BoxSession and Layout) then return end

  local Screen = {}
  Screen.__index = Screen

  -- A full-screen state, so it owns the frame.  src/core/StateStack.lua:44
  -- picks the draw floor from this flag, and src/core/Game.lua:407-409 keys
  -- the canvas clear off the same choice: opaque gets the classic white
  -- clear, transparent lets the overworld's world pass show through.
  -- Without it the map AND the PC main menu -- which OverworldController
  -- keeps on the stack with keepOpen (#695) -- both drew through the grid.
  -- Every comparable vanilla screen sets it: ListMenu.lua:12,
  -- PartyMenu.lua:24, SummaryMenu.lua:20.  Vanilla BoxMenu did not need it
  -- because it was a small 14x12 bordered Menu drawn deliberately over the
  -- PC menu; this replacement is full-screen.
  Screen.isOpaque = true

  -- SGB: the grid declares its own palette instead of inheriting one.
  -- Neither the WITHDRAW/DEPOSIT menu nor the PC main menu beneath it
  -- declare zones (src/ui/Menu has no sgbPalettes), so without this the
  -- zone walk falls through to the overworld, and the icons -- grayscale
  -- art awaiting a zone -- colored with the palette of whatever map the
  -- player was standing on when they opened the PC.  MEWMON whole-screen
  -- is what ListMenu's generic full-screen menus get (SET_PAL_GENERIC)
  -- and the palette the engine already trusts for mon icons: the party
  -- screen's icon column is MEWMON too.
  function Screen:sgbPalettes(game)
    return PaletteFX.wholeNamed(game.data, "MEWMON")
  end

  -- The mon the panel and stats strip describe: whatever the cursor is on,
  -- or in deposit mode, whichever party member is highlighted.
  function Screen:focused()
    -- A carried mon has been removed from its box by pickUp, so the cell
    -- under the cursor now holds either nothing or whichever mon compacted
    -- into that slot.  Showing the first blanks the panel mid-move; showing
    -- the second is worse, because it looks like a different Pokemon was
    -- picked up.  What the player is manipulating is the one in hand.
    --
    -- Checked before the mode, so it holds even if deposit mode ever
    -- becomes reachable while carrying.
    if self.session.carry then return self.session.carry.mon end
    if self.mode == "deposit" then
      return self.session.save.party[self.partyCursor]
    end
    return self.session:box()[self.cursor]
  end

  local function drawHeader(self)
    local n = self.session.save.currentBox
    -- Vertical arrows in deposit mode signal that up/down now page the
    -- destination box instead of the horizontal grid-cursor paging.
    local fmt = self.mode == "deposit" and "^BOX %2dv" or "<BOX %2d>"
    Font.draw(fmt:format(n), Layout.HEADER_X, Layout.HEADER_Y)
    -- right-aligned inside the frame: 5 glyphs ending at the interior edge
    -- count() not #: a sparse box holds nils, so # is meaningless
    Font.draw(("%2d/%2d"):format(self.session:count(), Boxes.CAPACITY),
              112, Layout.HEADER_Y)
  end

  -- A built-in icon draws exactly 16x16, but a mod-supplied image draws
  -- whole, at whatever size the file is (src/ui/PartyMenu.lua:240-242), so
  -- an icon pack shipping 32x32 art would bleed over its neighbours.
  -- Scissor each cell rather than trusting the source.
  --
  -- selected=false on purpose: with it true, drawIcon reads mon.stats.hp
  -- (PartyMenu.lua:211) to pick an animation speed from HP bar colour,
  -- which is meaningless for a stored mon.  forceAlt animates instead.
  local function drawIconClamped(self, mon, x, y, animated)
    love.graphics.setScissor(x, y, Layout.CELL, Layout.CELL)
    PartyMenu.drawIcon(self.game, mon, x, y, false, 0, animated)
    love.graphics.setScissor()
  end

  local function blink(self)
    return math.floor(self.counter / 16) % 2 == 1
  end

  -- Dpad key repeat: a direction acts on the frame it is pressed, then,
  -- after HELD_DELAY frames of being held, once every HELD_EVERY.  The grid
  -- is 20 cells and Kanto is 12 boxes wide; walking either on single taps
  -- is the mod's worst daily grind, and the Game Boy pad has no shoulder
  -- button to page with (src/core/Input.lua:9-21), so the hold is the
  -- pager.  A and B stay on wasPressed: drops and menus must never repeat.
  local HELD_DELAY = 20
  local HELD_EVERY = 6

  -- Returns the direction to act on this frame, or nil.  The press edge
  -- comes from wasPressed, not isDown: a tap can be pressed and released
  -- inside one step, so the frame that acts may already read as up.  The
  -- hold cadence then rides isDown from the direction the edge named.  Two
  -- held directions resolve by check order, up and left first, which only
  -- matters on a touch d-pad's diagonals.
  local function heldDirection(self, input)
    local pressed
    for _, d in ipairs({ "up", "down", "left", "right" }) do
      if input:wasPressed(d) then pressed = d break end
    end
    if pressed then
      self.heldDir = pressed
      self.heldCount = 0
      self.heldFired = false
      return pressed
    end
    local held
    for _, d in ipairs({ "up", "down", "left", "right" }) do
      if input:isDown(d) then held = d break end
    end
    if held ~= self.heldDir then
      -- released, or switched, with no edge this frame: reset the cadence
      self.heldDir = held
      self.heldCount = 0
      self.heldFired = false
      return nil
    end
    if not held then return nil end
    self.heldCount = self.heldCount + 1
    local due = self.heldFired and HELD_EVERY or HELD_DELAY
    if self.heldCount >= due then
      self.heldFired = true
      self.heldCount = 0
      return held
    end
    return nil
  end

  local function drawGrid(self)
    local box = self.session:box()
    for i = 1, Layout.COLS * Layout.ROWS do
      local mon = box[i]
      if mon then
        local x, y = Layout.slotXY(i)
        drawIconClamped(self, mon, x, y,
          self.mode == "box" and i == self.cursor and blink(self) or false)
      end
    end
  end

  local function drawPanel(self)
    local mon = self:focused()
    if not mon then return end
    local path, trueColor = Sprites.path(self.game.data, mon.species, "front",
      { mon = mon, kind = "summary" })
    if path then
      if self.spritePath ~= path then
        local ok, img = pcall(love.graphics.newImage, path)
        self.sprite = ok and img or nil
        self.spriteTrueColor = self.sprite and trueColor or false
        self.spritePath = path
      end
      if self.sprite then
        local pw, ph = self.sprite:getDimensions()
        local px = Layout.SPRITE_CX - math.floor(pw / 2)
        local py = Layout.SPRITE_BASELINE - ph
        -- SummaryMenu draws the front pic mirrored; sx = -1 anchored at the
        -- block's right edge lands it on px..px+pw
        love.graphics.draw(self.sprite, px + pw, py, 0, -1, 1)
        if self.spriteTrueColor then
          PaletteFX.markTrueColor(px, py, pw, ph)
        end
      end
    end
    -- Identity plate: the name and level ride above the sprite instead of
    -- heading the stats strip.  The plate is white on white wherever the
    -- sprite is short of it, and only bites where a tall sprite reaches
    -- up under it; the scissor keeps the chrome clean.
    --
    -- A name wider than the panel marquees rather than clipping: it holds
    -- its start, slides left until the tail shows, holds, and slides back.
    -- Ping-pong on the frame counter, so it carries no state and restarts
    -- with the screen.
    local MARQUEE_HOLD = 90
    local MARQUEE_EVERY = 5
    local nameText = self.session:nameOf(mon)
    local levelText = (":L%d"):format(mon.level or 1)
    local nameW, levelW = #nameText * 8, #levelText * 8
    local plateW = math.min(Layout.PANEL_W, math.max(nameW, levelW) + 4)
    local nameX
    if nameW > Layout.PANEL_W then
      plateW = Layout.PANEL_W
      local travel = nameW - Layout.PANEL_W
      local scroll = travel * MARQUEE_EVERY
      local loop = MARQUEE_HOLD + scroll + MARQUEE_HOLD + scroll
      local t = self.counter % loop
      local dx = 0
      if t < MARQUEE_HOLD then
        dx = 0
      elseif t < MARQUEE_HOLD + scroll then
        dx = math.floor((t - MARQUEE_HOLD) / MARQUEE_EVERY)
      elseif t < MARQUEE_HOLD + scroll + MARQUEE_HOLD then
        dx = travel
      else
        dx = travel - math.floor((t - MARQUEE_HOLD - scroll - MARQUEE_HOLD)
          / MARQUEE_EVERY)
      end
      nameX = Layout.PANEL_X - dx
    else
      nameX = Layout.SPRITE_CX - math.floor(nameW / 2)
    end
    love.graphics.setScissor(Layout.PANEL_X, Layout.PLATE_Y,
                             Layout.PANEL_W, 16)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.rectangle("fill", Layout.SPRITE_CX - math.floor(plateW / 2),
      Layout.PLATE_Y, plateW, 16)
    love.graphics.setColor(0, 0, 0, 1)
    Font.draw(nameText, nameX, Layout.PLATE_Y)
    Font.draw(levelText, Layout.SPRITE_CX - math.floor(levelW / 2),
      Layout.PLATE_Y + 8)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setScissor()
  end

  local function drawStats(self)
    local mon = self:focused()
    if not mon then return end
    local y, row = Layout.STATS_Y, Layout.ROW
    local x, x2 = Layout.STATS_X, Layout.STATS_X + 80
    -- Right end of the HP row: the shiny mark, then the status condition.
    -- Both are storage facts the vanilla PC never showed -- a mon keeps its
    -- status through storage, and a shiny is invisible until you already
    -- know its DVs.  The mark is a drawn diamond rather than a text glyph:
    -- the font carries no star, and a filled shape reads as a sparkle at
    -- this resolution the way the cursor's filled stubs do.  "OK" is the
    -- no-condition value, not worth ink.
    if Stats.isShiny(mon.dvs) then
      local mx, my = 120, y + 3
      love.graphics.rectangle("fill", mx + 2, my, 1, 1)
      love.graphics.rectangle("fill", mx, my + 1, 5, 1)
      love.graphics.rectangle("fill", mx + 2, my + 2, 1, 1)
    end
    if mon.status and mon.status ~= "OK" then
      Font.draw(mon.status, 128, y)
    end
    local stats = mon.stats
    if stats then
      Font.draw(("HP  %3d/%3d"):format(mon.hp or 0, stats.hp or 0), x, y)
      Font.draw(("ATK %3d"):format(stats.attack or 0), x, y + row)
      Font.draw(("DEF %3d"):format(stats.defense or 0), x2, y + row)
      Font.draw(("SPD %3d"):format(stats.speed or 0), x, y + row * 2)
      Font.draw(("SPC %3d"):format(stats.special or 0), x2, y + row * 2)
    end
    -- The type line sits under SPD/SPC.  Deposit mode's party frame (box C)
    -- covers this row, so it is box view's bonus row -- the frame, not a
    -- row count, decides whether it shows.  Display names go through
    -- TypeChart for the same reason SummaryMenu does: PSYCHIC's stored
    -- constant would print as "PSYCHIC_TYPE" (#214).
    if self.mode ~= "deposit" then
      local def = self.session.data.pokemon[mon.species]
      local t = def and def.types
      if t and t[1] then
        local line = TypeChart.displayName(t[1])
        if t[2] then
          line = line .. "/" .. TypeChart.displayName(t[2])
        end
        Font.draw(line, x, y + row * 3)
      end
    end
  end

  -- Bill's PC runs silent end to end (BIT_NO_MENU_BUTTON_SOUND,
  -- engine/menus/pokemon_pc.asm), so every menu this screen opens is noSound.
  local function openCursorMenu(self)
    local slot = self.cursor
    local mon = self.session:box()[slot]
    if not mon then return end
    local box = self.session.save.currentBox
    local items = {
      { label = "MOVE", onSelect = function()
          self.session:pickUp(box, slot)
        end },
      { label = "WITHDRAW", onSelect = function()
          local ok, reason = self.session:withdraw(box, slot)
          if not ok then self:say(reason) end
        end },
      { label = "STATS", keepOpen = true, onSelect = function()
          mod.ui.push(self.game, "SummaryMenu", mon)
        end },
      { label = "RELEASE", onSelect = function()
          self.game.stack:push(mod.ui.TextBox.new(self.game,
            ("Once released,\n%s is\ngone forever. OK?")
              :format(self.session:nameOf(mon)), nil, {
            defaultNo = true, noSound = true,
            choice = function(yes)
              if yes then self.session:release(box, slot) end
            end,
          }))
        end },
      { label = "CANCEL" },
    }
    self.game.stack:push(mod.ui.Menu.new(self.game, items,
      { tx = 5, ty = 6, tw = 11, th = 12, noSound = true }))
  end

  local REFUSALS = {
    party_full = "You can't take\nany more POKéMON.\fDeposit POKéMON\nfirst.",
    box_full = "Oops! This Box is\nfull of POKéMON.",
    last_mon = "You can't deposit\nthe last POKéMON!",
    no_mon = "What? There are\nno POKéMON here!",
    storage_full = "There is no room\nleft in storage!",
  }

  function Screen:say(reason)
    local text = REFUSALS[reason]
    if text then
      self.game.stack:push(mod.ui.TextBox.new(self.game, text))
    end
  end

  -- The deposit-mode branch of Screen:update: left/right walk the party
  -- row (what to deposit), up/down page the destination box (where it
  -- goes), A deposits, B leaves deposit mode.
  local function updateDeposit(self, input)
    local party = self.session.save.party
    if input:wasPressed("b") then
      -- Back to the WITHDRAW/DEPOSIT menu, the same exit box mode takes.
      -- Switching self.mode over to "box" here instead would drop the
      -- player into the withdraw half of the PC without them choosing it,
      -- and leave the menu one extra B press away.
      self.game.stack:pop()
    elseif input:wasPressed("a") then
      local ok, reason = self.session:deposit(self.partyCursor,
                                              self.session.save.currentBox)
      if not ok then
        self:say(reason)
      elseif self.partyCursor > #party then
        self.partyCursor = math.max(1, #party)
      end
    else
      -- Left/right walk the party row (what to deposit); up/down page the
      -- destination box (where it goes).  Both repeat on hold, which is
      -- mostly the paging's win: the destination is 12 boxes away in each
      -- direction.
      local d = heldDirection(self, input)
      if d == "left" and self.partyCursor > 1 then
        self.partyCursor = self.partyCursor - 1
      elseif d == "right" and self.partyCursor < #party then
        self.partyCursor = self.partyCursor + 1
      elseif d == "up" then
        self.session:pageBox(-1)
      elseif d == "down" then
        self.session:pageBox(1)
      end
    end
  end

  -- The box-view branch of Screen:update, once START/deposit has already
  -- been ruled out: A drops or opens the cursor menu, B cancels a carry or
  -- exits, and anything else is grid-cursor movement with edge paging.
  --
  -- Edge paging is how a carried mon crosses a box boundary, and it costs
  -- no buttons: the Game Boy pad has no L or R (src/core/Input.lua:9-21).
  local function updateBoxMode(self, input)
    if input:wasPressed("a") then
      if self.session.carry then
        local ok, reason = self.session:drop(self.session.save.currentBox,
                                             self.cursor)
        if not ok then self:say(reason) end
      else
        openCursorMenu(self)
      end
      return
    end

    if input:wasPressed("b") then
      if self.session.carry then
        local ok, reason = self.session:cancelCarry()
        if not ok then self:say(reason) end
      else
        -- Back to the WITHDRAW/DEPOSIT menu, which is still on the stack
        -- beneath us because its rows carry keepOpen.  The grid never
        -- commits: the menu owns every exit from the PC, so there is one
        -- place the save can be written rather than two.
        self.game.stack:pop()
      end
      return
    end

    local d = heldDirection(self, input)
    if d then
      local col = (self.cursor - 1) % Layout.COLS
      local row = math.floor((self.cursor - 1) / Layout.COLS)

      if d == "up" and row > 0 then
        row = row - 1
      elseif d == "down" and row < Layout.ROWS - 1 then
        row = row + 1
      elseif d == "left" then
        if col > 0 then
          col = col - 1
        else
          self.session:pageBox(-1)
          col = Layout.COLS - 1
        end
      elseif d == "right" then
        if col < Layout.COLS - 1 then
          col = col + 1
        else
          self.session:pageBox(1)
          col = 0
        end
      end

      self.cursor = Layout.slotAt(col, row)
    end
  end

  function Screen:update(dt)
    self.counter = self.counter + 1
    local input = self.game.input

    if self.mode == "deposit" then
      updateDeposit(self, input)
    else
      updateBoxMode(self, input)
    end

    -- The session outlives each grid push, so it is where the cursor lives
    -- between visits: newGrid reads it back, and writing it every frame
    -- here needs no exit hook.  Re-entering WITHDRAW puts you where you
    -- left, the way the vanilla screen remembers its cursor.
    self.session.cursor = self.cursor
    self.session.partyCursor = self.partyCursor
  end

  -- Draws the party as a row of icons in the 16px gap between the grid and
  -- the stats strip.  The icons are real colour art, so this must only ever
  -- be called from the white stage of Screen:draw, same as drawGrid and
  -- drawPanel -- calling it from a black stage would flatten the icons to
  -- solid black silhouettes (see the comment on Screen:draw).  Only the
  -- "PARTY" label is text, so it alone is bracketed back to black and
  -- restored to white, keeping the icons untinted.
  local function drawPartyRow(self)
    local party = self.session.save.party
    for i = 1, Layout.PARTY_SLOTS do
      local mon = party[i]
      if mon then
        local x, y = Layout.partyXY(i)
        drawIconClamped(self, mon, x, y, i == self.partyCursor and blink(self))
      end
    end
    love.graphics.setColor(0, 0, 0, 1)
    Font.draw("PARTY", Layout.PARTY_X + 6 * Layout.CELL + 8, Layout.PARTY_Y + 4)
    love.graphics.setColor(1, 1, 1, 1)
  end

  -- The cursor indicator: a 1px outline on the selected cell.
  --
  -- Drawn in BLACK, and deliberately not inside the white stage that paints
  -- the icons.  rectangle("line") fills with the current colour rather than
  -- sampling a texture, so an outline drawn while white is active would be
  -- white on a white background -- invisible, and invisible in exactly the
  -- way the icon-tinting bug was.
  --
  -- Blinks on the same 16-frame cadence as the icon animation, except while
  -- carrying: then it holds solid, because the player is looking for
  -- somewhere to put a Pokemon and the steady outline marks where it lands.
  -- On for the FIRST half of each cadence, unlike the icon animation: the
  -- cursor should be visible the instant the screen opens (counter 0), not
  -- 16 frames later.
  local function cursorOn(self)
    return self.session.carry ~= nil
      or math.floor(self.counter / 16) % 2 == 0
  end

  local function drawCursor(self)
    if not cursorOn(self) then return end
    local x, y
    if self.mode == "deposit" then
      x, y = Layout.partyXY(self.partyCursor)
    else
      x, y = Layout.slotXY(self.cursor)
    end

    local r, g, b, a = love.graphics.getColor()
    love.graphics.setColor(0, 0, 0, 1)
    -- Filled 1px stubs, never rectangle("line").  A stroked rect on integer
    -- coordinates straddles pixel boundaries, and LOVE's default smooth
    -- line style leaves partial-coverage greys behind; PaletteFX buckets by
    -- red channel, so those greys land in a lighter shade than black and
    -- the active palette renders them as a colour rather than black.  Every
    -- 160x144 screen in this engine fills for the same reason -- the one
    -- stroked rect, src/ui/Diploma.lua:31, offsets by half a pixel to dodge
    -- it.  Fills on whole pixels need no such trick.
    local c, arm = Layout.CELL, Layout.CURSOR_ARM
    local far = c - arm          -- start of the far-side arms
    local edge = c - 1           -- last pixel column/row of the cell
    local rect = love.graphics.rectangle
    -- top-left, top-right, bottom-left, bottom-right
    rect("fill", x,        y,        arm, 1)
    rect("fill", x,        y,        1,   arm)
    rect("fill", x + far,  y,        arm, 1)
    rect("fill", x + edge, y,        1,   arm)
    rect("fill", x,        y + edge, arm, 1)
    rect("fill", x,        y + far,  1,   arm)
    rect("fill", x + far,  y + edge, arm, 1)
    rect("fill", x + edge, y + far,  1,   arm)
    love.graphics.setColor(r, g, b, a)
  end

  -- The divider between the grid and the sprite panel, drawn with the same
  -- vertical glyph the frames are built from (Font.BORDER.v) so it reads as
  -- part of the chrome rather than a rule laid over it.  Box A's interior
  -- is 144px and the grid takes 80, so this column's tile is the 8px the
  -- panel gave up -- see Layout.PANEL_W.
  local function drawDivider()
    local x, y0 = Layout.DIVIDER_X, Layout.DIVIDER_TOP
    for i = 0, Layout.DIVIDER_ROWS - 1 do
      Font.drawCode(Font.BORDER.v, x, y0 + i * Layout.ROW)
    end
  end

  function Screen:draw()
    -- The two frames go down FIRST, before any content: Font.drawBox fills
    -- its whole rect white before drawing the border (src/render/Font.lua
    -- :417-418), so anything already painted underneath is erased.  Box B
    -- second, sharing row 10 with box A's bottom border, which is how
    -- adjacent boxes meet in the original.  drawBox restores the caller's
    -- colour after its fill and its border glyphs are tiles, so it is safe
    -- to call with black active.
    love.graphics.setColor(0, 0, 0, 1)
    Font.drawBox(unpack(Layout.BOX_A_TILES))
    Font.drawBox(unpack(Layout.BOX_B_TILES))
    -- Box C sits over box B's lower rows, so it goes down after it and
    -- still before any content.  It does not reach the header, but keeping
    -- every frame in one place is the rule that stops the next edit from
    -- painting a frame over something.
    if self.mode == "deposit" then
      Font.drawBox(unpack(Layout.BOX_C_TILES))
    end
    drawDivider()

    drawHeader(self)
    -- Glyph tiles are pre-baked black on transparent (src/render/Font.lua
    -- :408-411), so black draws text fine, but drawGrid/drawPanel paint
    -- real colour art (icons, the front sprite): love.graphics.draw tints
    -- by multiplying texture RGB against the active colour, so drawing
    -- them at (0,0,0,1) would flatten them to solid black.  White first,
    -- matching src/ui/PartyMenu.lua:715-717.
    love.graphics.setColor(1, 1, 1, 1)
    drawGrid(self)
    drawPanel(self)
    if self.mode == "deposit" then
      drawPartyRow(self)
    end
    drawCursor(self)

    love.graphics.setColor(0, 0, 0, 1)
    drawStats(self)
    love.graphics.setColor(1, 1, 1, 1)
  end

  -- The grid is no longer the entry point: a menu row pushes it, in the
  -- mode that row names.  Both rows share one session, so a withdrawal and
  -- a deposit in the same PC visit accumulate into a single dirty flag and
  -- a single write on the way out.
  local function newGrid(game, session, mode)
    -- The cursor comes from the session, where Screen:update kept it, so a
    -- grid reopened from the menu resumes where the last one stood.
    -- partyCursor clamps to the party actually there: deposits shrink it
    -- between visits.
    local partyCursor = session.partyCursor or 1
    local count = #session.save.party
    if partyCursor > count then partyCursor = count end
    if partyCursor < 1 then partyCursor = 1 end
    return setmetatable({
      game = game,
      session = session,
      cursor = session.cursor or 1,
      partyCursor = partyCursor,
      mode = mode,
      counter = 0,
      heldDir = nil,
      heldCount = 0,
      heldFired = false,
    }, Screen)
  end

  -- The entry screen is the withdraw/deposit menu, the same shape vanilla
  -- src/ui/BoxMenu.lua returns.  WITHDRAW and DEPOSIT carry keepOpen so the
  -- menu stays on the stack beneath the grid (src/ui/Menu.lua:93); B in the
  -- grid then pops back here for free, and that is how the player switches
  -- between the two modes.  Because the menu outlives the grid it is also
  -- the only place the save is committed -- via SEE YA! or by backing out.
  mod.content.screens:register("BoxMenu", {
    new = function(game)
      local session = BoxSession.new(game)
      -- Leaving with something changed announces the write rather than
      -- doing it silently.  This is the engine's own SaveMenu .save
      -- sequence (src/ui/StartMenu.lua:70-86, engine/menus/save.asm
      -- :164-181): a "Now saving..." page held on a timer, the write on its
      -- onDone, then a confirmation page with the save jingle.  Neither
      -- page takes a button press, matching how SAVE behaves from the
      -- START menu, so the player reads the same thing in both places.
      local function commitWithNotice()
        if not session.dirty then return end
        game.stack:push(mod.ui.TextBox.new(game, "Now saving...", function()
          session:commit()
          local who = (game.save.player and game.save.player.name) or "RED"
          game.stack:push(mod.ui.TextBox.new(game,
            ("%s saved\nthe game!"):format(who), nil, {
            auto = {
              sound = function()
                return require("src.core.Sound").play(game.data, "Save")
              end,
              delay = 30,
            },
          }))
        end, { auto = { delay = 120 } }))
      end

      local menu = mod.ui.Menu.new(game, {
        { label = "WITHDRAW POKéMON", keepOpen = true, onSelect = function()
            game.stack:push(newGrid(game, session, "box"))
          end },
        { label = "DEPOSIT POKéMON", keepOpen = true, onSelect = function()
            game.stack:push(newGrid(game, session, "deposit"))
          end },
        { label = "SEE YA!", onSelect = commitWithNotice },
      }, {
        tx = 0, ty = 0, th = 8,
        -- Bill's PC runs silent end to end (BIT_NO_MENU_BUTTON_SOUND,
        -- engine/menus/pokemon_pc.asm)
        noSound = true,
        onCancel = commitWithNotice,
      })
      -- the session outlives each grid push, so expose it on the menu
      menu.session = session
      return menu
    end,
  })
end
