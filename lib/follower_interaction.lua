-- Talking to your follower: face it, press A.
--
--   1. REPORT  -- a message with the lead Pokemon's portrait, its face and its
--                 words taken from its real state (HP, status, friendship:
--                 lib/mon_mood.lua + lib/follower_dialogue.lua).
--   2. MENU    -- once that text is fully typed, the engine's own choice menu
--                 opens under it: Pet / Play / Talk / Cancel.
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

local FollowerInteraction = {}
FollowerInteraction.__index = FollowerInteraction

local ACTIONS = { "pet", "play", "talk" } -- menu rows 0..2; row 3 is Cancel
local MENU = { "Pet", "Play", "Talk", "Cancel" }
local MENU_LAYOUT = { top = 3 } -- keeps the 4-row menu clear of the dialogue box
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
  self.state, self.mon, self.pending = nil, nil, nil
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

--- The menu's callback: row index 0.. (127 = B pressed).
function FollowerInteraction:onChoice(index)
  local action = ACTIONS[(tonumber(index) or -1) + 1]
  if not action or self.state ~= "menu" then
    self:abort()
    return
  end
  local mon = self:companionMon()
  if not mon or mon ~= self.mon then
    self:abort() -- the party changed under us
    return
  end
  local name = EnginePatch.displayName(mon)

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
      local ok = EnginePatch.showChoice(MENU, 0, function(index) self:onChoice(index) end, MENU_LAYOUT)
      if not ok then self:abort() end
    end
  elseif state == "menu" then
    -- the callback moves us on synchronously; a menu that vanished without
    -- calling it (a battle, a warp ...) is cleaned up here
    if not EnginePatch.choiceActive() then self:abort() end
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
