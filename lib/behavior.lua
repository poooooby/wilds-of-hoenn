-- Idle and Roam behaviours for visible wild Pokemon. No Chase/Hidden in v1
-- (see docs/ARCHITECTURE.md). Movement legality always goes through the
-- engine's own Collision.canEnter/isWater -- never reimplemented.
local V = ...
local EnginePatch = V.require("engine_patch")

local Behavior = {}
Behavior.IDLE = "idle"
Behavior.ROAM = "roam"

local DELTA = { up = { 0, -1 }, down = { 0, 1 }, left = { -1, 0 }, right = { 1, 0 } }
local DIRS = { "up", "down", "left", "right" }
local ACTION_MIN_TICKS, ACTION_JITTER_TICKS = 60, 60 -- ~1-2s at 60fps
local STEP_FRAMES = 16

--- Fixed 50/50 mix; no per-species or option-driven weighting in v1.
function Behavior.pick(rng)
  rng = rng or math.random
  return rng() < 0.5 and Behavior.IDLE or Behavior.ROAM
end

local function canStep(entity, game, tx, ty)
  -- Checked BEFORE canEnter, not after: a roaming wild Pokemon must stay
  -- on its OWN encounter terrain -- not just "not water" (that alone lets
  -- a land spawn wander onto any walkable non-water tile: paths, doodads,
  -- the player's own tile, anywhere). terrainAt is the same ROM-derived
  -- classification the eligible-cell scan and the engine's own vanilla
  -- step roll both use (encounters.lua:170), so a Pokemon can never roam
  -- somewhere it couldn't have spawned -- and doing this cheap, read-only
  -- check FIRST means a terrain-invalid direction never reaches the
  -- engine's canEnter/entityBlocks at all. canEnter is where the real
  -- engine's Objects.blocks(tx, ty, nil, elevation) reentrancy lives (see
  -- lib/engine_patch.lua's isProbingCanEnter) -- that's already guarded
  -- against misfiring a battle regardless of order, but there is no
  -- reason to even make the engine call for a direction this Pokemon
  -- could never actually take.
  if EnginePatch.terrainAt(tx, ty) ~= entity.terrain then return false end
  local onWater = entity.terrain == "water"
  return EnginePatch.canEnter(game, tx, ty, {
    fromX = entity.cellX, fromY = entity.cellY, dir = entity.facing,
    surfing = onWater, elevation = entity.elevation,
  })
end
Behavior._canStep = canStep

local function advanceMove(entity)
  entity.progress = entity.progress + 1
  local t = entity.progress / entity.stepFrames
  if t > 1 then t = 1 end
  entity.px = (entity.fromX + (entity.targetX - entity.fromX) * t) * 16
  entity.py = (entity.fromY + (entity.targetY - entity.fromY) * t) * 16
  if t >= 1 then
    entity.cellX, entity.cellY = entity.targetX, entity.targetY
    entity.moving = false
  end
end
Behavior._advanceMove = advanceMove

--- Advances `entity` by one field tick. `entity` fields: cellX, cellY,
--- facing, behavior (Behavior.IDLE|ROAM), terrain ("land"|"water"),
--- elevation, moving, fromX/fromY/targetX/targetY/progress/stepFrames
--- (movement-in-progress state), ticksUntilAction, px/py (world pixels,
--- kept in sync for the renderer). `game` and `rng` are passed through
--- (rng defaults to math.random; tests inject a seeded/deterministic one).
function Behavior.tick(entity, game, rng)
  rng = rng or math.random
  if entity.moving then
    advanceMove(entity)
    return
  end
  entity.ticksUntilAction = (entity.ticksUntilAction or 0) - 1
  if entity.ticksUntilAction > 0 then return end
  entity.ticksUntilAction = ACTION_MIN_TICKS + math.floor(rng() * ACTION_JITTER_TICKS)

  if entity.behavior == Behavior.IDLE then
    entity.facing = DIRS[math.floor(rng() * 4) + 1]
    return
  end

  local dir = DIRS[math.floor(rng() * 4) + 1]
  local d = DELTA[dir]
  local tx, ty = entity.cellX + d[1], entity.cellY + d[2]
  entity.facing = dir
  if not canStep(entity, game, tx, ty) then return end
  entity.fromX, entity.fromY = entity.cellX, entity.cellY
  entity.targetX, entity.targetY = tx, ty
  entity.progress = 0
  entity.stepFrames = STEP_FRAMES
  entity.moving = true
  -- Alternates walkA/walkB once per step (not per tick) -- see
  -- lib/spawn_manager.lua's collectActors, which reads this to pick the
  -- pose; the engine's own stepFlip draw() parameter is hardcoded false
  -- for non-player actors, so this is the only source of A/B alternation.
  entity.stepParity = not entity.stepParity
end

return Behavior
