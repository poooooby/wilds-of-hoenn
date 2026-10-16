-- Player-vs-wild-Pokemon contact: the mon the player saw standing in the
-- grass is the exact mon they battle (species, level, personality, IVs,
-- roamer-ness all carried through from the spawn).
--
-- Contact signal: a battle starts only when the player ARRIVES ON the wild
-- Pokemon's tile -- the engine's `world.stepped` event at the end of every step
-- (BattleTrigger:onPlayerStepped), so walking straight through one counts --
-- or is resting on it (BattleTrigger:checkContact, every field tick). Never from
-- an adjacent bump. engine_patch's `blocks` wrap fires for every
-- caller of Objects.blocks (player movement, NPC movement, trainer sight --
-- see lib/engine_patch.lua's comment on that target); only the PLAYER's own
-- collision check calls it with no `exceptLocalId` (collision.lua:1003
-- entityBlocks -> Objects.blocks(tx, ty, nil, elevation); every NPC/trainer-
-- sight caller passes its own localId). main.lua's `blocks` callback answers
-- "not blocked" for that player check so the player can step onto the mon,
-- while still blocking NPCs, trainer sight and other wild Pokemon.
--
-- Never in the middle of the step: `world.stepped` fires BEFORE the engine runs that
-- step's own events (player.lua finishStep: trainer sight, coord events, then
-- StepEvents.onStepTaken -- an egg hatching, poison ...). A battle started there let
-- the egg-hatch scene open on top of it, and once the battle's opening transition
-- finished every button went to the hidden battle, so the hatch's "Nickname?" Yes / No
-- never answered: a hard softlock. So the contact is only NOTED, and the battle starts
-- from the field tick (BattleTrigger:tick) once the game is free (EnginePatch.gameFree:
-- no step event queued or running, no message, menu or scene). Something happening ->
-- it waits and tries again the next tick. The player still meets that Pokemon -- right
-- after the hatch, the way the cart never rolls a wild encounter on a step that hatched
-- an egg -- and is held on its tile meanwhile: the contact takes a field lock of its own
-- (HOLD), since a held direction starts the next step -- or a ledge jump -- in the same
-- update that finished the last, and the engine's step events are pumped after the field
-- tick, so a hatch ending could otherwise let the player walk off before the battle. The
-- lock is let go while the game is checked (it would count as busy itself) and once the
-- battle is on.
local V = ...
local Config = V.require("config")
local EnginePatch = V.require("engine_patch")

local BattleTrigger = {}
BattleTrigger.__index = BattleTrigger

local HOLD = "wilds_of_hoenn_contact" -- our Field.lock tag while a contact waits for its battle
-- A battle we started that never opens is given up: the player is let go and the wild
-- Pokemon stays. Another mod stopping it from opening used to hold the player for good (a
-- softlock: the field music playing on, no moving, no Start menu). Measured in Emerald: the
-- transition starts the tick the battle is started and the battle is on the tick it ends,
-- 89 ticks on a route, 124 in a cave. So: neither a transition nor the battle for
-- PENDING_IDLE ticks -> it is not coming; and PENDING_GIVE_UP ticks at most in any case (a
-- transition that never ends; an engine that cannot report its transition).
BattleTrigger.PENDING_IDLE = 30
BattleTrigger.PENDING_GIVE_UP = 300

function BattleTrigger.new(mod, spawnManager, log)
  return setmetatable({
    mod = mod, spawnManager = spawnManager, log = log, pendingId = nil,
  }, BattleTrigger)
end

--- True while a battle we started is still resolving -- guards against the
--- player holding the movement key and re-triggering `blocks` every frame
--- before the battle has actually opened.
function BattleTrigger:isPending()
  return self.pendingId ~= nil
end

--- The engine's `world.stepped` event: a step just FINISHED on (x, y). This is
--- the real contact signal. Holding a direction starts the next step in the
--- same Player.update that finished the last one, so the player is never "at
--- rest" on the tile they cross -- checking only for a standing player meant a
--- mon in a cave could be walked straight through. The event fires inside
--- Player's finishStep, the same moment the engine rolls its own wild
--- encounters (and, like those, a battle started here stops the held
--- direction from beginning another step).
function BattleTrigger:onPlayerStepped(x, y)
  if self:isPending() or self.contact then return end
  x, y = tonumber(x), tonumber(y)
  if not x or not y then return end
  local entity = self.spawnManager:entityAt(x, y)
  if not entity then return end
  if self:_fieldBusy(x, y) then return end
  -- noted, not started: this step's own events have not run yet (see the header)
  self:_noteContact(entity, x, y)
end

-- a contact waiting for its battle: the player held on the tile (see the header)
function BattleTrigger:_noteContact(entity, x, y)
  self.contact = { id = entity.id, x = x, y = y }
  self:_hold(true)
end

function BattleTrigger:_hold(on)
  if on and not self.holding then
    if EnginePatch.lockField then EnginePatch.lockField(HOLD) end
    self.holding = true
  elseif not on and self.holding then
    if EnginePatch.unlockField then EnginePatch.unlockField(HOLD) end
    self.holding = false
  end
end

--- The player is held on the tile of a wild Pokemon they met: its battle is waiting for
--- the game to be free, or opening.
function BattleTrigger:holdsPlayer()
  return self.holding == true
end

-- the game is free for a wild battle (no step event, message, menu, scene ...)
local function gameFree()
  if EnginePatch.gameFree then return EnginePatch.gameFree() end
  return not (EnginePatch.fieldBusy and EnginePatch.fieldBusy())
end

--- Every field tick: starts the battle of a contact noted at the end of a step, once the
--- game is free; until then it waits. Dropped if that Pokemon is gone meanwhile.
function BattleTrigger:tick()
  local c = self.contact
  if not c then
    local active = EnginePatch.battleActive and EnginePatch.battleActive()
    if self:isPending() and not active then
      self.pendingAge = (self.pendingAge or 0) + 1
      local transition = EnginePatch.battleTransitionActive and EnginePatch.battleTransitionActive()
      if transition == false then
        self.pendingIdle = (self.pendingIdle or 0) + 1
      else
        self.pendingIdle = 0
      end
      if self.pendingAge >= BattleTrigger.PENDING_GIVE_UP or self.pendingIdle >= BattleTrigger.PENDING_IDLE then
        self:_giveUp()
        return
      end
    else
      self.pendingAge, self.pendingIdle = nil, nil
    end
    -- the battle is on (or never came): let go of the player
    if self.holding and (not self:isPending() or active) then
      self:_hold(false)
    end
    return
  end
  local e = self.spawnManager.entities and self.spawnManager.entities[c.id]
  if self:isPending() or not e or e.state ~= Config.STATE.AVAILABLE then
    self.contact = nil -- gone meanwhile (or already battling)
    self:_hold(false)
    return
  end
  -- our own hold would count as the field being busy: let go of it while checking
  self:_hold(false)
  if not gameFree() then self:_hold(true) return end -- an egg hatching, poison, a message: wait
  self.contact = nil
  self:onPlayerBumped(e)
  -- the player stays put until the battle is on (its intro does not stop a held direction)
  if self:isPending() then self:_hold(true) end
end

--- No wild battle while something else owns the field (EnginePatch.fieldBusy): a
--- cutscene walking the player onto a wild Pokemon (Wally's tutorial), a trainer who
--- spotted the player (the field is locked for the approach), a message or a warp.
--- Starting one then broke the cutscene / froze the trainer. The cell the player is on
--- is remembered as a grace cell: still standing there once the field is free again
--- starts nothing; stepping off and back on does.
function BattleTrigger:_fieldBusy(x, y)
  if not (EnginePatch.fieldBusy and EnginePatch.fieldBusy()) then return false end
  self.graceX, self.graceY = x, y
  return true
end

--- Called every field tick: backstop for the standing-still case (nothing
--- stepped, so no event) -- starts the battle when the player is resting on a
--- wild Pokemon's tile, never from an adjacent bump or a step in progress.
--- (The `blocks` hook in main.lua lets the player walk onto a wild Pokemon
--- for exactly this reason.)
function BattleTrigger:checkContact()
  if self:isPending() or self.contact then return end
  local player = EnginePatch.playerCell()
  if not player or player.moving then return end
  if self.graceX and (player.x ~= self.graceX or player.y ~= self.graceY) then
    self.graceX, self.graceY = nil, nil -- left the cell a cutscene / trainer put them on
  end
  local entity = self.spawnManager:entityAt(player.x, player.y)
  if not entity then return end
  if self:_fieldBusy(player.x, player.y) then return end
  if self.graceX == player.x and self.graceY == player.y then return end
  if not gameFree() then return end -- a step event, a message, a menu: try again next tick
  self:onPlayerBumped(entity)
end

--- A wild Pokemon chasing the player caught up with them (lib/wild_reactions.lua: on or
--- next to their tile while they stand): the normal wild battle, with the same guards as
--- the player stepping onto one (nothing while the field is busy; it waits for a free game).
function BattleTrigger:onChaserContact(entity)
  if self:isPending() or self.contact or not entity then return end
  local p = EnginePatch.playerCell and EnginePatch.playerCell()
  if p and self:_fieldBusy(p.x, p.y) then return end
  -- like a step's contact: the battle once the game is free (BattleTrigger:tick)
  self:_noteContact(entity, p and p.x, p and p.y)
end

function BattleTrigger:onPlayerBumped(entity)
  if self:isPending() then return end
  local enc = {
    species = entity.species, level = entity.level, personality = entity.personality,
    ivs = entity.ivs, roamer = entity.roamer, moves = entity.moves,
  }
  if entity.roamer then
    -- the roaming legendary battles as the engine has it NOW: its current HP and status
    -- (the battle reads them from the encounter; the copy rolled at spawn time would heal
    -- it), and if it has been caught or defeated meanwhile, it is simply gone
    local now = EnginePatch.roamerNow and EnginePatch.roamerNow()
    if not (now and now.species == entity.species) then
      self.spawnManager:despawn(entity.id, { animate = true })
      return
    end
    enc = now
  end
  self.pendingId = entity.id
  -- called over by Sweet Scent: main.lua's battle.started lowers the foe's evasion
  self.pendingLured = entity.lured ~= nil
  self.spawnManager:markEncounterStarting(entity.id)

  local ok, err = EnginePatch.startWild(self.spawnManager.game, enc, {
    done = function(result) self:_onBattleEnded(entity.id, result) end,
  })
  if not ok then
    -- Couldn't start (a battle is already running, the field is mid-warp,
    -- no healthy party mon, ...): un-pend and leave the entity exactly as
    -- it was. The player's own step was already blocked by the `blocks`
    -- wrap, independent of this, so there's nothing else to undo.
    if self.log then
      self.log:warn("[wilds_of_hoenn] wild battle did not start: %s", tostring(err))
    end
    self.pendingId, self.pendingLured = nil, false
    local e = self.spawnManager.entities[entity.id]
    if e then e.state = Config.STATE.AVAILABLE end
  end
end

--- A battle we started never opened (BattleTrigger.PENDING_GIVE_UP): let go of the player
--- and leave the wild Pokemon where it is. The tile they stand on becomes a grace tile, so
--- standing there does not try again at once; stepping off and back on does.
function BattleTrigger:_giveUp()
  local id = self.pendingId
  if self.log then
    self.log:warn("[wilds_of_hoenn] wild battle never opened (%d ticks): letting go of the player",
      self.pendingAge or 0)
  end
  self.pendingId, self.pendingLured, self.pendingAge, self.pendingIdle = nil, false, nil, nil
  self:_hold(false)
  local e = id and self.spawnManager.entities[id]
  if e and e.state == Config.STATE.ENCOUNTER_STARTING then e.state = Config.STATE.AVAILABLE end
  local p = EnginePatch.playerCell and EnginePatch.playerCell()
  if p then self.graceX, self.graceY = p.x, p.y end
end

function BattleTrigger:_onBattleEnded(entityId, _result)
  self:_hold(false)
  if self.pendingId == entityId then
    self.pendingId, self.pendingLured, self.pendingAge, self.pendingIdle = nil, false, nil, nil
  end
  -- Win, lose, flee, catch: the mon the player fought is gone from the
  -- overworld either way. SpawnManager's own refill() on the next tick
  -- puts a freshly rolled wild Pokemon somewhere else on the map.
  self.spawnManager:despawn(entityId)
end

return BattleTrigger
