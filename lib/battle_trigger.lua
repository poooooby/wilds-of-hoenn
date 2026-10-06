-- Player-vs-wild-Pokemon contact: the mon the player saw standing in the
-- grass is the exact mon they battle (species, level, personality, IVs,
-- roamer-ness all carried through from the spawn).
--
-- Contact signal: engine_patch's `blocks` wrap fires for every caller of
-- Objects.blocks (player movement, NPC movement, trainer sight -- see
-- lib/engine_patch.lua's comment on that target), but only the PLAYER's
-- own collision check calls it with no `exceptLocalId`
-- (collision.lua:1003 entityBlocks(game, tx, ty, elevation) ->
-- Objects.blocks(tx, ty, nil, elevation); every NPC/trainer-sight caller
-- passes its own localId). main.lua's `blocks` hook callback uses exactly
-- that to call BattleTrigger:onPlayerBumped only for the player, while
-- still blocking NPCs and trainer sight from walking through a wild
-- Pokemon like any other solid object.
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
