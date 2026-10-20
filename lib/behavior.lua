-- Idle and Roam behaviours for visible wild Pokemon (startled ones flee or chase: lib/
-- wild_reactions.lua, through Behavior.tryStep). Movement legality always goes through
-- the engine's own Collision.canEnter/isWater -- never reimplemented.
local V = ...
local EnginePatch = V.require("engine_patch")
local Config = V.require("config")

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

-- A chaser may leave its spawn area (Config.REACT.chase.anyGround): open ground anywhere
-- -- dry, walkable, the engine's collision allowing it -- but never water (a land chaser
-- does not wade in), a doorway (it would stand in a warp), or the player's own cell.
local function openGround(tx, ty)
  if EnginePatch.isWater and EnginePatch.isWater(tx, ty) then return false end
  if EnginePatch.isWarpCell and EnginePatch.isWarpCell(tx, ty) then return false end
  local p = EnginePatch.playerCell and EnginePatch.playerCell()
  if p and ((p.x == tx and p.y == ty) or (p.moving and p.targetX == tx and p.targetY == ty)) then
    return false
  end
  return true
end
Behavior._openGround = openGround

--- Is `entity` standing off its own encounter terrain (a chaser that left the grass)?
function Behavior.offTerrain(entity)
  return EnginePatch.terrainAt(entity.cellX, entity.cellY) ~= entity.terrain
end

local function canStep(entity, game, tx, ty, anyGround)
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
  local onWater = entity.terrain == "water"
  -- Never onto the player (or the tile they are stepping into): the player is not an engine
  -- object, so the engine's canEnter never sees them, and a wild Pokemon wandering onto a
  -- player standing still started a battle by itself -- in a cave, where the whole floor is
  -- encounter ground, all the time (and with another mod keeping that battle from opening,
  -- the player was held for good: lib/battle_trigger.lua's give-up).
  local p = EnginePatch.playerCell and EnginePatch.playerCell()
  if p and ((p.x == tx and p.y == ty) or (p.moving and p.targetX == tx and p.targetY == ty)) then
    return false
  end
  if anyGround and not onWater then
    if not openGround(tx, ty) then return false end
  elseif EnginePatch.terrainAt(tx, ty) ~= entity.terrain then
    return false
  end
  -- a swimmer keeps off the last water row before a bank (EncounterSource.openWater)
  if onWater and EnginePatch.isWater and not EnginePatch.isWater(tx, ty + 1) then return false end
  -- A swimmer passes no elevation: spawns carry 3 (their draw layer), Gen 3 water is
  -- elevation 1, and the engine refuses a surfing step onto water at another elevation
  -- (collision.lua canEnter, "elevation") -- so no water spawn could ever take a step.
  -- Its terrain is already held to water above.
  return EnginePatch.canEnter(game, tx, ty, {
    fromX = entity.cellX, fromY = entity.cellY, dir = entity.facing,
    surfing = onWater, elevation = (not onWater) and entity.elevation or nil,
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
    -- a step that ends on pond water / a puddle leaves a ripple, like the player's
    if EnginePatch.ripplesAt and EnginePatch.ripplesAt(entity.cellX, entity.cellY) then
      EnginePatch.startRipple(entity.cellX, entity.cellY)
    end
  end
end
Behavior._advanceMove = advanceMove

--- One tick of a water spawn's swimming (Config.SWIM): it holds a heading for a run of
--- tiles, pauses, then picks a new heading -- trying every direction, turning back last,
--- so a blocked one does not leave it sitting there. `entity.swim` keeps its state.
local function roll(rng, lo, hi)
  return lo + math.floor(rng() * (hi - lo + 1))
end
local REVERSE = { up = "down", down = "up", left = "right", right = "left" }

function Behavior.swimTick(entity, game, rng, cfg)
  local s = entity.swim
  if not s then s = { left = 0, pause = 0 } entity.swim = s end
  if s.pause > 0 then
    s.pause = s.pause - 1
    return
  end
  local frames = cfg.stepFrames or STEP_FRAMES
  if s.left > 0 and s.dir and Behavior.tryStep(entity, game, s.dir, frames) then
    s.left = s.left - 1
    if s.left == 0 then s.pause = roll(rng, cfg.pauseMin, cfg.pauseMax) end
    return
  end
  -- a new heading: the four directions in a random order, back the way it came last
  local order = { "up", "down", "left", "right" }
  for i = 4, 2, -1 do
    local j = math.floor(rng() * i) + 1
    order[i], order[j] = order[j], order[i]
  end
  local back = s.dir and REVERSE[s.dir]
  if back then
    for i, d in ipairs(order) do
      if d == back then table.remove(order, i) order[#order + 1] = d break end
    end
  end
  local facing = entity.facing
  for _, d in ipairs(order) do
    if Behavior.tryStep(entity, game, d, frames) then
      s.dir = d
      s.left = roll(rng, cfg.runMin, cfg.runMax) - 1
      if s.left == 0 then s.pause = roll(rng, cfg.pauseMin, cfg.pauseMax) end
      return
    end
  end
  -- boxed in: look about, try again after a pause
  entity.facing = facing
  s.dir, s.left = nil, 0
  s.pause = roll(rng, cfg.pauseMin, cfg.pauseMax)
end

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
  -- a water spawn swims (Config.SWIM) instead of idling / roaming
  local swim = entity.terrain == "water" and Config.SWIM
  if swim then return Behavior.swimTick(entity, game, rng, swim) end
  entity.ticksUntilAction = (entity.ticksUntilAction or 0) - 1
  if entity.ticksUntilAction > 0 then return end
  entity.ticksUntilAction = ACTION_MIN_TICKS + math.floor(rng() * ACTION_JITTER_TICKS)

  if entity.behavior == Behavior.IDLE then
    entity.facing = DIRS[math.floor(rng() * 4) + 1]
    return
  end

  Behavior.tryStep(entity, game, DIRS[math.floor(rng() * 4) + 1], STEP_FRAMES)
end

--- Turns `entity` toward `dir` and starts a one-tile step there taking `frames` ticks
--- (16 = walking pace, fewer = faster), when its own legality allows it. True when the
--- step began. Shared by Roam and the startled flee / chase (lib/wild_reactions.lua).
--- `opts.anyGround`: a land Pokemon may step off its own terrain onto open ground (a
--- chaser, and its walk home).
function Behavior.tryStep(entity, game, dir, frames, opts)
  local d = DELTA[dir]
  if not d then return false end
  local tx, ty = entity.cellX + d[1], entity.cellY + d[2]
  entity.facing = dir
  if not canStep(entity, game, tx, ty, opts and opts.anyGround) then return false end
  entity.fromX, entity.fromY = entity.cellX, entity.cellY
  entity.targetX, entity.targetY = tx, ty
  entity.progress = 0
  entity.stepFrames = frames or STEP_FRAMES
  entity.moving = true
  -- PMDCollab plays its walk cycle faster on a quicker step (1 at walking pace)
  if entity.renderer and entity.renderer.isPmd then
    entity.renderer.walkMul = STEP_FRAMES / entity.stepFrames
  end
  -- Alternates walkA/walkB once per step (not per tick) -- see
  -- lib/spawn_manager.lua's collectActors, which reads this to pick the
  -- pose; the engine's own stepFlip draw() parameter is hardcoded false
  -- for non-player actors, so this is the only source of A/B alternation.
  entity.stepParity = not entity.stepParity
  return true
end
Behavior.STEP_FRAMES = STEP_FRAMES
Behavior.DELTA = DELTA

return Behavior
