-- Talking to your follower: face it, press A.
--
--   1. REPORT  -- a message with the lead Pokemon's portrait, its face and its
--                 words taken from its real state (HP, status, friendship:
--                 lib/mon_mood.lua + lib/follower_dialogue.lua).
--   2. MENU    -- once that text is fully typed, the engine's own choice menu
--                 opens under it: Interact (Pet / Play / Talk) /
--                 Role (Follow / Forage / Fight) / Recall / Cancel.
--   3. SCENE   -- the follower acts it out (lib/follower_actions.lua: Play = a
--                 thrown ball it fetches and spins at, Pet = an idle and a cry,
--                 Talk = two cries) while the field is locked.
--   4. RESULT  -- the action's reply, with a face to match, and the friendship
--                 gain applied to the real party mon: Play +3, Pet +2, Talk +1.
--                 Play is refused (with the reason) by a hurt or sick Pokemon;
--                 Pet has a chance to cure a status condition; Talk reports how
--                 fond of you it is.
--
-- Everything a player can spam goes through lib/interaction_limiter.lua:
-- per-action cooldowns, a budget per time window, and an escalating lock-out
-- for button-mashing. While locked the Pokemon only turns you away -- no menu.
--
-- A plain state machine, ticked from the follower tick (a stay-message cannot
-- tell us when its text finished, and the choice callback fires in the middle
-- of the HUD's input handling, so nothing else is done there):
--   nil -> "report" -> "menu" -> "anim" -> "result" -> nil, with abort() as the escape
--   hatch whenever the screen state is not what the current step expects (a
--   battle began, the message got closed by something else, ...).
local V = ...
local Config = V.require("config")
local EnginePatch = V.require("engine_patch")
local MonMood = V.require("mon_mood")
local Dialogue = V.require("follower_dialogue")
local Limiter = V.require("interaction_limiter")
local PartyRoles = V.require("party_roles")

local FollowerInteraction = {}
FollowerInteraction.__index = FollowerInteraction

-- A primary menu with two sub menus. A row is { label, action }: an action is
-- a scene ("pet"), a job ("follow"), "recall", or "menu:<name>" to open a sub
-- menu; "back" returns to the primary menu; nil cancels.
local MENUS = {
  main = {
    { "Interact", "menu:interact" }, { "Role", "menu:role" },
    { "Recall", "recall" }, { "Cancel", nil },
  },
  interact = {
    { "Pet", "pet" }, { "Play", "play" }, { "Talk", "talk" }, { "Back", "back" },
  },
  role = {
    { "Follow", "follow" }, { "Forage", "forage" }, { "Fight", "battle" }, { "Back", "back" },
  },
}
local JOB_LINES = PartyRoles.LINES
local MENU_LAYOUT = { top = 3, maxRight = 29 } -- clear of the dialogue box; shifted left when a label makes it wide (arrows)
local STORE_KEY = "follower_interaction/limiter"
local LOCK_TAG = "wilds_of_hoenn_follower_action"

-- the happy face each successful action shows (a hurting mon keeps its own)
local ACTION_EMOTION = { pet = "Joyous", play = "Inspired", talk = "Happy" }
local HURTING = {
  fainted = true, critical = true, poison = true, burn = true, paralysis = true,
  freeze = true, sleep = true, low = true, hurt = true,
}

-- The limiter's state belongs to the playthrough and must NOT rewind with a
-- save state (that would be a free reset), so it goes through mod.storage
-- (not rewound by checkpoints) when available, else mod.save.
local function makeStore(self)
  local mod = self.mod
  return {
    load = function()
      if mod.storage and self.game then
        local ok, value = pcall(mod.storage.read, mod.storage, self.game, STORE_KEY)
        if ok and type(value) == "table" then return value.state end
        return nil
      end
      if mod.save then
        local ok, value = pcall(mod.save.get, mod.save, STORE_KEY)
        return ok and value or nil
      end
    end,
    save = function(state)
      if mod.storage and self.game then
        local ok, wrote = pcall(mod.storage.write, mod.storage, self.game, STORE_KEY,
          { format = 1, state = state })
        if ok and wrote ~= false then return end
      end
      if mod.save then pcall(mod.save.set, mod.save, STORE_KEY, state) end
    end,
  }
end

--- opts (all optional): limiter, clock, rng (tests); isAway (function -> true
--- while the follower cannot be talked to, e.g. recalled into the player).
function FollowerInteraction.new(mod, portraitUI, opts)
  opts = opts or {}
  local self = setmetatable({
    mod = mod, portraitUI = portraitUI, state = nil, mon = nil, game = nil,
    rng = opts.rng, isAway = opts.isAway, adapter = opts.adapter,
    companion = opts.companion,
  }, FollowerInteraction)
  self.limiter = opts.limiter or Limiter.new({
    cfg = Config.INTERACT, clock = opts.clock, store = makeStore(self),
  })
  return self
end

-- The Pokemon that is out (the saved companion, else the lead).
function FollowerInteraction:companionMon()
  if self.companion then
    return (self.companion:resolve(EnginePatch.partyMons()))
  end
  return EnginePatch.leadPartyMon()
end

function FollowerInteraction:isActive()
  return self.state ~= nil
end

function FollowerInteraction:reset()
  if self.locked then
    EnginePatch.unlockField(LOCK_TAG)
    self.locked = false
    if self.adapter then self.adapter:cancelAction() end
  end
  self.state, self.mon, self.pending, self.pendingMenu, self.menuName = nil, nil, nil, nil, nil
end

--- Drop everything half-done: close our message, clear the portrait.
function FollowerInteraction:abort()
  if self.state then
    EnginePatch.closeStayMessage()
    self.portraitUI:clear()
  end
  self:reset()
end

-- Final line of an interaction: a normal message the player closes with A/B.
function FollowerInteraction:finish(text, emotion)
  local shown = self.portraitUI:say(text, {
    mon = self.mon, emotion = emotion,
    done = function() self:reset() end,
  })
  if shown then
    self.state = "result"
  else
    self:abort()
  end
end

-- Acts the action out on the follower, then shows the result. Without a
-- follower to animate (or an adapter, in tests) it goes straight to the result.
function FollowerInteraction:animate(action, text, emotion)
  local scene = self.adapter and self.adapter:startAction(action)
  if not scene then
    self:finish(text, emotion)
    return
  end
  -- the report message is still up under the menu (a "stay" message): take it
  -- and its portrait down so the field is free for the scene -- an open
  -- message counts as a busy screen, which would cancel the scene at once
  EnginePatch.closeStayMessage()
  self.portraitUI:clear()
  EnginePatch.lockField(LOCK_TAG)
  self.locked = true
  if action == "play" then EnginePatch.playerPose(Config.ACTIONS.play.playerPoseTicks) end
  self.pending = { text = text, emotion = emotion }
  self.state = "anim"
end

--- Called from the interact hook (before the engine's A-button handler).
--- Returns true when the press was ours -- the follower is in the facing cell
--- and an interaction began -- so the engine must not also act on it.
function FollowerInteraction:tryStart(game)
  if self.state then return false end
  if not EnginePatch.canStartInteraction() then return false end
  if not EnginePatch.followerInFacingCell() then return false end
  if self.isAway and self.isAway() then return false end
  if self.adapter and self.adapter.isBusy and self.adapter:isBusy() then return false end
  local mon = self:companionMon()
  if not mon then return false end

  self.game, self.mon = game or self.game, mon
  local name = EnginePatch.displayName(mon)

  if self.limiter:status().locked then
    self:finish(Dialogue.refusal("locked", name, self.rng), "Angry")
    return true
  end

  local _, reason = MonMood.read(mon)
  local shown = self.portraitUI:say(Dialogue.report(reason, name, self.rng), {
    mon = mon, stay = true,
  })
  if not shown then
    self:reset()
    return false
  end
  self.state = "report"
  return true
end

--- Applies the friendship gain of a granted action (Play +3, Pet +2, Talk +1,
--- Config.INTERACT.gain); returns points gained.
function FollowerInteraction:grant(action, mon)
  local before = EnginePatch.friendshipOf(mon)
  local gain = (Config.INTERACT.gain or {})[action] or 0
  return EnginePatch.setFriendship(mon, before + gain) - before
end

local RIGHT = "\226\150\182" -- the font's right arrow (UTF-8 for the arrow glyph)
local LEFT = "\226\151\128" -- ... and its left arrow

-- The engine sizes a menu from its labels' byte length (see src/ui/game3/choice.lua)
local function tilesFor(bytes)
  return math.min(18, math.max(6, math.floor(bytes * 0.7) + 2))
end

local ARROW_GAP = 24 -- px between the widest label and the right arrow

-- The font's own pen codes (frlg_font.lua PEN_CODES): CLEARTO moves the pen to an
-- absolute x, so every arrow starts at the same pixel whatever its label's width.
local function clearTo(px) return string.char(0xFC, 0x13, px) end
local CLEAR0 = string.char(0xFC, 0x11, 0) -- moves the pen 0 px: three bytes of width padding

-- Labels for a menu. A row that opens a sub menu ends in a right arrow, all in
-- one column just right of the widest label. The arrow is placed by pixel (the
-- font is proportional, so spaces cannot line two rows up). The window is sized
-- from the labels' byte length, so no-op pen codes pad the byte count until the
-- window just holds the arrow. A Back row starts with a left arrow. Without the
-- engine font (tests) the rows are padded with spaces by character count.
local function measure(text)
  return EnginePatch.measureText and EnginePatch.measureText(text) or 0
end

function FollowerInteraction.labels(name)
  local rows = MENUS[name]
  local out, arrowed, widest = {}, {}, nil
  for i, row in ipairs(rows) do
    out[i] = row[1]
    if row[2] == "back" then out[i] = LEFT .. " " .. row[1] end
    if row[2] and row[2]:find("^menu:") then
      arrowed[#arrowed + 1] = i
      if not widest or #row[1] > #rows[widest][1] then widest = i end
    end
  end
  if #arrowed == 0 then return out end
  local arrow = measure(RIGHT)
  if arrow > 0 then
    local arrowX = math.min(255, math.floor(measure(rows[widest][1]) + ARROW_GAP))
    local tiles = math.ceil((arrowX + arrow + 14) / 8)
    for _, i in ipairs(arrowed) do
      local text = rows[i][1] .. clearTo(arrowX) .. RIGHT
      while tilesFor(#text) < tiles and #text < 60 do text = text .. CLEAR0 end
      out[i] = text
    end
  else
    local longest = #rows[widest][1]
    for _, i in ipairs(arrowed) do
      out[i] = rows[i][1] .. string.rep(" ", longest - #rows[i][1] + 1) .. RIGHT
    end
  end
  return out
end

-- Opens the named menu (from the tick: the engine's choice callback runs in the
-- middle of the HUD's input handling, so nothing is opened from inside it).
function FollowerInteraction:openMenu(name)
  local labels = FollowerInteraction.labels(name)
  self.menuName = name
  if not EnginePatch.showChoice(labels, 0, function(index) self:onChoice(index) end, MENU_LAYOUT) then
    self:abort()
  end
end

--- The menu's callback: row index 0.. (127 = B pressed).
function FollowerInteraction:onChoice(index)
  local row = self.state == "menu" and MENUS[self.menuName] and MENUS[self.menuName][(tonumber(index) or -1) + 1]
  local action = row and row[2]
  if not action then
    if self.menuName ~= "main" and tonumber(index) == 127 and self.state == "menu" then
      self.pendingMenu = "main" -- B in a sub menu goes back, like Back
    else
      self:abort()
    end
    return
  end
  if action == "back" then
    self.pendingMenu = "main"
    return
  end
  local sub = action:match("^menu:(.+)$")
  if sub then
    self.pendingMenu = sub
    return
  end
  local mon = self:companionMon()
  if not mon or mon ~= self.mon then
    self:abort() -- the party changed under us
    return
  end
  local name = EnginePatch.displayName(mon)

  -- Recall and the three jobs: no scene and no friendship; they change what the
  -- companion is doing (lib/follower_adapter.lua plays the ball scene once the
  -- message is closed) and say so
  if JOB_LINES[action] then
    local current = self.companion and self.companion:savedRole(mon)
    if current == nil and action == "follow" then current = "follow" end
    if current == action then
      self:finish(string.format("%s is already doing that.", name), (MonMood.read(mon)))
    elseif self.companion and self.companion:set(mon, action) then
      self:finish(string.format(JOB_LINES[action], name), action == "recall" and "Normal" or "Happy")
    else
      self:finish("Nothing happened.", (MonMood.read(mon)))
    end
    return
  end

  -- a hurt or sick Pokemon will not play: it says why, and nothing is spent
  if action == "play" then
    local blocker = MonMood.playBlocker(mon)
    if blocker then
      self:finish(Dialogue.cantPlay(blocker, name, self.rng), (MonMood.read(mon)))
      return
    end
  end

  if MonMood.friendshipOf(mon) >= 255 then
    if action == "talk" then
      local text, emotion = Dialogue.talk(255, name, self.rng) -- it loves you
      self:animate(action, text, emotion)
    else
      self:animate(action, Dialogue.maxed(name, self.rng), "Inspired") -- nothing to gain, nothing spent
    end
    return
  end

  local result = self.limiter:attempt(action)
  if result.ok then
    -- petting a Pokemon with a status condition may cure it
    local healed = false
    if action == "pet" and MonMood.statusOf(mon) then
      local roll = self.rng and self.rng() or math.random()
      if roll < (Config.INTERACT.petHealChance or 0) then
        healed = EnginePatch.clearStatus(mon)
      end
    end
    self:grant(action, mon)
    local derived, reason = MonMood.read(mon) -- after the gain (and the cure)
    local hurting = HURTING[reason] == true
    local text, emotion
    if action == "talk" then
      -- it tells you how fond of you it is, with a face to match
      text, emotion = Dialogue.talk(EnginePatch.friendshipOf(mon), name, self.rng)
    elseif healed then
      text, emotion = Dialogue.healed(name, self.rng), hurting and derived or ACTION_EMOTION.pet
    else
      text = Dialogue.action(action, name, hurting, self.rng)
      emotion = hurting and derived or ACTION_EMOTION[action]
    end
    self:animate(action, text, emotion)
  elseif result.reason == "locked" then
    self:finish(Dialogue.refusal(result.newlyLocked and "locked_now" or "locked", name, self.rng),
      result.newlyLocked and "Shouting" or "Angry")
  else -- "cooldown" | "tired": no gain; the face is just how it feels
    self:finish(Dialogue.refusal(result.reason, name, self.rng), (MonMood.read(mon)))
  end
end

--- Once per follower tick.
function FollowerInteraction:tick(game)
  self.game = game or self.game
  local state = self.state
  if not state then return end

  if state == "report" then
    if not EnginePatch.isMessageOpen() then
      self:abort()
    elseif EnginePatch.messageOnLastPage() then
      self.state = "menu"
      self:openMenu("main")
    end
  elseif state == "menu" then
    -- the callback moves us on synchronously; a menu that vanished without
    -- calling it (a battle, a warp ...) is cleaned up here
    if self.pendingMenu then
      local name = self.pendingMenu
      self.pendingMenu = nil
      self:openMenu(name)
    elseif not EnginePatch.choiceActive() then
      self:abort()
    end
  elseif state == "anim" then
    if EnginePatch.screenBusy() or not self.adapter then
      self:abort() -- a battle / menu / warp took the screen mid-scene
    elseif not self.adapter:actionActive() then
      local pending = self.pending or {}
      self.locked = false -- the scene is over; release the field first
      EnginePatch.unlockField(LOCK_TAG)
      self:finish(pending.text or "", pending.emotion)
    end
  elseif state == "result" then
    if not EnginePatch.isMessageOpen() then self:reset() end
  end
end

--- Forget the cached limiter state (a save was loaded / a checkpoint
--- restored): the next use re-reads it from storage.
function FollowerInteraction:onSaveChanged()
  self:abort()
  self.limiter:reset()
end

return FollowerInteraction
