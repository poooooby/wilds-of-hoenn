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
local V = ...
local Config = V.require("config")
local EnginePatch = V.require("engine_patch")

local BattleTrigger = {}
BattleTrigger.__index = BattleTrigger

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
  if self:isPending() then return end
  x, y = tonumber(x), tonumber(y)
  if not x or not y then return end
  local entity = self.spawnManager:entityAt(x, y)
  if entity then self:onPlayerBumped(entity) end
end

--- Called every field tick: backstop for the standing-still case (nothing
--- stepped, so no event) -- starts the battle when the player is resting on a
--- wild Pokemon's tile, never from an adjacent bump or a step in progress.
--- (The `blocks` hook in main.lua lets the player walk onto a wild Pokemon
--- for exactly this reason.)
function BattleTrigger:checkContact()
  if self:isPending() then return end
  local player = EnginePatch.playerCell()
  if not player or player.moving then return end
  local entity = self.spawnManager:entityAt(player.x, player.y)
  if entity then self:onPlayerBumped(entity) end
end

function BattleTrigger:onPlayerBumped(entity)
  if self:isPending() then return end
  self.pendingId = entity.id
  self.spawnManager:markEncounterStarting(entity.id)

  local enc = {
    species = entity.species, level = entity.level, personality = entity.personality,
    ivs = entity.ivs, roamer = entity.roamer, moves = entity.moves,
  }
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
    self.pendingId = nil
    local e = self.spawnManager.entities[entity.id]
    if e then e.state = Config.STATE.AVAILABLE end
  end
end

function BattleTrigger:_onBattleEnded(entityId, _result)
  if self.pendingId == entityId then self.pendingId = nil end
  -- Win, lose, flee, catch: the mon the player fought is gone from the
  -- overworld either way. SpawnManager's own refill() on the next tick
  -- puts a freshly rolled wild Pokemon somewhere else on the map.
  self.spawnManager:despawn(entityId)
end

return BattleTrigger
