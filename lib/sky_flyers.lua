-- Flying Pokemon in the sky (the Flying Mons option). Two jobs:
--
-- 1. Ambient birds, never met or fought, drawn from the Flying-type species of this
--    map's encounter table (in a town or city, or a route with none, the maps joined
--    to it):
--      passers -- cross the view at mid or high height (lib/flight_path.lua: higher =
--                 closer to the camera = bigger, faster, blurred);
--      perchers -- swoop onto a tree crown, a roof or a signpost (lib/perch_spots.lua),
--                 sit with folded wings, turning or hopping now and then, and fly off
--                 after a while or when the player comes close;
--      divers  -- real birds (Config.FLYERS.realBirds) of the sea / Water type plunge into open water with a splash, stay under
--                 a moment, burst out and climb away.
-- 2. Wild Flying-type Pokemon (real spawns, lib/spawn_manager.lua) arriving and leaving
--    by air: planArrival / planDeparture / stepFlight / pushFlight.
--
-- Nothing here changes what spawns: a lander is the encounter the engine rolled, it
-- just comes in from the sky. Sky only over open-air maps (EnginePatch.skyAllowed).
local V = ...
local Config = V.require("config")
local EnginePatch = V.require("engine_patch")
local FlightPath = V.require("flight_path")
local PerchSpots = V.require("perch_spots")
local SkyDraw = V.require("sky_draw")
local SpawnFx = V.require("spawn_fx")
local SpriteSource = V.require("sprite_source")
local FormSource = V.require("form_source")
local RendererFactory = V.require("renderer_factory")
local ActorRenderer = V.require("actor_renderer")
local PmdRenderer = V.require("pmd_renderer")

local SkyFlyers = {}
SkyFlyers.__index = SkyFlyers

local FAR = 120 -- px (at least): how far off a bird starts / ends; high up, just off screen

local RAIN = { [3] = true, [5] = true, [8] = true, [13] = true } -- rain, storm, sandstorm, downpour
local FOG = { [6] = true, [9] = true }

--- `deps` (all optional, for tests): rng(a, b), occupied(x, y), viewSize(), playerCell().
function SkyFlyers.new(mod, deps)
  deps = deps or {}
  local self = setmetatable({
    mod = mod, rng = deps.rng or math.random, occupied = deps.occupied,
    viewSize = deps.viewSize or function()
      if EnginePatch.viewSize then return EnginePatch.viewSize() end
      return 240, 160
    end,
    playerCell = deps.playerCell or function()
      return EnginePatch.playerCell and EnginePatch.playerCell() or nil
    end,
    birds = {}, nextId = 1, taken = {}, allowed = false,
    pool = {}, seaPool = {}, timers = {},
  }, SkyFlyers)
  return self
end

local function between(rng, range) return rng(range[1], range[2]) end

--- Is this species a bird in the sky: a Flying type that is not on Config.FLYERS.notBirds
--- (flightless, or ruled out by the flyer audit) and not taller than Config.FLYERS.maxBirdHeightDm in the Pokedex -- the sea
--- serpents and sky dragons (Gyarados, Rayquaza) are Flying types, but no birds. A species
--- the Pokedex has no height for is judged by its type alone.
function SkyFlyers.flies(species)
  species = tonumber(species)
  if not (species and EnginePatch.isFlying and EnginePatch.isFlying(species)) then return false end
  local cfg = Config.FLYERS
  local nat = EnginePatch.nationalFor and EnginePatch.nationalFor(species)
  if nat and cfg.notBirds[nat] then return false end
  local h = EnginePatch.heightDm and EnginePatch.heightDm(species)
  return not (h and h > cfg.maxBirdHeightDm)
end

--- Kept for tests (flies() no longer caches anything).
function SkyFlyers._resetFlies() end

-- ------- species --------------------------------------------------------------

local function addSlots(out, seen, t, seaOnly)
  if type(t) ~= "table" then return end
  for _, area in ipairs({ "land", "grass", "water" }) do
    local a = t[area]
    local slots = type(a) == "table" and (a.slots or a.mons or a) or nil
    if type(slots) == "table" and not (seaOnly and area ~= "water") then
      for _, s in ipairs(slots) do
        local species = type(s) == "table" and tonumber(s.species or s[1])
        if species and species > 0 and SkyFlyers.flies(species) then
          local sea = area == "water" or EnginePatch.isWaterType(species)
          local e = seen[species]
          if e then
            e.weight = e.weight + 1
            e.sea = e.sea or sea
          else
            e = { species = species, weight = 1, sea = sea }
            seen[species] = e
            out[#out + 1] = e
          end
        end
      end
    end
  end
end

--- The Flying-type species seen around `mapId`: { {species, weight, sea}, ... }. A town
--- or city (or a route without any) takes those of the maps joined to it as well.
function SkyFlyers.poolFor(mapId)
  local out, seen = {}, {}
  addSlots(out, seen, EnginePatch.tableFor(mapId))
  local mt = EnginePatch.mapType and EnginePatch.mapType()
  if #out == 0 or mt == 1 or mt == 2 then
    for _, id in ipairs(EnginePatch.neighbourMapIds()) do
      addSlots(out, seen, EnginePatch.tableFor(id))
    end
  end
  return out
end

local function pickWeighted(list, rng)
  local total = 0
  for _, e in ipairs(list) do total = total + e.weight end
  if total <= 0 then return nil end
  local r = rng(1, total)
  for _, e in ipairs(list) do
    r = r - e.weight
    if r <= 0 then return e end
  end
  return list[#list]
end

-- ------- map lifecycle -----------------------------------------------------------

function SkyFlyers:clear()
  for _, b in ipairs(self.birds) do SkyDraw.release(b) end
  self.birds, self.taken = {}, {}
end

function SkyFlyers:onMapEntered(mapId)
  self:clear()
  self.mapId = mapId
  self.allowed = Config.flyersOn(self.mod) and EnginePatch.skyAllowed(mapId) or false
  self.pool, self.seaPool, self.perches = {}, {}, nil
  if not self.allowed then return end
  self:_refreshPool()
  -- perching is a town thing (roofs, trees, signposts): in the wild a bird only lands where
  -- the player can reach it, i.e. a real spawn swooping onto its own spawn cell
  local mt = EnginePatch.mapType and EnginePatch.mapType()
  self.perches = (mt == 1 or mt == 2) and PerchSpots.build() or nil
  local cfg, rng = Config.FLYERS, self.rng
  -- the first ones come soon after arriving, not at once
  self.timers = {
    passer = math.floor(between(rng, cfg.passer.every) / 3),
    perch = math.floor(between(rng, cfg.perch.every) / 3),
    dive = math.floor(between(rng, cfg.dive.every) / 2),
  }
end

--- Is this one a real bird (Config.FLYERS.realBirds)? Only those dive into the sea.
function SkyFlyers.isRealBird(species)
  local nat = EnginePatch.nationalFor and EnginePatch.nationalFor(species)
  return nat ~= nil and Config.FLYERS.realBirds[nat] == true
end

--- Re-reads which species fly here. Done on map entry and every POOL_REFRESH ticks: the
--- live encounter table can change under us (Modern Spawns writes its own, by time of day,
--- after the map has loaded).
local POOL_REFRESH = 600
function SkyFlyers:_refreshPool()
  self.poolAge = 0
  self.pool = SkyFlyers.poolFor(self.mapId)
  self.seaPool = {}
  for _, e in ipairs(self.pool) do
    if e.sea and SkyFlyers.isRealBird(e.species) then self.seaPool[#self.seaPool + 1] = e end
  end
end

function SkyFlyers:onMapExited()
  self:clear()
  self.allowed = false
end

--- The option changed: off drops every ambient bird now; on starts them on this map.
function SkyFlyers:onOptionChanged(mapId)
  if Config.flyersOn(self.mod) then self:onMapEntered(mapId or self.mapId) else self:onMapExited() end
end

--- Can a wild Pokemon arrive / leave by air here? (The option on, open sky, a Flying type,
--- never the roaming legendary.)
function SkyFlyers:canFly(e)
  return self.allowed and Config.flyersOn(self.mod) and e ~= nil and e.isFlyer == true and not e.roamer
end

-- ------- renderers ---------------------------------------------------------------

local function widthOf(r)
  if not r then return 16 end
  if r.isPmd then
    local w = PmdRenderer.contentSize(r.info)
    return (w and w > 0) and w or 16
  end
  return (r.frameWidth and r:frameWidth()) or 16
end

--- A view of one flying sprite, the table lib/sky_draw.lua draws: its renderer, and
--- what it needs to switch art while flying (HGSS floaters fly with their levitating
--- sheet; a PMD swimmer is drawn whole in the air).
function SkyFlyers.newView(id, renderer, dex, mod)
  return {
    id = id, renderer = renderer, floater = SpriteSource.isFloater(mod, dex),
    basePresentation = renderer and renderer.presentation, baseSwimming = renderer and renderer.swimming,
    flapClock = 0, width = widthOf(renderer), x = 0, y = 0, h = 0,
  }
end

-- the renderer's art for a flying / perched / landed bird, for this tick
local function animate(view, s)
  local r = view.renderer
  if not r then return end
  view.flapClock = view.flapClock + 1
  if r.isPmd then
    r.swimming = false
    if s.flapping then
      r:advanceAs("fly", 1, "walk")
    elseif s.sitting and not view.holding then
      r:holdIdle()
    end
    view.holding = s.sitting and true or nil
    view.pose = ActorRenderer.POSE_STAND
  else
    if s.flapping then
      if view.floater then r.presentation = SpriteSource.PRESENTATION_LEVITATES end
      local beat = math.floor(view.flapClock / Config.FLYERS.flapTicks) % 2
      view.pose = beat == 0 and ActorRenderer.POSE_WALK_A or ActorRenderer.POSE_WALK_B
    else
      r.presentation = SpriteSource.PRESENTATION_LAND -- folded wings: its standing art
      view.pose = ActorRenderer.POSE_STAND
    end
  end
end

--- Puts a renderer back the way it draws on the ground (a lander touching down).
function SkyFlyers.restore(view)
  local r = view and view.renderer
  if not r then return end
  r.presentation = view.basePresentation or r.presentation
  if r.isPmd then
    r.swimming = view.baseSwimming
    if r.advance then r:advance(false) end
  end
  SkyDraw.release(view)
end

-- one tick of a view's plan: its position / look for this tick; false once done
local function stepView(self, view, plan)
  -- a take-off planned when it happens, not when the bird arrived (the player has moved)
  local ph = FlightPath.current(plan)
  if ph and ph.lazy and plan.t == 0 then
    local out = self:_swoopOut(ph.from, ph.n)
    ph.to, ph.curve, ph.fadeOut, ph.lazy = out.to, out.curve, true, nil
  end
  local s = FlightPath.step(plan)
  if not s then return false end
  if view.screenSpace then
    -- a passer's plan runs in screen px (collectActors places it in the world)
    view.sx, view.sy, view.h = s.x or view.sx, s.y or view.sy, s.h or 0
  else
    view.x, view.y, view.h = s.x or view.x, s.y or view.y, s.h or 0
  end
  view.alpha = s.alpha
  view.lift, view.hop, view.sink, view.hidden = s.lift, s.hop, s.sink, s.hidden
  view.facing = s.facing
  view.sitting = s.sitting
  animate(view, s)
  if not s.hidden and SkyDraw.blurred(view.h) then SkyDraw.prepare(view) end
  return s
end

-- ------- wild Pokemon arriving / leaving by air ---------------------------------------

-- a point high up and well away from (x, y), for when the view is not known yet
local function awayFrom(self, x, y)
  local vw = self.viewSize()
  local d = math.max(FAR, (tonumber(vw) or 240) * 0.5)
  local a = self.rng(0, 359) * math.pi / 180
  return x + math.cos(a) * d, y + math.sin(a) * d * 0.8
end

-- the player's tile (world px of its top-left), or nil
function SkyFlyers:_playerPx()
  local p = self.playerCell and self.playerCell()
  if not p then return nil end
  return p.x * 16, p.y * 16
end

--- Is cell (x, y) farther than the swoop clear radius (Config.FLYERS.swoop.clearRadius
--- tiles) from the player? A wild Pokemon that close arrives / leaves the usual way.
function SkyFlyers:clearOfPlayer(x, y)
  local p = self.playerCell and self.playerCell()
  if not p then return true end
  return math.max(math.abs(p.x - x), math.abs(p.y - y)) > Config.FLYERS.swoop.clearRadius
end

-- the closest the path from a to b (curve `c`, the bow FlightPath draws) comes to the
-- player's tile, in px (the greater of the x / y distances)
local function closestTo(a, b, c, plx, ply)
  local dx, dy = b.x - a.x, b.y - a.y
  local len = math.sqrt(dx * dx + dy * dy)
  local best = math.huge
  for k = 0, 20 do
    local e = k / 20
    local bow = len > 0 and math.sin(math.pi * e) * c or 0
    local x = a.x + dx * e - (len > 0 and dy / len * bow or 0)
    local y = a.y + dy * e + (len > 0 and dx / len * bow or 0)
    best = math.min(best, math.max(math.abs(x - plx), math.abs(y - ply)))
  end
  return best
end
SkyFlyers._closestTo = closestTo

--- Where a swoop onto (or off) world point (tx, ty) starts (or ends): a point off screen,
--- mid or high up (Config.FLYERS.swoop.startH), on any side but away from the player, and
--- the arc to fly, bending away from the player, so the path keeps out of the clear radius
--- around them. Returns { x, y, h }, curve.
function SkyFlyers:_swoopEnd(tx, ty)
  local cfg, rng = Config.FLYERS.swoop, self.rng
  local h = between(rng, cfg.startH) / 100
  local cam = self.cam
  if not cam then
    local x, y = awayFrom(self, tx, ty)
    return { x = x, y = y, h = h }, between(rng, cfg.arc) * (rng(0, 1) == 0 and -1 or 1)
  end
  local vw, vh = self.viewSize()
  local look = FlightPath.look(h)
  local margin = 40 * look.scale
  local plx, ply = self:_playerPx()
  plx, ply = plx or (cam.x + vw / 2 - 8), ply or (cam.y + vh / 2 - 8)
  local base = (math.atan2 or math.atan)(ty - ply, tx - plx) -- away from the player (LuaJIT / Lua 5.3+)
  if tx == plx and ty == ply then base = rng(0, 359) * math.pi / 180 end
  local clear = (cfg.clearRadius + 1) * 16 - 1
  local bestEnd, bestCurve, bestD = nil, 0, -1
  for _ = 1, 12 do
    local th = base + rng(-80, 80) * math.pi / 180
    local cx, cy = math.cos(th), math.sin(th)
    local d = 32
    local sx, sy
    while d <= 1200 do
      local px, py = tx + cx * d, ty + cy * d
      local qx, qy = FlightPath.toScreen(px, py, look.parallax, cam.x, cam.y, vw, vh)
      if qx < -margin or qx > vw + margin or qy < -margin or qy > vh + margin then sx, sy = px, py break end
      d = d + 16
    end
    if sx then
      local a, b = { x = sx, y = sy }, { x = tx, y = ty }
      for _, sign in ipairs({ 1, -1 }) do
        local c = sign * between(rng, cfg.arc)
        local near = closestTo(a, b, c, plx, ply)
        if near > bestD then bestEnd, bestCurve, bestD = a, c, near end
      end
      if bestD >= clear then break end
    end
  end
  if not bestEnd then
    local x, y = awayFrom(self, tx, ty)
    return { x = x, y = y, h = h }, between(rng, cfg.arc)
  end
  bestEnd.h = h
  return bestEnd, bestCurve
end

-- a fly phase down from the sky onto `to` ({x, y, h = 0, lift}), and one up from `from`
-- back into it (the same kind of path reversed, fading out at its end)
function SkyFlyers:_swoopIn(to, n)
  local start, curve = self:_swoopEnd(to.x, to.y)
  return { type = "fly", from = start, to = to, n = n, curve = curve }
end
function SkyFlyers:_swoopOut(from, n)
  local stop, curve = self:_swoopEnd(from.x, from.y)
  -- worked out as the path from stop to `from`: flown the other way the bow flips sign
  return { type = "fly", from = from, to = stop, n = n, curve = -curve, fadeOut = true }
end

--- Starts entity `e` (a wild Flying-type Pokemon just placed on its cell) coming down
--- from the sky; sometimes (Config.FLYERS.land.perchChance) by way of a perch near its
--- cell first, hopping down from it. Returns its fx table for SpawnManager.
function SkyFlyers:planArrival(e)
  local cfg, rng = Config.FLYERS.land, self.rng
  local tx, ty = e.cellX * 16, e.cellY * 16
  local phases
  local perch
  if self.perches and rng(1, 100) <= math.floor(cfg.perchChance * 100) then
    local near = {}
    for _, s in ipairs(self.perches:near(e.cellX, e.cellY, cfg.perchRange, self.taken)) do
      if self:clearOfPlayer(s.x, s.y) then near[#near + 1] = s end
    end
    if #near > 0 then perch = near[rng(1, #near)] end
  end
  if perch then
    local px, py, lift = perch.x * 16, perch.y * 16, perch.lift
    self.taken[perch] = e
    phases = {
      self:_swoopIn({ x = px, y = py, h = 0, lift = lift }, between(rng, cfg.flyTicks)),
      { type = "sit", at = { x = px, y = py, lift = lift }, n = between(rng, cfg.sit),
        facing = ({ "down", "left", "right" })[rng(1, 3)] },
      { type = "hop", from = { x = px, y = py, lift = lift }, to = { x = tx, y = ty, lift = 0 },
        n = cfg.hopTicks + math.max(math.abs(perch.x - e.cellX), math.abs(perch.y - e.cellY)) * 6, height = 10 },
    }
  else
    phases = { self:_swoopIn({ x = tx, y = ty, h = 0 }, between(rng, cfg.flyTicks)) }
  end
  local view = SkyFlyers.newView(e.id, e.renderer, e.dex, self.mod)
  view.perch = perch
  return { kind = "land", mode = "swoop", plan = FlightPath.plan(phases, rng), view = view }
end

--- Starts entity `e` flying up from its cell and away. Returns its fx table.
function SkyFlyers:planDeparture(e)
  local cfg, rng = Config.FLYERS.land, self.rng
  local phases = { self:_swoopOut({ x = e.cellX * 16, y = e.cellY * 16, h = 0 }, between(rng, cfg.flyTicks)) }
  local view = SkyFlyers.newView(e.id, e.renderer, e.dex, self.mod)
  return { kind = "leave", mode = "swoop", plan = FlightPath.plan(phases, rng), view = view }
end

--- One tick of an arriving / leaving wild Pokemon's flight. True once it is over.
function SkyFlyers:stepFlight(fx)
  local view = fx.view
  local s = stepView(self, view, fx.plan)
  if view.perch and s and not s.sitting and view.wasSitting then
    self.taken[view.perch] = nil -- hopped off its perch
    view.perch = nil
  end
  view.wasSitting = s and s.sitting
  if not s then
    if view.perch then self.taken[view.perch] = nil view.perch = nil end
    return true
  end
  return false
end

--- Frees what a flight held (it was cut short: a despawn, a map change).
function SkyFlyers:endFlight(fx)
  local view = fx and fx.view
  if not view then return end
  if view.perch then self.taken[view.perch] = nil view.perch = nil end
  SkyDraw.release(view)
end

--- Appends the actors of an arriving / leaving wild Pokemon.
function SkyFlyers:pushFlight(fx, actors, camX, camY)
  local vw, vh = self.viewSize()
  SkyDraw.push(actors, fx.view, camX or 0, camY or 0, vw, vh)
end

-- ------- ambient birds ---------------------------------------------------------------

local function inView(cam, vw, vh, x, y, margin)
  if not cam then return false end
  return x >= cam.x + margin and x <= cam.x + vw - 16 - margin
    and y >= cam.y + margin and y <= cam.y + vh - 16 - margin
end

function SkyFlyers:_newBird(kind, entry, phases)
  local dex = FormSource.artKeyFor(self.mod, entry.species)
  if not dex then return nil end
  local renderer = RendererFactory.new(self.mod, dex, false, Config.spriteStyle(self.mod),
    SpriteSource.PRESENTATION_LAND)
  if not renderer then return nil end
  -- a big Pokemon high up would cover the view: those only come down as real spawns
  if widthOf(renderer) > Config.FLYERS.maxAmbientWidth then return nil end
  local id = self.nextId
  self.nextId = id + 1
  local bird = SkyFlyers.newView(id, renderer, dex, self.mod)
  bird.kind, bird.species = kind, entry.species
  bird.plan = FlightPath.plan(phases, self.rng)
  self.birds[#self.birds + 1] = bird
  return bird
end

function SkyFlyers:_count(kind, highOnly)
  local n = 0
  for _, b in ipairs(self.birds) do
    if b.kind == kind and (not highOnly or (b.high == true)) then n = n + 1 end
  end
  return n
end

function SkyFlyers:_spawnPasser()
  local cfg, rng = Config.FLYERS.passer, self.rng
  if not self.cam or self:_count("passer") >= cfg.max then return false end
  local entry = pickWeighted(self.pool, rng)
  if not entry then return false end
  local fog = FOG[(EnginePatch.weatherId and EnginePatch.weatherId()) or -1]
  local high = not fog and self:_count("passer", true) < cfg.maxHigh and rng(1, 100) <= 40
  local h = high and 1 or (0.45 + rng(0, 15) / 100)
  local look = FlightPath.look(h)
  local vw, vh = self.viewSize()
  -- across the top band of the screen, side to side, in screen px (its feet; the sprite
  -- reaches up from them): a gentle arc, never straight, never over the middle or bottom
  -- its feet at least a body's height down (the sprite is drawn upward from them, `scale`
  -- times its size), so the whole bird shows inside the band rather than past the top edge
  local top = math.floor(24 * look.scale)
  local bottom = math.max(top + 4, math.floor(vh * cfg.band - cfg.arc[2]))
  local fromLeft = rng(0, 1) == 0
  local margin = 48 * look.scale
  local x0 = fromLeft and -margin or vw + margin
  local x1 = fromLeft and vw + margin or -margin
  local y0, y1 = rng(top, bottom), rng(top, bottom)
  local arc = between(rng, cfg.arc)
  -- bow up (toward the top edge) unless there is no room above, then down
  local bowDown = (y0 + y1) / 2 - arc < top
  -- FlightPath bows by +curve along (-dy, dx) / len: flying right (dx > 0) that is downward
  local sign = ((x1 > x0) == bowDown) and 1 or -1
  local n = between(rng, high and cfg.highTicks or cfg.ticks)
  local bob = high and { between(rng, cfg.bob), between(rng, cfg.bobTicks) } or nil
  local bird = self:_newBird("passer", entry, {
    { type = "fly", from = { x = x0, y = y0, h = h }, to = { x = x1, y = y1, h = h }, n = n, curve = sign * arc,
      bob = bob },
  })
  if bird then
    bird.high, bird.screenSpace = high, true
    bird.sx, bird.sy = x0, y0
    bird.cam0 = { x = self.cam.x, y = self.cam.y }
    bird.band = { top = -margin, bottom = vh * cfg.band }
  end
  return bird ~= nil
end

function SkyFlyers:_playerNear(x, y, radius)
  local p = self.playerCell and self.playerCell()
  if not p then return false end
  return math.max(math.abs(p.x - x), math.abs(p.y - y)) <= radius
end

function SkyFlyers:_spawnPercher()
  local cfg, rng = Config.FLYERS.perch, self.rng
  if not (self.cam and self.perches) or self:_count("perch") >= cfg.max then return false end
  local entry = pickWeighted(self.pool, rng)
  if not entry then return false end
  local vw, vh = self.viewSize()
  local cam = self.cam
  local spot = self.perches:pick(function(s)
    return inView(cam, vw, vh, s.x * 16, s.y * 16, 16) and not self:_playerNear(s.x, s.y, cfg.scatterRunning + 1)
      and self:clearOfPlayer(s.x, s.y)
  end, self.taken, 24, rng)
  if not spot then return false end
  local px, py = spot.x * 16, spot.y * 16
  local bird = self:_newBird("perch", entry, {
    self:_swoopIn({ x = px, y = py, h = 0, lift = spot.lift }, between(rng, cfg.flyTicks)),
    { type = "sit", at = { x = px, y = py, lift = spot.lift }, n = between(rng, cfg.stay),
      facing = ({ "down", "left", "right" })[rng(1, 3)] },
    { type = "fly", lazy = true, from = { x = px, y = py, h = 0, lift = spot.lift }, n = between(rng, cfg.flyTicks) },
  })
  if not bird then return false end
  bird.perch = spot
  self.taken[spot] = bird
  return true
end

-- an open water cell in view a sea bird can plunge into (water around it, nothing on it)
function SkyFlyers:_waterCell()
  local cam, rng = self.cam, self.rng
  if not cam then return nil end
  local vw, vh = self.viewSize()
  local x0, y0 = math.ceil(cam.x / 16) + 1, math.ceil(cam.y / 16) + 1
  local x1, y1 = math.floor((cam.x + vw) / 16) - 2, math.floor((cam.y + vh) / 16) - 2
  if x1 < x0 or y1 < y0 then return nil end
  for _ = 1, 24 do
    local x, y = rng(x0, x1), rng(y0, y1)
    if EnginePatch.isWater(x, y) and EnginePatch.isWater(x, y + 1) and EnginePatch.isWater(x, y - 1)
      and EnginePatch.isWater(x - 1, y) and EnginePatch.isWater(x + 1, y)
      and not (self.occupied and self.occupied(x, y)) and not EnginePatch.objectOn(x, y)
      and self:clearOfPlayer(x, y) then
      return x, y
    end
  end
  return nil
end

function SkyFlyers:_spawnDiver()
  local cfg, rng = Config.FLYERS.dive, self.rng
  if #self.seaPool == 0 or self:_count("dive") >= 1 then return false end
  local x, y = self:_waterCell()
  if not x then return false end
  local entry = pickWeighted(self.seaPool, rng)
  local wx, wy = x * 16, y * 16
  local at = { x = wx, y = wy }
  local bird = self:_newBird("dive", entry, {
    self:_swoopIn({ x = wx, y = wy, h = 0 }, between(rng, cfg.flyTicks)),
    { type = "sink", at = at, n = cfg.sinkTicks, event = "splash" },
    { type = "under", at = at, n = between(rng, cfg.under) },
    { type = "rise", at = at, n = cfg.sinkTicks, event = "splash" },
    { type = "fly", lazy = true, from = { x = wx, y = wy, h = 0 }, n = between(rng, cfg.flyTicks) },
  })
  if bird then bird.cellX, bird.cellY = x, y end
  return bird ~= nil
end

-- the scatter radius: wider while the player runs
local function scatterRadius()
  local cfg = Config.FLYERS.perch
  return (EnginePatch.playerIsRunning and EnginePatch.playerIsRunning()) and cfg.scatterRunning or cfg.scatter
end

function SkyFlyers:_scatter(bird)
  local rng = self.rng
  local spot = bird.perch
  local px, py = spot.x * 16, spot.y * 16
  FlightPath.replaceRest(bird.plan, {
    self:_swoopOut({ x = px, y = py, h = 0, lift = spot.lift },
      math.floor(between(rng, Config.FLYERS.perch.flyTicks) * 0.8)),
  }, true)
  if rng(1, 100) <= math.floor(Config.FLYERS.perch.cryChance * 100) then EnginePatch.playCry(bird.species) end
end

--- One tick (from the follower tick, like every wild Pokemon): new birds on their timers,
--- every bird a step on, perched ones scared off by the player.
function SkyFlyers:tick()
  if not self.allowed then return end
  self.poolAge = (self.poolAge or 0) + 1
  if self.poolAge >= POOL_REFRESH then self:_refreshPool() end
  local cfg = Config.FLYERS
  local slow = RAIN[(EnginePatch.weatherId and EnginePatch.weatherId()) or -1] and cfg.stormSlowdown or 1
  for kind, t in pairs(self.timers) do
    t = t - 1
    if t <= 0 then
      if #self.pool > 0 then
        if kind == "passer" then self:_spawnPasser()
        elseif kind == "perch" then self:_spawnPercher()
        else self:_spawnDiver() end
      end
      t = between(self.rng, cfg[kind].every) * slow
    end
    self.timers[kind] = t
  end
  local keep = {}
  for _, b in ipairs(self.birds) do
    if b.sitting and b.perch and self:_playerNear(b.perch.x, b.perch.y, scatterRadius()) then
      self:_scatter(b)
    end
    local s = stepView(self, b, b.plan)
    if s then
      for _, ev in ipairs(s.events) do
        if ev == "splash" and b.cellX then
          EnginePatch.startRipple(b.cellX, b.cellY)
          b.rings = b.rings or {}
          b.rings[#b.rings + 1] = 0
        end
      end
      if b.perch and not s.sitting and b.wasSitting then
        self.taken[b.perch] = nil -- off its perch
        b.perch = nil
      end
      b.wasSitting = s.sitting
      keep[#keep + 1] = b
    else
      if b.perch then self.taken[b.perch] = nil end
      SkyDraw.release(b)
    end
    if b.rings then
      local left = {}
      for _, age in ipairs(b.rings) do
        if age + 1 < SpawnFx.ringsTicks() then left[#left + 1] = age + 1 end
      end
      b.rings = #left > 0 and left or nil
    end
  end
  self.birds = keep
end

--- Appends every ambient bird's actors; remembers the camera for placing new ones.
function SkyFlyers:collectActors(actors, camX, camY)
  if camX ~= nil and camY ~= nil then self.cam = { x = camX, y = camY } end
  if #self.birds == 0 then return end
  local vw, vh = self.viewSize()
  for _, b in ipairs(self.birds) do
    if b.screenSpace and b.sx and camX ~= nil then
      -- a passer: its screen path, slid by the view's scrolling at its own parallax, but kept
      -- in the top band (feet at most band.bottom down the screen)
      local p = FlightPath.look(b.h).parallax
      local sx = b.sx - (camX - b.cam0.x) * p
      local sy = b.sy - (camY - b.cam0.y) * p
      sy = math.max(b.band.top, math.min(b.band.bottom, sy))
      b.x, b.y = FlightPath.fromScreen(sx - 8, sy - 16, p, camX, camY, vw, vh)
    end
    SkyDraw.push(actors, b, camX or 0, camY or 0, vw, vh)
    if b.rings and b.cellX then
      for _, age in ipairs(b.rings) do
        local a = SpawnFx.ringsActor(age, b.cellX * 16, b.cellY * 16, b.cellY * 16, 3, 95000 + b.id)
        if a then actors[#actors + 1] = a end
      end
    end
  end
end

--- How many ambient birds are out (tests, tools).
function SkyFlyers:count(kind)
  if not kind then return #self.birds end
  return self:_count(kind)
end

return SkyFlyers
