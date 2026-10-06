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

function SpawnManager:onMapEntered(mapId, game)
  self:clearAll()
  self.mapId = mapId
  self.game = game
  if not Config.enabled(self.mod) then return end
  self.source:loadMap(mapId)
  if not self.source:isEligible() then return end
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
  if not EnginePatch.repelAllows(enc.level) then return false end
  local dex = EnginePatch.nationalFor(enc.species)
  if not dex then return false end
  enc = Shiny.rollForEncounter(self.mod, enc)

  local id = self.nextId
  self.nextId = id + 1

  local renderer = ActorRenderer.new(self.mod, dex, enc.shiny, Config.spriteStyle(self.mod))
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
    moving = false,
    renderer = renderer,
    state = Config.STATE.AVAILABLE,
  }
  self.order[#self.order + 1] = id
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
  for _, id in ipairs(self.order) do
    local e = self.entities[id]
    if e and e.state == Config.STATE.AVAILABLE then
      Behavior.tick(e, self.game)
    end
  end
  self:refill("land")
  self:refill("water")
end

--- Appends one actor per live entity (engine_patch's `collectActors` hook).
function SpawnManager:collectActors(actors)
  for _, id in ipairs(self.order) do
    local e = self.entities[id]
    if e and e.state ~= Config.STATE.DESPAWNED then
      actors[#actors + 1] = {
        kind = "wild_mon", i = id,
        x = e.px, y = e.py, sortY = e.py, elevation = e.elevation,
        facing = e.facing, walkPhase = e.moving and 1 or 0,
        renderer = e.renderer,
      }
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
--- effect on the very next frame. Cheap: the renderer's path (and so its
--- image/quad cache key) already depends on `style`
--- (SpriteSource.pathFor), so this is just flipping that one field.
function SpawnManager:refreshSpriteStyle()
  local style = Config.spriteStyle(self.mod)
  for _, e in pairs(self.entities) do
    if e.renderer then e.renderer.style = style end
  end
end

function SpawnManager:count()
  local n = 0
  for _ in pairs(self.entities) do n = n + 1 end
  return n
end

return SpawnManager
