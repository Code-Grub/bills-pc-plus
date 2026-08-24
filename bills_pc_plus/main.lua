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
    Font.draw(("%2d/%2d"):format(#self.session:box(), Boxes.CAPACITY),
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
    if not path then return end
    if self.spritePath ~= path then
      local ok, img = pcall(love.graphics.newImage, path)
      self.sprite = ok and img or nil
      self.spriteTrueColor = self.sprite and trueColor or false
      self.spritePath = path
    end
    if not self.sprite then return end
    local pw, ph = self.sprite:getDimensions()
    local px = Layout.SPRITE_CX - math.floor(pw / 2)
    local py = Layout.SPRITE_BASELINE - ph
    -- SummaryMenu draws the front pic mirrored; sx = -1 anchored at the
    -- block's right edge lands it on px..px+pw
    love.graphics.draw(self.sprite, px + pw, py, 0, -1, 1)
    if self.spriteTrueColor then
      require("src.render.PaletteFX").markTrueColor(px, py, pw, ph)
    end
  end

  local function drawStats(self)
    local mon = self:focused()
    if not mon then return end
    local y, row = Layout.STATS_Y, Layout.ROW
    local x, x2 = Layout.STATS_X, Layout.STATS_X + 80
    -- Deposit mode puts box C over the fourth row, so stop one short
    -- rather than drawing text that the frame is about to cover.
    local rows = self.mode == "deposit"
      and Layout.STATS_ROWS_DEPOSIT or Layout.STATS_ROWS_BOX
    local stats = mon.stats
    Font.draw(self.session:nameOf(mon), x, y)
    Font.draw((":L%d"):format(mon.level or 1), 112, y)
    if not stats then return end
    Font.draw(("HP  %3d/%3d"):format(mon.hp or 0, stats.hp or 0), x, y + row)
    Font.draw(("ATK %3d"):format(stats.attack or 0), x, y + row * 2)
    Font.draw(("DEF %3d"):format(stats.defense or 0), x2, y + row * 2)
    if rows >= 4 then
      Font.draw(("SPD %3d"):format(stats.speed or 0), x, y + row * 3)
      Font.draw(("SPC %3d"):format(stats.special or 0), x2, y + row * 3)
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
    elseif input:wasPressed("left") and self.partyCursor > 1 then
      self.partyCursor = self.partyCursor - 1
    elseif input:wasPressed("right") and self.partyCursor < #party then
      self.partyCursor = self.partyCursor + 1
    elseif input:wasPressed("up") then
      self.session:pageBox(-1)
    elseif input:wasPressed("down") then
      self.session:pageBox(1)
    elseif input:wasPressed("a") then
      local ok, reason = self.session:deposit(self.partyCursor,
                                              self.session.save.currentBox)
      if not ok then
        self:say(reason)
      elseif self.partyCursor > #party then
        self.partyCursor = math.max(1, #party)
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

    local col = (self.cursor - 1) % Layout.COLS
    local row = math.floor((self.cursor - 1) / Layout.COLS)

    if input:wasPressed("up") and row > 0 then
      row = row - 1
    elseif input:wasPressed("down") and row < Layout.ROWS - 1 then
      row = row + 1
    elseif input:wasPressed("left") then
      if col > 0 then
        col = col - 1
      else
        self.session:pageBox(-1)
        col = Layout.COLS - 1
      end
    elseif input:wasPressed("right") then
      if col < Layout.COLS - 1 then
        col = col + 1
      else
        self.session:pageBox(1)
        col = 0
      end
    end

    self.cursor = Layout.slotAt(col, row)
  end

  function Screen:update(dt)
    self.counter = self.counter + 1
    local input = self.game.input

    if self.mode == "deposit" then
      updateDeposit(self, input)
      return
    end

    updateBoxMode(self, input)
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
    return setmetatable({
      game = game,
      session = session,
      cursor = 1,
      partyCursor = 1,
      mode = mode,
      counter = 0,
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
