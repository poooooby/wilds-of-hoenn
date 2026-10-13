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
local SweetScentHearts = V.require("sweet_scent_hearts")
local SpawnFx = V.require("spawn_fx")

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
  self.filled = false -- the map's first fill is instant; spawns after it arrive (lib/spawn_fx.lua)
end

--- Measures what the player can reach from where they stand (see
--- lib/reachability.lua) and restricts spawning to it. Fails OPEN: without
--- the engine pieces or a start cell, no restriction is applied and the map
--- behaves exactly as before.
function SpawnManager:_rebuildReach()
  self.reach, self.reachCount, self.reachAge = nil, nil, 0
  -- what the area depends on, as measured now (see _checkReach)
  self.reachFp = EnginePatch.reachFingerprint and EnginePatch.reachFingerprint() or nil
  self.reachFpPending = nil
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
    if e.state == Config.STATE.AVAILABLE and not e.engaged
      and not self.source:canStay(e.cellX, e.cellY, e.terrain) then
      doomed[#doomed + 1] = id
    end
  end
  for _, id in ipairs(doomed) do self:despawn(id, { animate = true }) end
end

--- Whether the reachable area should be re-measured now, from what it depends on
--- (EnginePatch.reachFingerprint: Cut / Rock Smash / Strength usable, where the
--- trees, rocks and boulders are). Checked every REACH_CHECK_TICKS; a change is only
--- acted on once nothing has changed for REACH_SETTLE_TICKS, so a boulder puzzle's run
--- of pushes costs one re-measure when the player pauses, not one per push. Without a
--- fingerprint (an engine that hides its object list) it falls back to a plain timer.
function SpawnManager:_reachStale()
  local age = self.reachAge
  if self.reachFp == nil then return age >= Config.REACH_REBUILD_TICKS end
  if age % Config.REACH_CHECK_TICKS ~= 0 then return false end
  local fp = EnginePatch.reachFingerprint()
  if fp == nil then return age >= Config.REACH_REBUILD_TICKS end
  local pending = self.reachFpPending
  if fp == self.reachFp then
    self.reachFpPending = nil -- changed and changed back (a boulder pushed out and in)
    return false
  end
  if not pending or pending.fp ~= fp then
    self.reachFpPending = { fp = fp, since = age } -- (re)start the settle wait
    return false
  end
  return age - pending.since >= Config.REACH_SETTLE_TICKS
end

--- Once per tick: keep the reachable area current. Re-measures when the
--- player stands outside it (they warped, hopped a ledge, were carried
--- somewhere new) and when what it depends on changed and settled (a tree cut,
--- a rock smashed, boulders pushed: _reachStale), and drops spawns that are no
--- longer reachable.
function SpawnManager:_checkReach()
  if not Config.REACHABLE_SPAWNS or not self.source:isEligible() then return end
  self.reachAge = (self.reachAge or 0) + 1
  local p = EnginePatch.playerCell and EnginePatch.playerCell()
  if p and p.moving then return end
  local outside = self.reach and p and not Reachability.has(self.reach, p.x, p.y)
  if outside or (not self.reach and self.reachAge >= 60) or (self.reach and self:_reachStale()) then
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
  self.filled = true
end

function SpawnManager:onMapExited()
  self:clearAll()
end

--- How many Pokemon one terrain keeps out: `row.min` plus one per `row.tilesPer` eligible
--- tiles, at most `row.max` (row = a Config.SPAWN_AMOUNT level; Normal when omitted).
local function targetCount(eligibleCount, row)
  if eligibleCount <= 0 then return 0 end
  row = row or Config.SPAWN_AMOUNT.normal
  local n = row.min + math.floor(eligibleCount / row.tilesPer)
  if n > row.max then n = row.max end
  if n < row.min then n = row.min end
  return n
end
SpawnManager._targetCount = targetCount

--- After the Spawn Amount option is lowered: despawns the Pokemon past the new target,
--- farthest from the player first (never one in a battle or a skirmish).
function SpawnManager:trimToAmount()
  local row = Config.spawnAmount(self.mod)
  local p = EnginePatch.playerCell and EnginePatch.playerCell()
  for _, terrain in ipairs({ "land", "water" }) do
    local want = targetCount(self.source:eligibleCount(terrain), row)
    local list = {}
    for id, e in pairs(self.entities) do
      if e.terrain == terrain and e.state == Config.STATE.AVAILABLE and not e.engaged and not e.lured then
        local d = p and math.max(math.abs(e.cellX - p.x), math.abs(e.cellY - p.y)) or 0
        list[#list + 1] = { id = id, d = d }
      end
    end
    local extra = self:_activeCountFor(terrain) - want
    table.sort(list, function(a, b) if a.d ~= b.d then return a.d > b.d end return a.id < b.id end)
    for i = 1, math.min(extra, #list) do self:despawn(list[i].id, { animate = true }) end
  end
end

--- How many of one terrain count toward the Spawn Amount target: Pokemon that Sweet
--- Scent called over come on top of it while they are lured.
function SpawnManager:_activeCountFor(terrain)
  local n = 0
  for _, e in pairs(self.entities) do
    if e.terrain == terrain and not e.lured and e.state ~= Config.STATE.LEAVING then n = n + 1 end
  end
  return n
end

-- the facing that looks from (x, y) toward (tx, ty)
local function faceToward(x, y, tx, ty)
  local dx, dy = tx - x, ty - y
  if math.abs(dx) > math.abs(dy) then return dx < 0 and "left" or "right" end
  return dy < 0 and "up" or "down"
end

--- Sweet Scent used in the field (engine_patch's `sweetScent` hook, in place of the
--- engine's instant wild battle): calls Config.SWEET_SCENT.min..max wild Pokemon to free
--- spawn cells minDist..maxDist tiles from the player, rolled the way the engine's Sweet
--- Scent rolls (no Repel check, as the engine's has none), lured -- staying put, facing
--- the player, hearts over them -- for lureTicks. Returns how many came, or nil when the
--- visible spawns are not in charge here (option off, no encounters on this map, the
--- Safari Zone): the engine's own Sweet Scent then runs.
function SpawnManager:sweetScent()
  if not Config.enabled(self.mod) or not self.source:isEligible() then return nil end
  if EnginePatch.safariActive and EnginePatch.safariActive() then return nil end
  local p = EnginePatch.playerCell and EnginePatch.playerCell()
  if not p then return nil end
  local cfg = Config.SWEET_SCENT
  local cells = {}
  for _, terrain in ipairs({ "land", "water" }) do
    for _, c in ipairs(self.source:eligibleCells(terrain)) do
      local d = math.max(math.abs(c.x - p.x), math.abs(c.y - p.y))
      if d >= cfg.minDist and d <= cfg.maxDist and self:_cellFree(c.x, c.y) then
        cells[#cells + 1] = { x = c.x, y = c.y, terrain = terrain }
      end
    end
  end
  for i = #cells, 2, -1 do -- shuffle
    local j = math.random(1, i)
    cells[i], cells[j] = cells[j], cells[i]
  end
  local want, came = math.random(cfg.min, cfg.max), 0
  for _, c in ipairs(cells) do
    if came >= want then break end
    if self:_cellFree(c.x, c.y) then
      local enc = EnginePatch.rollSweetScent(self.mapId, c.terrain)
      if enc and not (enc.roamer and self:_roamerOut()) then
        if enc.personality == nil then enc.personality = EnginePatch.randomPersonality() end
        enc = ModernSpawns.apply(self.mapId, c.terrain, enc)
        local id = self.nextId
        if self:_place(c.terrain, c, enc) then
          local e = self.entities[id]
          if e then
            e.lured = { ticks = cfg.lureTicks, age = 0 }
            e.moving = false
            e.facing = faceToward(c.x, c.y, p.x, p.y)
          end
          came = came + 1
        end
      end
    end
  end
  return came
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
  -- The roaming legendary (Suicune / Entei / Raikou, Latias / Latios) is ONE Pokemon:
  -- the roll returns it on every encounter it wins on the roamer's map (roamer.lua,
  -- 1 in encounterOdds), so without this a busy map filled up with copies of it.
  if enc.roamer and self:_roamerOut() then return false end
  -- FireRed / LeafGreen's rules roll no personality: draw it now so the sprite
  -- (shiny, gender) and the battle Pokemon are the same one
  if enc.personality == nil then enc.personality = EnginePatch.randomPersonality() end
  -- Modern Spawns' species for the slot the engine rolled (no-op without it)
  enc = ModernSpawns.apply(self.mapId, terrain, enc)
  if not EnginePatch.repelAllows(enc.level) then return false end
  return self:_place(terrain, cell, enc)
end

--- Whether the roaming legendary is already out on this map (live, or its battle starting).
function SpawnManager:_roamerOut()
  for _, e in pairs(self.entities) do
    if e.roamer and e.state ~= Config.STATE.DESPAWNED then return true end
  end
  return false
end

-- Puts an already rolled encounter on `cell` as a visible wild Pokemon.
-- `keepShiny` skips the shiny roll (the encounter's own `shiny` stands).
function SpawnManager:_place(terrain, cell, enc, keepShiny)
  local dex = FormSource.artKeyFor(self.mod, enc.species)
  if not dex then return false end
  -- the engine's own shiny, plus a shiny chain's bonus (Modern Spawns); never a bonus for
  -- the roamer, whose personality is the engine's saved one
  if not keepShiny then
    enc = Shiny.rollForEncounter(enc, not enc.roamer and ModernSpawns.chainBonus(enc.species) or nil)
  end

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
  -- after the map's first fill, a new Pokemon rises out of the grass / surfaces / fades in
  if self.filled then self:_startFx(self.entities[id], "appear") end
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

--- Tops `terrain` up to its target count. Runs every tick, so it copies nothing: the
--- usual full map returns after a count, and a spawn picks a cell straight from the
--- source's filtered list.
function SpawnManager:refill(terrain)
  local count = self.source:eligibleCount(terrain)
  if count == 0 then return end
  local want = targetCount(count, (Config.spawnAmount(self.mod)))
  local have = self:_activeCountFor(terrain)
  if have >= want then return end
  local attempts = 0
  local maxAttempts = (want - have) * 8 + 8
  while have < want and attempts < maxAttempts do
    attempts = attempts + 1
    local cell = self.source:randomCell(terrain)
    if cell and self:_spawnOne(terrain, cell) then have = have + 1 end
  end
end

--- Advances every live entity one tick (engine_patch's `followerTick` hook,
--- piggybacked on Follower.update so this mod needs no extra tick seam).
function SpawnManager:tick(game)
  self.game = game or self.game
  self:_checkReach()
  local gone
  for _, id in ipairs(self.order) do
    local e = self.entities[id]
    if e and e.rings then -- they outlast the rise, so they keep their own clock
      e.rings.age = e.rings.age + 1
      if e.rings.age >= SpawnFx.ringsTicks() then e.rings = nil end
    end
    -- an `engaged` Pokemon is in a skirmish with the player's Battler
    -- (lib/overworld_battle.lua): it stands its ground and that module animates it
    if e and e.fx then
      -- arriving / leaving (lib/spawn_fx.lua): it finishes a step it was on, nothing else
      if e.moving then Behavior._advanceMove(e) end
      if e.renderer and e.renderer.advance then e.renderer:advance(e.moving) end
      local done = SpawnFx.step(e.fx)
      if done and e.fx.kind == "leave" then
        gone = gone or {}
        gone[#gone + 1] = id -- removed after the loop (despawn reshapes self.order)
      elseif done then
        e.fx = nil
        self:_applyFx(e)
      else
        self:_applyFx(e)
      end
    elseif e and e.state == Config.STATE.AVAILABLE and not e.engaged then
      if e.floater and not e.moving then e.flapClock = e.flapClock + 1 end
      local lure = e.lured
      if lure then
        -- called over by Sweet Scent: it stays put (finishing a step it was on), hearts over
        -- it, until the lure wears off; then it wanders like any other
        lure.ticks, lure.age = lure.ticks - 1, lure.age + 1
        if e.moving then Behavior._advanceMove(e) end
        if lure.ticks <= 0 then e.lured = nil end
      else
        Behavior.tick(e, self.game)
      end
      if e.renderer and e.renderer.advance then e.renderer:advance(e.moving) end
    elseif e and e.engaged and e.moving then
      -- caught mid-step: it finishes the step (the Battler planned for the cell it
      -- lands on), then stands its ground
      Behavior._advanceMove(e)
    end
  end
  for _, id in ipairs(gone or {}) do self:despawn(id) end
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

--- Is the entity close enough to the view to be drawn? (camX, camY) = the view's
--- top-left in world px; no camera = draw everything (an older engine). The margin
--- covers the biggest sprites, which reach well past their 16 px tile. Drawing only
--- these matters with gen3-hd-sprites: every tagged draw takes one of its field
--- layers (12 by default), and off-screen ones used them up.
local CULL_MARGIN = 128
local function inView(e, camX, camY, vw, vh)
  if camX == nil or camY == nil then return true end
  return e.px > camX - CULL_MARGIN and e.px < camX + vw + CULL_MARGIN
    and e.py > camY - CULL_MARGIN and e.py < camY + vh + CULL_MARGIN
end
SpawnManager._inView = inView

--- Every live wild Pokemon's water reflection, for lib/reflection.lua (the
--- drawBehind hook). Off-screen ones are skipped when the camera is given.
function SpawnManager:reflections(list, camX, camY)
  local vw, vh = 240, 160
  if camX ~= nil and EnginePatch.viewSize then vw, vh = EnginePatch.viewSize() end
  for _, id in ipairs(self.order) do
    local e = self.entities[id]
    local r = e and e.state ~= Config.STATE.DESPAWNED and inView(e, camX, camY, vw, vh) and e.renderer
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

function SpawnManager:collectActors(actors, camX, camY)
  local vw, vh = 240, 160
  if camX ~= nil and EnginePatch.viewSize then vw, vh = EnginePatch.viewSize() end
  for _, id in ipairs(self.order) do
    local e = self.entities[id]
    if e and e.state ~= Config.STATE.DESPAWNED and inView(e, camX, camY, vw, vh) then
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
      if e.rings then
        local a = SpawnFx.ringsActor(e.rings.age, e.cellX * 16, e.cellY * 16, e.py, e.elevation, id)
        if a then actors[#actors + 1] = a end
      end
      if e.fx and e.fx.rustle then
        local a = SpawnFx.rustleActor(e.fx.rustle.sheet, e.fx.rustle.frames, e.fx.t,
          e.cellX * 16, e.cellY * 16, e.py, e.elevation, id)
        if a then actors[#actors + 1] = a end
      end
      if e.lured then
        -- just above the highest point its art reaches in any frame (headLift), so the
        -- idle / walk animation never covers the hearts, plus a 4 px gap
        local r = e.renderer
        local lift = r and r.headLift and r:headLift()
          or (r and r.visualHeight and r:visualHeight()) or (r and r.frameHeight and r:frameHeight()) or 20
        actors[#actors + 1] = SweetScentHearts.actor(e.px, e.py, math.max(10, math.min(96, (lift or 20) + 4)),
          e.lured.age, e.lured.ticks, e.elevation, id)
      end
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
    -- never the roaming legendary: it is met only in a real battle, which keeps its saved state
    if e and e.state == Config.STATE.AVAILABLE and not e.engaged and not e.noFight and not e.roamer and not e.fx then
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

--- How a Pokemon on this tile arrives / leaves: "water", "grass" or "fade".
function SpawnManager:_fxMode(e)
  if e.terrain == "water" or (EnginePatch.isWater and EnginePatch.isWater(e.cellX, e.cellY)) then return "water" end
  if EnginePatch.isGrass and EnginePatch.isGrass(e.cellX, e.cellY) then return "grass" end
  return "fade"
end

--- Starts entity `e` arriving ("appear") or leaving ("leave"): the renderer shows the first
--- frame of it at once; grass rustles, water ripples (lib/spawn_fx.lua).
function SpawnManager:_startFx(e, kind)
  if not e then return end
  local cfg = Config.SPAWN_FX or {}
  local mode = self:_fxMode(e)
  local fx = SpawnFx.new(kind, mode, kind == "leave" and cfg.leaveTicks or cfg.appearTicks)
  if mode == "grass" and EnginePatch.grassRustle then
    local sheet, frames = EnginePatch.grassRustle(e.cellX, e.cellY)
    if sheet then fx.rustle = { sheet = sheet, frames = frames } end
  elseif mode == "water" then
    e.rings = { age = 0 } -- three rings growing outward (SpawnFx.ringsActor), on their own clock
  end
  e.fx = fx
  self:_applyFx(e)
end

-- the effect's current look on the renderer (sink / alpha), or cleared when it is over
function SpawnManager:_applyFx(e)
  local r = e.renderer
  if not r then return end
  if not e.fx then
    if r.act and r.act.spawnFx then r.act = nil end
    r.alpha = nil
    return
  end
  local v = SpawnFx.visual(e.fx)
  if v.sink then r.act = { sink = v.sink, spawnFx = true } end
  r.alpha = v.alpha
end

--- Removes a wild Pokemon. `opts.animate`: it sinks back into the grass / water or fades
--- out first (state LEAVING: drawn, but no longer met, counted or fought), then goes.
--- Without it -- after a battle, on a map change -- it is gone at once.
function SpawnManager:despawn(id, opts)
  local e = self.entities[id]
  if not e then return end
  if opts and opts.animate and e.state == Config.STATE.AVAILABLE then
    e.state = Config.STATE.LEAVING
    e.lured = nil
    self:_startFx(e, "leave")
    return
  end
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
