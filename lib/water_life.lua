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
  self.fish, self.whales = WaterLife.poolFor(self.mapId)
end

function WaterLife:clear()
  self.creatures = {}
end

function WaterLife:onMapEntered(mapId)
  self:clear()
  self.mapId = mapId
  local mt = EnginePatch.mapType and EnginePatch.mapType()
  self.allowed = Config.waterLife(self.mod) and mt ~= 8 and mt ~= 9 -- not indoors
  if not self.allowed then return end
  self:_refreshPool()
  local cfg, rng = Config.WATER_LIFE, self.rng
  self.timers = { leap = math.floor(between(rng, cfg.leap.every) / 3), whale = math.floor(between(rng, cfg.whale.every) / 3) }
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
      if kind == "leap" then self:_spawnLeaper() else self:_spawnWhale() end
      t = between(self.rng, cfg[kind].every)
    end
    self.timers[kind] = t
  end
  local keep = {}
  for _, c in ipairs(self.creatures) do
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
  end
  self.creatures = keep
end

--- Appends every creature's actors; remembers the camera for placing new ones.
function WaterLife:collectActors(actors, camX, camY)
  if camX ~= nil and camY ~= nil then self.cam = { x = camX, y = camY } end
  local cfg = Config.WATER_LIFE
  for _, c in ipairs(self.creatures) do
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
  end
end

return WaterLife
