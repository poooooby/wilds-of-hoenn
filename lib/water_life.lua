-- Life in the water (the Water Life option): ambient, never met or fought, drawn from the
-- species of this map's own fishing and Surf tables (re-read now and then: Modern Spawns
-- writes its own after a map loads).
--
--   leapers -- small fish (Config.WATER_LIFE: the Water 2 egg group, the fish, under 1 m,
--              plus Feebas, minus Horsea / Octillery / Inkay) jump out of open water in an
--              arc and dive back in, a splash of droplets and a ripple each way. PMDCollab
--              fish play their Hop animation through it (baked "hop" sheet), HGSS ones are
--              carried along the arc.
--   whales  -- Wailmer and Wailord rise slowly to the surface (drawn swimming, cut at the
--              waterline), lie there or drift a tile, blow a spray from their blowhole once
--              or twice, and sink back under.
-- Only in open water in view (water all round, nothing on it, not next to the player), at
-- most a couple at once. Drawn as ordinary field actors at the water's level.
local V = ...
local Config = V.require("config")
local EnginePatch = V.require("engine_patch")
local SpawnFx = V.require("spawn_fx")
local SpriteSource = V.require("sprite_source")
local FormSource = V.require("form_source")
local RendererFactory = V.require("renderer_factory")
local RecallMath = V.require("recall_math")
local FlightPath = V.require("flight_path")
local SkyDraw = V.require("sky_draw")
local ActorRenderer = V.require("actor_renderer")

local WaterLife = {}
WaterLife.__index = WaterLife

local POOL_REFRESH = 600

--- `deps` (all optional, for tests): rng(a, b), occupied(x, y), viewSize(), playerCell().
function WaterLife.new(mod, deps)
  deps = deps or {}
  return setmetatable({
    mod = mod, rng = deps.rng or math.random, occupied = deps.occupied,
    viewSize = deps.viewSize or function()
      if EnginePatch.viewSize then return EnginePatch.viewSize() end
      return 240, 160
    end,
    playerCell = deps.playerCell or function() return EnginePatch.playerCell and EnginePatch.playerCell() or nil end,
    creatures = {}, nextId = 1, allowed = false, fish = {}, whales = {}, timers = {},
  }, WaterLife)
end

local function between(rng, r) return rng(r[1], r[2]) end

-- a swimming fish's body wiggle this tick: a sway across the way it faces (sideways for
-- one swimming left / right, up and down for one swimming up / down)
local function sway(view, swimming)
  if not swimming then view.swayX, view.swayY = 0, 0 return end
  local w = Config.WATER_LIFE.swim.wiggle
  local d = math.sin((view.flapClock or 0) / w.ticks * math.pi * 2) * w.px
  if view.facing == "left" or view.facing == "right" then
    view.swayX, view.swayY = 0, d
  else
    view.swayX, view.swayY = d, 0
  end
end
WaterLife._sway = sway


--- Is this species one of the small fish that leap? Pure given the engine answers.
function WaterLife.isFish(species)
  local cfg = Config.WATER_LIFE
  local nat = EnginePatch.nationalFor and EnginePatch.nationalFor(species)
  if nat and cfg.notFish[nat] then return false end
  if nat and cfg.fishExtra[nat] then return true end
  local g1, g2 = nil, nil
  if EnginePatch.eggGroups then g1, g2 = EnginePatch.eggGroups(species) end
  if not (g1 == 12 or g2 == 12) then return false end -- Water 2: the fish
  local h = EnginePatch.heightDm and EnginePatch.heightDm(species)
  return h == nil or h < cfg.maxFishHeightDm
end

--- One of the fish that swim by under the sea (Dive maps)? The Water 2 egg group, no
--- legendary (egg group 15, Undiscovered), nothing massive (Config.WATER_LIFE.swim).
function WaterLife.isSwimmer(species)
  if WaterLife.isWhale(species) then return false end
  local nat = EnginePatch.nationalFor and EnginePatch.nationalFor(species)
  local cfg = Config.WATER_LIFE
  if nat and cfg.notFish[nat] then return false end
  local g1, g2 = nil, nil
  if EnginePatch.eggGroups then g1, g2 = EnginePatch.eggGroups(species) end
  if g1 == 15 or g2 == 15 then return false end
  if not (g1 == 12 or g2 == 12 or (nat and cfg.fishExtra[nat])) then return false end
  local h = EnginePatch.heightDm and EnginePatch.heightDm(species)
  return h == nil or h <= cfg.swim.maxHeightDm
end

-- every species that may swim by under the sea, worked out once: each national dex number
-- the game knows a species for (National Dex Gen 3 adds the later generations) that passes
-- isSwimmer. Rebuilt when it came out empty (the species data was not loaded yet).
local swimmerCache
function WaterLife.allSwimmers(maxNational)
  if swimmerCache and #swimmerCache > 0 then return swimmerCache end
  local out, seen = {}, {}
  for nat = 1, maxNational or 1025 do
    local s = EnginePatch.speciesForNational and EnginePatch.speciesForNational(nat)
    if s and not seen[s] then
      seen[s] = true
      if WaterLife.isSwimmer(s) then out[#out + 1] = s end
    end
  end
  swimmerCache = out
  return out
end
function WaterLife._resetSwimmers() swimmerCache = nil end

--- Wailmer / Wailord?
function WaterLife.isWhale(species)
  local nat = EnginePatch.nationalFor and EnginePatch.nationalFor(species)
  return nat ~= nil and Config.WATER_LIFE.whales[nat] == true
end

local function addFrom(list, seen, t)
  if type(t) ~= "table" then return end
  for _, area in ipairs({ "fishing", "water", "oldRod", "goodRod", "superRod" }) do
    local a = t[area]
    local slots = type(a) == "table" and (a.slots or a.mons or a) or nil
    if type(slots) == "table" then
      for _, s in ipairs(slots) do
        local species = type(s) == "table" and tonumber(s.species or s[1])
        if species and species > 0 and not seen[species] then
          seen[species] = true
          list[#list + 1] = species
        end
      end
    end
  end
end

--- The fish and whales of `mapId`'s fishing and Surf tables: two lists of species.
function WaterLife.poolFor(mapId)
  local all, seen = {}, {}
  addFrom(all, seen, EnginePatch.tableFor(mapId))
  local fish, whales = {}, {}
  for _, s in ipairs(all) do
    if WaterLife.isWhale(s) then whales[#whales + 1] = s
    elseif WaterLife.isFish(s) then fish[#fish + 1] = s end
  end
  return fish, whales
end

function WaterLife:_refreshPool()
  self.poolAge = 0
  self.swimmers = {}
  if self.underwater then
    -- every sea fish the game knows (National Dex included), not just this map's table
    self.swimmers = WaterLife.allSwimmers()
    self.fish, self.whales = {}, {}
  else
    self.fish, self.whales = WaterLife.poolFor(self.mapId)
  end
end

function WaterLife:clear()
  for _, c in ipairs(self.creatures or {}) do if c.kind == "swim" then SkyDraw.release(c) end end
  self.creatures = {}
end

function WaterLife:onMapEntered(mapId)
  self:clear()
  self.mapId = mapId
  local mt = EnginePatch.mapType and EnginePatch.mapType()
  self.allowed = Config.waterLife(self.mod) and mt ~= 8 and mt ~= 9 -- not indoors
  self.underwater = mt == 5 -- a Dive map: fish swim by under the sea
  if not self.allowed then return end
  self:_refreshPool()
  local cfg, rng = Config.WATER_LIFE, self.rng
  if self.underwater then
    self.timers = { swim = math.floor(between(rng, cfg.swim.every) / 4) }
  else
    self.timers = { leap = math.floor(between(rng, cfg.leap.every) / 3), whale = math.floor(between(rng, cfg.whale.every) / 3) }
  end
end

function WaterLife:onMapExited()
  self:clear()
  self.allowed = false
end

function WaterLife:onOptionChanged(mapId)
  if Config.waterLife(self.mod) then self:onMapEntered(mapId or self.mapId) else self:onMapExited() end
end

-- ------- where -------------------------------------------------------------------

--- An open water cell in view for a creature `wide` tiles to each side: water there and all
--- round, nothing on it or next to it, not too near the player or another creature. nil
--- when none was found.
function WaterLife:_waterCell(wide)
  local cam, rng = self.cam, self.rng
  if not cam then return nil end
  local vw, vh = self.viewSize()
  local x0, y0 = math.ceil(cam.x / 16) + 1 + wide, math.ceil(cam.y / 16) + 2
  local x1, y1 = math.floor((cam.x + vw) / 16) - 2 - wide, math.floor((cam.y + vh) / 16) - 2
  if x1 < x0 or y1 < y0 then return nil end
  local p = self.playerCell and self.playerCell()
  local minD = Config.WATER_LIFE.minPlayerDist
  for _ = 1, 30 do
    local x, y = rng(x0, x1), rng(y0, y1)
    local ok = not (p and math.max(math.abs(p.x - x), math.abs(p.y - y)) < minD + wide)
    for dy = -1, 1 do
      for dx = -wide - 1, wide + 1 do
        if ok and not (EnginePatch.isWater(x + dx, y + dy)
            and not (self.occupied and self.occupied(x + dx, y + dy))) then ok = false end
      end
    end
    if ok and EnginePatch.objectOn and EnginePatch.objectOn(x, y) then ok = false end
    if ok then
      for _, c in ipairs(self.creatures) do
        if math.abs(c.cx - x) <= wide + 2 and math.abs(c.cy - y) <= 2 then ok = false end
      end
    end
    if ok then return x, y end
  end
  return nil
end

-- ------- splash and spray (drawn in code) ------------------------------------------

--- The droplets of a splash `age` ticks in: { {dx, dy, alpha}, ... } around the point it
--- left the water (dy negative = up). `seed` varies them. Pure (tested).
function WaterLife.splash(age, seed)
  local out = {}
  if age < 0 or age >= 26 then return out end
  local n = 8
  for i = 1, n do
    local a = ((i - 1) / n) * math.pi + (seed % 7) * 0.05 -- fanned out over the top half
    local v = 1.1 + ((seed * 31 + i * 17) % 10) / 12
    local vx, vy = math.cos(a) * v, -math.sin(a) * v * 1.6
    local dy = vy * age + 0.09 * age * age
    if dy <= 2 then
      out[#out + 1] = { math.floor(vx * age + 0.5), math.floor(dy + 0.5), 1 - age / 26 }
    end
  end
  return out
end

--- A whale's spout `age` ticks into a spray lasting `n`: a fountain of droplets thrown up
--- from the blowhole and fanning out as they fall, { {dx, dy, alpha, size}, ... } (size 2 =
--- a bigger drop, near the start of its flight). Pure (tested).
function WaterLife.spray(age, n, seed)
  local out = {}
  local fade = age < n and 1 or math.max(0, 1 - (age - n) / 30)
  if fade <= 0 then return out end
  for k = 0, 120 do
    local born = k * 0.4                       -- about 2-3 drops a tick while it blows
    local t = age - born
    if t >= 0 and t < 34 and born < n * 0.7 then
      local side = ((k * 7 + seed) % 9) - 4      -- -4 .. 4: a fan
      local vx = side * 0.16
      local vy = -(3.0 + ((k * 13 + seed) % 9) * 0.1)
      local dy = vy * t + 0.12 * t * t
      if dy <= 2 then
        out[#out + 1] = { math.floor(vx * t + 0.5), math.floor(dy + 0.5), (1 - t / 34) * fade, t < 10 and 2 or 1 }
      end
    end
  end
  return out
end

local function dropletActor(list, gx, gy, sortY, id)
  return {
    kind = "ow_water_droplets", elevation = 3, sortY = sortY, x = gx, y = gy, i = 96000 + id,
    draw = function(_, camX, camY)
      local g = love and love.graphics
      if not (g and g.rectangle) then return end
      local r, gg, b, a = g.getColor()
      for _, d in ipairs(list) do
        local size = d[4] or 1
        g.setColor(0.88, 0.96, 1.0, d[3])
        g.rectangle("fill", math.floor(gx + d[1] - camX), math.floor(gy + d[2] - camY), size, size)
      end
      g.setColor(r, gg, b, a)
    end,
  }
end

-- ------- creatures -------------------------------------------------------------------

function WaterLife:_renderer(species, presentation)
  local dex = FormSource.artKeyFor(self.mod, species)
  if not dex then return nil end
  return RendererFactory.new(self.mod, dex, false, Config.spriteStyle(self.mod), presentation)
end

function WaterLife:_splashAt(c, x, y)
  if EnginePatch.startRipple then EnginePatch.startRipple(x, y) end
  c.rings = c.rings or {}
  c.rings[#c.rings + 1] = { x = x, y = y, age = 0 }
  c.splashes = c.splashes or {}
  c.splashes[#c.splashes + 1] = { x = x, y = y, age = 0 }
end

function WaterLife:_spawnLeaper()
  local cfg, rng = Config.WATER_LIFE.leap, self.rng
  if #self.fish == 0 or self:count("leap") >= cfg.max then return false end
  local x, y = self:_waterCell(0)
  if not x then return false end
  local r = self:_renderer(self.fish[rng(1, #self.fish)], SpriteSource.PRESENTATION_LAND)
  if not r then return false end
  local dir = rng(0, 1) == 0 and -1 or 1
  local c = { kind = "leap", id = self.nextId, cx = x, cy = y, renderer = r, t = 0,
              n = between(rng, cfg.ticks), dir = dir, facing = dir < 0 and "left" or "right" }
  self.nextId = self.nextId + 1
  if r.isPmd then r.swimming = false end
  self:_splashAt(c, x, y)
  self.creatures[#self.creatures + 1] = c
  return true
end

function WaterLife:_spawnWhale()
  local cfg, rng = Config.WATER_LIFE.whale, self.rng
  if #self.whales == 0 or self:count("whale") >= cfg.max then return false end
  local x, y = self:_waterCell(1)
  if not x then return false end
  local r = self:_renderer(self.whales[rng(1, #self.whales)], SpriteSource.PRESENTATION_SWIMMING)
  if not r then return false end
  local drift = between(rng, cfg.drift) * (rng(0, 1) == 0 and -1 or 1)
  local stay = between(rng, cfg.stay)
  local sprays, times = between(rng, cfg.sprays), {}
  for k = 1, sprays do times[k] = cfg.riseTicks + math.floor(stay * k / (sprays + 1)) end
  local c = { kind = "whale", id = self.nextId, cx = x, cy = y, renderer = r, t = 0, stay = stay,
              n = cfg.riseTicks * 2 + stay, drift = drift, sprayAt = times,
              facing = drift < 0 and "left" or (drift > 0 and "right" or (rng(0, 1) == 0 and "left" or "right")) }
  self.nextId = self.nextId + 1
  self:_splashAt(c, x, y)
  self.creatures[#self.creatures + 1] = c
  return true
end

-- ------- under the sea: fish swimming by as shadows -------------------------------

--- Starts a fish (or a small school of them) swimming across the view under the sea: from
--- off screen on one side to off screen on the other, curving and wiggling, at a depth.
function WaterLife:_spawnSwimmer()
  local cfg, rng = Config.WATER_LIFE.swim, self.rng
  if not self.cam or #self.swimmers == 0 or self:count("swim") >= cfg.max then return false end
  local species = self.swimmers[rng(1, #self.swimmers)]
  local h = rng(0, 100) / 100
  local look = FlightPath.look(h, cfg.layers)
  local vw, vh = self.viewSize()
  local ax, ay, side = FlightPath.edgePoint(vw, vh, 48, rng)
  local bx, by = FlightPath.edgePoint(vw, vh, 48, rng, FlightPath.OPPOSITE[side])
  local fx, fy = FlightPath.fromScreen(ax, ay, look.parallax, self.cam.x, self.cam.y, vw, vh)
  local tx, ty = FlightPath.fromScreen(bx, by, look.parallax, self.cam.x, self.cam.y, vw, vh)
  local n = between(rng, cfg.ticks)
  local curve = rng(-cfg.curve, cfg.curve)
  local wave = { cfg.wave.amp, between(rng, cfg.wave.cycles) }
  local members = 1
  local hd = EnginePatch.heightDm and EnginePatch.heightDm(species)
  if (hd == nil or hd <= cfg.schoolMaxHeightDm) and rng(1, 100) <= cfg.schoolChance then
    members = between(rng, cfg.school)
  end
  local made = 0
  for k = 1, members do
    local r = self:_renderer(species, SpriteSource.PRESENTATION_LAND)
    if r then
      r.silhouette = true -- a dark shape under the water
      if r.isPmd then r.swimming = false end
      local ox = k == 1 and 0 or rng(-cfg.schoolSpread, cfg.schoolSpread)
      local oy = k == 1 and 0 or rng(-cfg.schoolSpread, cfg.schoolSpread)
      local delay = k == 1 and 0 or rng(0, 20)
      local c = {
        kind = "swim", id = self.nextId, renderer = r, layers = cfg.layers, h = h, x = fx + ox, y = fy + oy,
        cx = 0, cy = 0, flapClock = rng(0, 10),
        plan = FlightPath.plan({
          { type = "sit", at = { x = fx + ox, y = fy + oy }, n = delay + 1 }, -- a school spreads out a little
          { type = "fly", from = { x = fx + ox, y = fy + oy, h = h }, to = { x = tx + ox, y = ty + oy, h = h },
            n = n, curve = curve, wave = wave },
        }, rng),
        bubbles = {}, nextBubble = between(rng, cfg.bubbleEvery),
      }
      self.nextId = self.nextId + 1
      self.creatures[#self.creatures + 1] = c
      made = made + 1
    end
  end
  return made > 0
end

function WaterLife:_tickSwimmer(c)
  local cfg = Config.WATER_LIFE.swim
  local s = FlightPath.step(c.plan)
  if not s then return false end
  c.x, c.y, c.h, c.facing = s.x or c.x, s.y or c.y, c.h, s.facing
  c.lift, c.hop = 0, 0
  local r = c.renderer
  c.flapClock = c.flapClock + 1
  if r.isPmd then
    if r.advance then r:advance(true) end
    c.pose = ActorRenderer.POSE_STAND
  else
    c.pose = (math.floor(c.flapClock / 8) % 2 == 0) and ActorRenderer.POSE_WALK_A or ActorRenderer.POSE_WALK_B
  end
  sway(c, true)
  if SkyDraw.blurred(c.h) then SkyDraw.prepare(c) end
  -- bubbles rising from it now and then
  c.nextBubble = c.nextBubble - 1
  if c.nextBubble <= 0 then
    c.bubbles[#c.bubbles + 1] = { x = c.x + 8 + self.rng(-3, 3), y = c.y + 6, age = 0, seed = self.rng(0, 99) }
    c.nextBubble = between(self.rng, cfg.bubbleEvery)
  end
  local keep = {}
  for _, b in ipairs(c.bubbles) do
    b.age = b.age + 1
    if b.age < cfg.bubbleTicks then keep[#keep + 1] = b end
  end
  c.bubbles = keep
  return true
end

--- A bubble `age` ticks after it left a fish: dx, dy, alpha (rising, wobbling, fading).
--- Pure (tested).
function WaterLife.bubble(age, seed)
  local life = Config.WATER_LIFE.swim.bubbleTicks
  return math.floor(math.sin(age / 6 + (seed or 0)) * 1.5 + 0.5), -math.floor(age * 0.45), math.max(0, 1 - age / life)
end

local function bubbleActor(list, id)
  return {
    kind = "ow_bubbles", elevation = 3, sortY = 1e9, x = 0, y = 0, i = 97000 + id,
    fixedPriority = true, priority = 1, subpriority = 0,
    draw = function(_, camX, camY)
      local g = love and love.graphics
      if not (g and g.rectangle) then return end
      local r, gg, b, a = g.getColor()
      for _, bub in ipairs(list) do
        local dx, dy, alpha = WaterLife.bubble(bub.age, bub.seed)
        local bx, by = math.floor(bub.x + dx - camX), math.floor(bub.y + dy - camY)
        g.setColor(0.85, 0.95, 1.0, alpha * 0.9)
        g.rectangle("fill", bx, by - 1, 1, 1)
        g.rectangle("fill", bx - 1, by, 1, 1)
        g.rectangle("fill", bx + 1, by, 1, 1)
        g.rectangle("fill", bx, by + 1, 1, 1)
      end
      g.setColor(r, gg, b, a)
    end,
  }
end

-- ------- under the sea: wild fish spawns arriving / leaving by swimming --------------
-- The same interface lib/sky_flyers.lua gives the birds (planArrival / planDeparture /
-- stepFlight / pushFlight / endFlight / restore), driven by lib/spawn_manager.lua for an
-- fx of mode "swim": a fish glides in under the water as a dark shape from off screen,
-- wiggling and curving round the player, then takes shape on its tile; leaving, it fades
-- back to a shadow and swims off.

--- May wild Pokemon `e` arrive / leave by swimming here: a Dive map, Water Life on, one of
--- the fish (isSwimmer), more than Config.FLYERS.swoop.clearRadius tiles from the player.
function WaterLife:canSwim(e)
  if not (self.allowed and self.underwater and Config.waterLife(self.mod) and e and not e.roamer) then return false end
  if not WaterLife.isSwimmer(e.species) then return false end
  local p = self.playerCell and self.playerCell()
  return not p or math.max(math.abs(p.x - e.cellX), math.abs(p.y - e.cellY)) > Config.FLYERS.swoop.clearRadius
end

-- a point off screen for a swim onto / off (tx, ty) at depth h, on the side away from the
-- player, with a curve bending away from them
function WaterLife:_swimEnd(tx, ty, h)
  local cfg, rng = Config.WATER_LIFE.swim, self.rng
  local cam = self.cam
  local vw, vh = self.viewSize()
  local look = FlightPath.look(h, cfg.layers)
  local p = self.playerCell and self.playerCell()
  local plx, ply = p and p.x * 16 or tx, p and p.y * 16 or ty
  local base = (math.atan2 or math.atan)(ty - ply, tx - plx)
  if tx == plx and ty == ply then base = rng(0, 359) * math.pi / 180 end
  for _ = 1, 12 do
    local th = base + rng(-70, 70) * math.pi / 180
    local cx, cy = math.cos(th), math.sin(th)
    for d = 48, 1200, 16 do
      local px, py = tx + cx * d, ty + cy * d
      local off = true
      if cam then
        local qx, qy = FlightPath.toScreen(px, py, look.parallax, cam.x, cam.y, vw, vh)
        off = qx < -40 or qx > vw + 40 or qy < -40 or qy > vh + 40
      elseif d < 200 then
        off = false
      end
      if off then
        local a, b = { x = px, y = py }, { x = tx, y = ty }
        local c = rng(10, 30)
        local SkyFlyers = V.require("sky_flyers")
        if SkyFlyers._closestTo(a, b, -c, plx, ply) > SkyFlyers._closestTo(a, b, c, plx, ply) then c = -c end
        return { x = px, y = py, h = h }, c
      end
    end
  end
  return { x = tx + 200, y = ty, h = h }, 20
end

local function swimView(e, mod)
  return { id = e.id, renderer = e.renderer, layers = Config.WATER_LIFE.swim.layers, x = e.px, y = e.py, h = 0,
           silhouette = true, flapClock = 0, baseSilhouette = e.renderer and e.renderer.silhouette }
end

--- Wild fish `e` (just placed on its cell) swims in under the water and takes shape.
function WaterLife:planArrival(e)
  local cfg, rng = Config.WATER_LIFE.swim, self.rng
  local h = rng(30, 70) / 100
  local tx, ty = e.cellX * 16, e.cellY * 16
  local start, curve = self:_swimEnd(tx, ty, h)
  local phases = {
    { type = "fly", from = start, to = { x = tx, y = ty, h = 0 }, n = between(rng, { 150, 240 }), curve = curve,
      wave = { cfg.wave.amp, between(rng, cfg.wave.cycles) } },
    { type = "sit", at = { x = tx, y = ty }, n = 24, solid = "in", fidget = { 999, 999 } },
  }
  return { kind = "land", mode = "swim", plan = FlightPath.plan(phases, rng), view = swimView(e, self.mod) }
end

--- Wild fish `e` fades back to a shadow and swims off.
function WaterLife:planDeparture(e)
  local cfg, rng = Config.WATER_LIFE.swim, self.rng
  local h = rng(30, 70) / 100
  local x, y = e.cellX * 16, e.cellY * 16
  local stop, curve = self:_swimEnd(x, y, h)
  local phases = {
    { type = "sit", at = { x = x, y = y }, n = 24, solid = "out", fidget = { 999, 999 } },
    { type = "fly", from = { x = x, y = y, h = 0 }, to = stop, n = between(rng, { 150, 240 }), curve = -curve,
      wave = { cfg.wave.amp, between(rng, cfg.wave.cycles) }, fadeOut = true },
  }
  local view = swimView(e, self.mod)
  view.solid = 1
  return { kind = "leave", mode = "swim", plan = FlightPath.plan(phases, rng), view = view }
end

--- One tick of a fish swimming in / out. True once it is over.
function WaterLife:stepFlight(fx)
  local view = fx.view
  local ph = FlightPath.current(fx.plan)
  local s = FlightPath.step(fx.plan)
  if not s then return true end
  view.x, view.y, view.h, view.facing = s.x or view.x, s.y or view.y, s.h or 0, s.facing
  view.alpha = s.alpha
  view.lift, view.hop = 0, 0
  if ph and ph.solid then
    local p = math.min(1, fx.plan.t == 0 and 1 or fx.plan.t / ph.n)
    view.solid = ph.solid == "in" and p or (1 - p)
  elseif ph and ph.type == "fly" then
    view.solid = nil
  end
  local r = view.renderer
  view.flapClock = view.flapClock + 1
  if r then
    if r.isPmd then
      r.swimming = false
      if r.advance then r:advance(ph and ph.type == "fly") end
      view.pose = ActorRenderer.POSE_STAND
    else
      view.pose = (ph and ph.type == "fly")
        and ((math.floor(view.flapClock / 8) % 2 == 0) and ActorRenderer.POSE_WALK_A or ActorRenderer.POSE_WALK_B)
        or ActorRenderer.POSE_STAND
    end
  end
  sway(view, ph and ph.type == "fly")
  if SkyDraw.blurred(view.h) then SkyDraw.prepare(view) end
  return false
end

--- Appends the actors of a fish swimming in / out: its shadow, and while it takes shape
--- (or fades) the solid sprite over it.
function WaterLife:pushFlight(fx, actors, camX, camY)
  local view = fx.view
  local vw, vh = self.viewSize()
  if view.solid then
    local shadow = setmetatable({ alpha = (1 - view.solid) * (view.alpha or 1), silhouette = true }, { __index = view })
    local solid = setmetatable({ id = view.id + 50000, alpha = view.solid * (view.alpha or 1), silhouette = false },
      { __index = view })
    if shadow.alpha > 0.01 then SkyDraw.push(actors, shadow, camX or 0, camY or 0, vw, vh) end
    if solid.alpha > 0.01 then SkyDraw.push(actors, solid, camX or 0, camY or 0, vw, vh) end
  else
    SkyDraw.push(actors, view, camX or 0, camY or 0, vw, vh)
  end
end

function WaterLife:endFlight(fx)
  if fx and fx.view then SkyDraw.release(fx.view) end
end

--- Puts a renderer back the way it draws on its tile.
function WaterLife.restore(view)
  local r = view and view.renderer
  if r then
    if r.isPmd and r.advance then r:advance(false) end
  end
  SkyDraw.release(view)
end

--- How many of `kind` are out.
function WaterLife:count(kind)
  local n = 0
  for _, c in ipairs(self.creatures) do if not kind or c.kind == kind then n = n + 1 end end
  return n
end

-- a creature's place and look this tick: world x, y of its tile, the act table
local function leapState(c, cfg)
  local p = math.min(1, c.t / c.n)
  local r = c.renderer
  local height = (r and r.isPmd) and cfg.pmdHeight or cfg.height
  local x = c.cx * 16 + c.dir * cfg.drift * p
  local dy = -math.sin(math.pi * p) * height
  -- breaking the surface on the way out and in
  local sink = 0
  if p < 0.15 then sink = 1 - p / 0.15 elseif p > 0.85 then sink = (p - 0.85) / 0.15 end
  return x, c.cy * 16, { dy = dy, sink = math.min(0.95, sink) }
end

local function whaleState(c, cfg)
  local rise = cfg.riseTicks
  local sink
  if c.t < rise then sink = 1 - RecallMath.ease(c.t / rise)
  elseif c.t > rise + c.stay then sink = RecallMath.ease(math.min(1, (c.t - rise - c.stay) / rise))
  else sink = 0 end
  local p = math.max(0, math.min(1, (c.t - rise) / math.max(1, c.stay)))
  local x = c.cx * 16 + c.drift * 16 * p
  return x, c.cy * 16, { sink = math.min(0.98, sink) }
end
WaterLife._leapState, WaterLife._whaleState = leapState, whaleState

--- One tick: new creatures on their timers, every one a step on.
function WaterLife:tick()
  if not self.allowed then return end
  self.poolAge = (self.poolAge or 0) + 1
  if self.poolAge >= POOL_REFRESH then self:_refreshPool() end
  local cfg = Config.WATER_LIFE
  for kind, t in pairs(self.timers) do
    t = t - 1
    if t <= 0 then
      if kind == "leap" then self:_spawnLeaper()
      elseif kind == "whale" then self:_spawnWhale()
      else self:_spawnSwimmer() end
      t = between(self.rng, cfg[kind].every)
    end
    self.timers[kind] = t
  end
  local keep = {}
  for _, c in ipairs(self.creatures) do
    if c.kind == "swim" then
      if self:_tickSwimmer(c) then keep[#keep + 1] = c else SkyDraw.release(c) end
      goto continue
    end
    c.t = c.t + 1
    local r = c.renderer
    if c.kind == "leap" then
      if r and r.isPmd then r:advanceAs("hop", 1, "idle") end
      if c.t == c.n then self:_splashAt(c, math.floor((c.cx * 16 + c.dir * cfg.leap.drift) / 16 + 0.5), c.cy) end
    else
      if r and r.advance then r:advance(c.drift ~= 0 and c.t > cfg.whale.riseTicks and c.t < cfg.whale.riseTicks + c.stay) end
      for _, at in ipairs(c.sprayAt) do
        if c.t == at then c.sprays = c.sprays or {} c.sprays[#c.sprays + 1] = { age = 0 } end
      end
      if c.t == cfg.whale.riseTicks + c.stay + 1 then
        self:_splashAt(c, math.floor((c.cx * 16 + c.drift * 16) / 16 + 0.5), c.cy)
      end
    end
    for _, list in ipairs({ c.rings or {}, c.splashes or {}, c.sprays or {} }) do
      for _, fx in ipairs(list) do fx.age = fx.age + 1 end
    end
    local alive = c.t < c.n + 40 -- (the last splash plays out)
    if alive then keep[#keep + 1] = c end
    ::continue::
  end
  self.creatures = keep
end

--- Appends every creature's actors; remembers the camera for placing new ones.
function WaterLife:collectActors(actors, camX, camY)
  if camX ~= nil and camY ~= nil then self.cam = { x = camX, y = camY } end
  local cfg = Config.WATER_LIFE
  local vw, vh = self.viewSize()
  for _, c in ipairs(self.creatures) do
    if c.kind == "swim" then
      SkyDraw.push(actors, c, camX or 0, camY or 0, vw, vh)
      if #c.bubbles > 0 then actors[#actors + 1] = bubbleActor(c.bubbles, c.id) end
      goto continue
    end
    local x, y, act
    if c.kind == "leap" then x, y, act = leapState(c, cfg.leap) else x, y, act = whaleState(c, cfg.whale) end
    if c.t <= c.n and act.sink < 0.98 then
      local r = c.renderer
      actors[#actors + 1] = {
        kind = "ow_water_life", x = x, y = y, sortY = y, elevation = 3, i = 95500 + c.id,
        facing = c.facing, walkPhase = "stand",
        draw = function(_, cX, cY)
          local old = r.act
          r.act = act
          r:draw(x, y, cX, cY, c.facing, "stand")
          r.act = old
        end,
      }
    end
    for _, rg in ipairs(c.rings or {}) do
      local a = SpawnFx.ringsActor(rg.age, rg.x * 16, rg.y * 16, rg.y * 16, 3, 96500 + c.id)
      if a then actors[#actors + 1] = a end
    end
    for _, s in ipairs(c.splashes or {}) do
      local d = WaterLife.splash(s.age, c.id)
      if #d > 0 then actors[#actors + 1] = dropletActor(d, s.x * 16 + 8, s.y * 16 + 13, s.y * 16 + 1, c.id) end
    end
    if c.sprays then
      local r = c.renderer
      local lift = (r and r.headLift and r:headLift()) or 24
      for _, s in ipairs(c.sprays) do
        local d = WaterLife.spray(s.age, cfg.whale.sprayTicks, c.id)
        if #d > 0 then actors[#actors + 1] = dropletActor(d, x + 8, y + 16 - lift + 2, y + 2, c.id) end
      end
    end
    ::continue::
  end
end

return WaterLife
