-- Lifecycle: map enter -> place visible wild Pokemon -> per-tick behaviour
-- and refill -> map exit despawns everything. The only module that owns
-- entity state; engine_patch.lua's wraps call into this one.
local V = ...
local Config = V.require("config")
local EnginePatch = V.require("engine_patch")
local EncounterSource = V.require("encounter_source")
local Behavior = V.require("behavior")
local Shiny = V.require("shiny")
local ActorRenderer = V.require("actor_renderer")
local RendererFactory = V.require("renderer_factory")
local Reachability = V.require("reachability")
local SpriteSource = V.require("sprite_source")
local FormSource = V.require("form_source")
local GrassCover = V.require("grass_cover")
local ModernSpawns = V.require("modern_spawns_bridge")

local SpawnManager = {}
SpawnManager.__index = SpawnManager

function SpawnManager.new(mod)
  return setmetatable({
    mod = mod,
    source = EncounterSource.new(mod),
    entities = {}, -- id -> entity
    order = {}, -- stable draw/iteration order
    nextId = 1,
    mapId = nil,
    game = nil,
  }, SpawnManager)
end

function SpawnManager:clearAll()
  self.entities = {}
  self.order = {}
end

--- Measures what the player can reach from where they stand (see
--- lib/reachability.lua) and restricts spawning to it. Fails OPEN: without
--- the engine pieces or a start cell, no restriction is applied and the map
--- behaves exactly as before.
function SpawnManager:_rebuildReach()
  self.reach, self.reachCount, self.reachAge = nil, nil, 0
  if Config.REACHABLE_SPAWNS and EnginePatch.reachStart and EnginePatch.reachMover then
    local start = EnginePatch.reachStart()
    local move = start and EnginePatch.reachMover(self.game)
    if start and move then
      local t0 = os.clock()
      local set, count = Reachability.build({
        startX = start.x, startY = start.y, startState = start.state, move = move,
      })
      self.reach, self.reachCount = set, count
      local log = self.mod and self.mod.log
      if log and set then
        pcall(log.info, log, "[wilds_of_hoenn] reachable area on %s: %d cells (%.0f ms)",
          tostring(self.mapId), count or 0, (os.clock() - t0) * 1000)
      end
    end
  end
  self.source:setReachable(self.reach)
end

--- Despawns every wild Pokemon standing outside the reachable area.
function SpawnManager:_pruneUnreachable()
  if not self.reach then return end
  local doomed = {}
  for id, e in pairs(self.entities) do
    if e.state == Config.STATE.AVAILABLE and not Reachability.has(self.reach, e.cellX, e.cellY) then
      doomed[#doomed + 1] = id
    end
  end
  for _, id in ipairs(doomed) do self:despawn(id) end
end

--- Once per tick: keep the reachable area current. Re-measures when the
--- player stands outside it (they warped, hopped a ledge, were carried
--- somewhere new) and on a slow timer (Surf learned, a tree cut ...), and
--- drops spawns that are no longer reachable.
function SpawnManager:_checkReach()
  if not Config.REACHABLE_SPAWNS or not self.source:isEligible() then return end
  self.reachAge = (self.reachAge or 0) + 1
  local p = EnginePatch.playerCell and EnginePatch.playerCell()
  if p and p.moving then return end
  local outside = self.reach and p and not Reachability.has(self.reach, p.x, p.y)
  if outside or (self.reachAge >= Config.REACH_REBUILD_TICKS) or (not self.reach and self.reachAge >= 60) then
    self:_rebuildReach()
    self:_pruneUnreachable()
  end
end

function SpawnManager:onMapEntered(mapId, game)
  self:clearAll()
  self.mapId = mapId
  self.game = game
  self.reach, self.reachCount, self.reachAge = nil, nil, 0
  if not Config.enabled(self.mod) then return end
  self.source:loadMap(mapId)
  if not self.source:isEligible() then return end
  self:_rebuildReach()
  self:refill("land")
  self:refill("water")
end

function SpawnManager:onMapExited()
  self:clearAll()
end

local function targetCount(eligibleCount)
  if eligibleCount <= 0 then return 0 end
  local n = Config.MIN_VISIBLE + math.floor(eligibleCount / Config.TILES_PER_ADDITIONAL)
  if n > Config.MAX_VISIBLE then n = Config.MAX_VISIBLE end
  if n < Config.MIN_VISIBLE then n = Config.MIN_VISIBLE end
  return n
end
SpawnManager._targetCount = targetCount

function SpawnManager:_activeCountFor(terrain)
  local n = 0
  for _, e in pairs(self.entities) do
    if e.terrain == terrain then n = n + 1 end
  end
  return n
end

function SpawnManager:_cellFree(x, y)
  for _, e in pairs(self.entities) do
    if e.cellX == x and e.cellY == y then return false end
    if e.moving and e.targetX == x and e.targetY == y then return false end
  end
  -- A spawn on the player's tile would start a battle at once now that
  -- contact means "standing on it" -- keep the cell they stand on, and the
  -- one they are stepping into, clear.
  local p = EnginePatch.playerCell and EnginePatch.playerCell()
  if p then
    if p.x == x and p.y == y then return false end
    if p.moving and p.targetX == x and p.targetY == y then return false end
  end
  local player = self.game and self.game.world and self.game.world.player
  if player and player.cellX == x and player.cellY == y then return false end
  return true
end

function SpawnManager:_silhouetteFor(speciesId)
  local mode = Config.silhouetteMode(self.mod)
  if mode == "off" then return false end
  if mode == "all" then return true end
  return not EnginePatch.isCaught(speciesId) -- "undiscovered"
end

function SpawnManager:_spawnOne(terrain, cell)
  if not self:_cellFree(cell.x, cell.y) then return false end
  local enc = EnginePatch.rollSweetScent(self.mapId, terrain)
  if not enc then return false end
  -- FireRed / LeafGreen's rules roll no personality: draw it now so the sprite
  -- (shiny, gender) and the battle Pokemon are the same one
  if enc.personality == nil then enc.personality = EnginePatch.randomPersonality() end
  -- Modern Spawns' species for the slot the engine rolled (no-op without it)
  enc = ModernSpawns.apply(self.mapId, terrain, enc)
  if not EnginePatch.repelAllows(enc.level) then return false end
  return self:_place(terrain, cell, enc)
end

-- Puts an already rolled encounter on `cell` as a visible wild Pokemon.
-- `keepShiny` skips the SHINY RATE roll (the encounter's own `shiny` stands).
function SpawnManager:_place(terrain, cell, enc, keepShiny)
  local dex = FormSource.artKeyFor(self.mod, enc.species)
  if not dex then return false end
  if not keepShiny then enc = Shiny.rollForEncounter(self.mod, enc) end

  local id = self.nextId
  self.nextId = id + 1

  local presentation = (terrain == "water") and SpriteSource.DEFAULT_WATER_PRESENTATION or SpriteSource.PRESENTATION_LAND
  local renderer = RendererFactory.new(self.mod, dex, enc.shiny, Config.spriteStyle(self.mod), presentation)
  -- PMDCollab: start each Pokemon at its own point in the Idle loop so a
  -- group of them doesn't breathe in unison.
  if renderer.isPmd then
    renderer.clock = math.random(0, 239)
    renderer.idleSpeed = Config.PMD_WILD_IDLE_SPEED
  end
  renderer.silhouette = self:_silhouetteFor(enc.species)

  local facings = { "up", "down", "left", "right" }
  self.entities[id] = {
    id = id,
    species = enc.species, dex = dex, level = enc.level,
    personality = enc.personality, ivs = enc.ivs, roamer = enc.roamer,
    moves = enc.moves, shiny = enc.shiny,
    terrain = terrain, elevation = 3,
    cellX = cell.x, cellY = cell.y, px = cell.x * 16, py = cell.y * 16,
    facing = facings[math.random(1, 4)],
    behavior = Behavior.pick(),
    ticksUntilAction = math.random(0, 60),
    moving = false, stepParity = false,
    floater = SpriteSource.isFloater(self.mod, dex),
    flapClock = math.random(0, 4 * Config.IDLE_FLAP_TICKS),
    renderer = renderer,
    state = Config.STATE.AVAILABLE,
  }
  self.order[#self.order + 1] = id
  return true
end

-- ------- tooling: a chosen species instead of a rolled one -------------------
-- For developer tools (a separate mod calls these through mod.exports): they
-- reproduce a problem spawn on demand. Nothing in the game calls them.

--- An encounter for engine species id `species` at `level` with a fresh
--- personality; `opts.shiny` makes it genuinely shiny (same nature and gender).
function SpawnManager:encounterFor(species, level, opts)
  opts = opts or {}
  local enc = { species = tonumber(species), level = tonumber(level) or 10,
                personality = EnginePatch.randomPersonality(), shiny = false }
  if opts.shiny then
    local ids = EnginePatch.trainerIds() or { otId = 0, otSecretId = 0 }
    if not EnginePatch.isShiny(enc.personality, ids.otId, ids.otSecretId) then
      local p = Shiny.boostedPersonality(enc.personality, ids.otId, ids.otSecretId,
        function(x) return EnginePatch.genderOf(enc.species, x) end)
      if p then enc.personality = p end
    end
    enc.shiny = true
  end
  return enc
end

--- Spawns `species` on a free eligible tile within `opts.radius` (default 3)
--- of the player: a land tile, else a water tile (`opts.terrain` forces one).
--- Returns true, cell -- or nil, reason.
function SpawnManager:spawnSpecies(species, level, opts)
  opts = opts or {}
  if not tonumber(species) then return nil, "no species" end
  local p = EnginePatch.playerCell and EnginePatch.playerCell()
  if not p then return nil, "no player" end
  local radius = tonumber(opts.radius) or 3
  local order = opts.terrain and { opts.terrain } or { "land", "water" }
  for _, terrain in ipairs(order) do
    local near = {}
    for _, c in ipairs(self.source:eligibleCells(terrain)) do
      if math.max(math.abs(c.x - p.x), math.abs(c.y - p.y)) <= radius and self:_cellFree(c.x, c.y) then
        near[#near + 1] = c
      end
    end
    if #near > 0 then
      local cell = near[math.random(1, #near)]
      local enc = self:encounterFor(species, level, opts)
      if self:_place(terrain, cell, enc, true) then return true, cell end
      return nil, "could not place it"
    end
  end
  return nil, "no valid tile within " .. radius .. " tiles"
end

--- Starts a wild battle against `species` at `level` right now.
--- Returns true, or nil, reason.
function SpawnManager:battleSpecies(species, level, opts)
  if not tonumber(species) then return nil, "no species" end
  local enc = self:encounterFor(species, level, opts)
  local ok, err = EnginePatch.startWild(self.game, enc, {})
  if not ok then return nil, tostring(err or "the battle did not start") end
  return true
end

function SpawnManager:refill(terrain)
  local eligible = self.source:eligibleCells(terrain)
  if #eligible == 0 then return end
  local want = targetCount(#eligible)
  local have = self:_activeCountFor(terrain)
  local attempts = 0
  local maxAttempts = (want - have) * 8 + 8
  while have < want and attempts < maxAttempts do
    attempts = attempts + 1
    local cell = eligible[math.random(1, #eligible)]
    if self:_spawnOne(terrain, cell) then have = have + 1 end
  end
end

--- Advances every live entity one tick (engine_patch's `followerTick` hook,
--- piggybacked on Follower.update so this mod needs no extra tick seam).
function SpawnManager:tick(game)
  self.game = game or self.game
  self:_checkReach()
  for _, id in ipairs(self.order) do
    local e = self.entities[id]
    -- an `engaged` Pokemon is in a skirmish with the player's Battler
    -- (lib/overworld_battle.lua): it stands its ground and that module animates it
    if e and e.state == Config.STATE.AVAILABLE and not e.engaged then
      if e.floater and not e.moving then e.flapClock = e.flapClock + 1 end
      Behavior.tick(e, self.game)
      if e.renderer and e.renderer.advance then e.renderer:advance(e.moving) end
    end
  end
  self:refill("land")
  self:refill("water")
end

--- Appends one actor per live entity (engine_patch's `collectActors` hook).
local function poseOf(e)
  local pose = ActorRenderer.POSE_STAND
  if e.moving then
    pose = e.stepParity and ActorRenderer.POSE_WALK_A or ActorRenderer.POSE_WALK_B
  elseif e.floater then
    pose = ActorRenderer.idleFlapPose(e.flapClock, Config.IDLE_FLAP_TICKS)
  end
  if e.owPose then pose = e.owPose end -- set by the Battler's skirmish
  return pose
end

--- Every live wild Pokemon's water reflection, for lib/reflection.lua (the
--- drawBehind hook).
function SpawnManager:reflections(list)
  for _, id in ipairs(self.order) do
    local e = self.entities[id]
    local r = e and e.state ~= Config.STATE.DESPAWNED and e.renderer
    if r and r.reflectionGeometry then
      local geo = r:reflectionGeometry(e.px, e.py, e.facing, poseOf(e))
      if geo then
        local moving = e.moving and e.targetX ~= nil
        list[#list + 1] = {
          geo = geo,
          cell = { cx = moving and e.targetX or e.cellX, cy = moving and e.targetY or e.cellY,
                   pcx = e.cellX, pcy = e.cellY },
        }
      end
    end
  end
end

function SpawnManager:collectActors(actors)
  for _, id in ipairs(self.order) do
    local e = self.entities[id]
    if e and e.state ~= Config.STATE.DESPAWNED then
      local pose = poseOf(e)
      actors[#actors + 1] = {
        kind = "wild_mon", i = id,
        x = e.px, y = e.py, sortY = e.py, elevation = e.elevation,
        facing = e.facing, walkPhase = pose,
        renderer = e.renderer,
      }
      -- "Sinking into grass" overlay -- see lib/grass_cover.lua. A water
      -- spawn's cell is never grass, so this is a no-op for those without
      -- needing its own terrain check here.
      GrassCover.append(actors, e.cellX, e.cellY, e.py, e.elevation, id)
    end
  end
end

--- The live wild Pokemon standing on (tx, ty), or nil. Entities mid-battle
--- (ENCOUNTER_STARTING) don't count -- they're being removed.
function SpawnManager:entityAt(tx, ty)
  for _, id in ipairs(self.order) do
    local e = self.entities[id]
    if e and e.state == Config.STATE.AVAILABLE and e.cellX == tx and e.cellY == ty then
      return e
    end
  end
  return nil
end

--- engine_patch's `blocks` hook: true when something we spawned occupies
--- (tx, ty). Elevation is intentionally ignored here, matching how
--- Objects.blocks treats a visible, non-passable object -- a wild Pokemon
--- always blocks regardless of the mover's elevation.
function SpawnManager:blocksCell(tx, ty)
  return self:entityAt(tx, ty) ~= nil
end

--- Wild Pokemon a Battler may pick a fight with: live, not already in a
--- skirmish, and not one it already failed to build a fighter for.
function SpawnManager:fightTargets()
  local out = {}
  for _, id in ipairs(self.order) do
    local e = self.entities[id]
    if e and e.state == Config.STATE.AVAILABLE and not e.engaged and not e.noFight then
      out[#out + 1] = e
    end
  end
  return out
end

--- The entity with this id (nil once it is gone).
function SpawnManager:get(id)
  return self.entities[id]
end

function SpawnManager:markEncounterStarting(id)
  local e = self.entities[id]
  if e then e.state = Config.STATE.ENCOUNTER_STARTING end
end

function SpawnManager:despawn(id)
  if not self.entities[id] then return end
  self.entities[id] = nil
  for i = #self.order, 1, -1 do
    if self.order[i] == id then
      table.remove(self.order, i)
      break
    end
  end
end

--- Re-points every live entity's renderer at the current Sprite Style
--- option without respawning anything -- a mid-game style switch takes
--- effect on the very next frame. Each renderer is rebuilt through
--- RendererFactory (the PMDCollab style is a different renderer class, so a
--- switch to or from it can't be a field flip), keeping the entity's
--- species, shininess, terrain art and silhouette. Rebuilding is cheap: the
--- image and quad caches are keyed by path, not by renderer.
function SpawnManager:refreshSpriteStyle()
  local style = Config.spriteStyle(self.mod)
  for _, e in pairs(self.entities) do
    if e.renderer then
      local presentation = (e.terrain == "water") and SpriteSource.DEFAULT_WATER_PRESENTATION
        or SpriteSource.PRESENTATION_LAND
      local fresh = RendererFactory.new(self.mod, e.dex, e.shiny, style, presentation)
      fresh.silhouette = e.renderer.silhouette
      if fresh.isPmd then
        fresh.clock = math.random(0, 239)
        fresh.idleSpeed = Config.PMD_WILD_IDLE_SPEED
      end
      e.renderer = fresh
    end
  end
end

function SpawnManager:count()
  local n = 0
  for _ in pairs(self.entities) do n = n + 1 end
  return n
end

return SpawnManager
