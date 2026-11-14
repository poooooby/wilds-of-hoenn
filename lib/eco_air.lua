-- Wild Ecology in the air (lib/eco.lua activity "fish"): a sea bird resting on the water
-- (a real bird, Config.FLYERS.realBirds: Wingull, Pelipper ...) now and then flies up, circles
-- out over the water and plunges in after a fish a few tiles away, coming up where it went in
-- and sitting on the water there. The flight itself is lib/sky_flyers.lua planFishing, run as
-- the Pokemon's arriving fx (lib/spawn_manager.lua: not met while it is in the air or under).
--
-- Flocks (a group of a flying species) land and take off together: lib/spawn_manager.lua
-- _spawnGroup / _leaveGroup with SkyFlyers:planFollow.
local V = ...
local Config = V.require("config")
local EnginePatch = V.require("engine_patch")
local Eco = V.require("eco")
local EcoWater = V.require("eco_water")
local SkyFlyers = V.require("sky_flyers")
local RendererFactory = V.require("renderer_factory")
local SpriteSource = V.require("sprite_source")

local EcoAir = {}

local function between(rng, r) return rng(r[1], r[2]) end

--- May `e` go fishing now? A real bird sitting at the surface on its own (not leading a
--- group: the others would be left bobbing), the sky open.
function EcoAir.canFish(e, sm)
  return e.terrain == "water" and e.isFlyer == true and not e.group and not e.rider and not e.roamer
    and not e.lured and not e.react and not e.engaged and not e.fx and not e.moving and not e.eco
    and sm ~= nil and not sm.underwater and sm.sky ~= nil and sm.sky:canFly(e)
    and SkyFlyers.isRealBird(e.species) or false
end

-- open water all round (x, y), so the plunge never lands by a bank
local function openWater(x, y)
  if EnginePatch.terrainAt(x, y) ~= "water" then return false end
  if not EnginePatch.isWater then return true end
  return EnginePatch.isWater(x, y + 1) and EnginePatch.isWater(x, y - 1)
    and EnginePatch.isWater(x - 1, y) and EnginePatch.isWater(x + 1, y)
end

-- is cell (x, y) well inside the view (the sky's camera)? nil when the view is not known
local function inView(sm, x, y)
  local sky = sm and sm.sky
  local cam = sky and sky.cam
  if not (cam and sky.viewSize) then return nil end
  local vw, vh = sky.viewSize()
  local px, py = x * 16, y * 16
  return px >= cam.x + 8 and px <= cam.x + (vw or 240) - 24 and py >= cam.y + 24 and py <= cam.y + (vh or 160) - 24
end

--- Where `e` dives: a free open-water cell Config.ECO.fish.range tiles off, clear of the
--- player -- one in view when the bird itself is (the player sees the whole dive). Returns
--- x, y or nil.
function EcoAir.fishingSpot(e, sm, rng)
  rng = rng or math.random
  local cfg = Config.ECO.fish
  local lo, hi = cfg.range[1], cfg.range[2]
  local list, seen = {}, {}
  local watched = inView(sm, e.cellX, e.cellY)
  for dy = -hi, hi do
    for dx = -hi, hi do
      local d = math.max(math.abs(dx), math.abs(dy))
      local x, y = e.cellX + dx, e.cellY + dy
      if d >= lo and d <= hi and openWater(x, y) and not (sm._cellFree and not sm:_cellFree(x, y))
        and not (sm.sky and sm.sky.clearOfPlayer and not sm.sky:clearOfPlayer(x, y)) then
        list[#list + 1] = { x, y }
        if watched and inView(sm, x, y) then seen[#seen + 1] = list[#list] end
      end
    end
  end
  if #seen > 0 then list = seen end
  if #list == 0 then return nil end
  local c = list[rng(1, #list)]
  return c[1], c[2]
end

Eco.register("fish", {
  -- (one tick: it hands over to the flight, which carries it from here)
  step = function(e, _ctx, sm, s)
    if not (sm and sm.sky and sm.sky.planFishing) then return true end
    if s.tx == nil or (sm._cellFree and not sm:_cellFree(s.tx, s.ty)) then return true end
    local fromX, fromY = e.cellX, e.cellY
    e.fx = sm.sky:planFishing(e, s.tx, s.ty)
    e.cellX, e.cellY, e.px, e.py = s.tx, s.ty, s.tx * 16, s.ty * 16
    e.swim, e.wakes = nil, nil
    if e.renderer then e.renderer.bobDy = 0 end
    if EnginePatch.startRipple then EnginePatch.startRipple(fromX, fromY) end
    return true
  end,
})

function EcoAir.choose(e, ctx, sm)
  if not EcoAir.canFish(e, sm) then return nil end
  local cfg = Config.ECO.fish
  if not sm.sky:clearOfPlayer(e.cellX, e.cellY) then return nil end
  if not EcoWater._due(e, "fish", cfg.every, ctx.rng or math.random, ctx.now or 0) then return nil end
  local x, y = EcoAir.fishingSpot(e, sm, ctx.rng)
  if not x then return nil end
  return "fish", { tx = x, ty = y }
end
Eco.addChooser(EcoAir.choose)

-- ------- the catch: a bird with a profile `catch` (Cramorant) comes up from its plunge with
-- that Pokemon in its beak, holds it a while, wriggling, then gulps it down

function EcoAir.catchState(e, sm, rng)
  rng = rng or math.random
  local cfg = Config.ECO.fish.catch
  local dex = e.profile and e.profile.catch
  local mod = sm and sm.mod
  local fish = dex and RendererFactory.new(mod, dex, false, Config.spriteStyle(mod), SpriteSource.PRESENTATION_LAND)
  if not fish then return nil end
  fish.swimming = false
  fish.act = { scale = cfg.scale }
  return { fish = fish, n = between(rng, cfg.hold) }
end

Eco.register("catch", {
  step = function(e, _ctx, _sm, s)
    local cfg = Config.ECO.fish.catch
    local r = e.renderer
    if r and r.advance then r:advance(false) end
    local f = s.fish
    if f then
      if f.advance then f:advance(true) end -- (its walk: a wriggle)
      local k = 1
      if s.t > s.n then k = math.max(0, 1 - (s.t - s.n) / cfg.gulpTicks) end
      f.act.scale = cfg.scale * k
      s.k = k
      if k <= 0 then return true end
    end
    return not f
  end,
})

--- Where the beak is: px offsets from the bird's tile top-left (x across, y down) for its
--- facing, `lift` px its head reaches above the tile's bottom, `reach` px its snout reaches
--- ahead (left / right). Pure.
function EcoAir.beakAt(facing, lift, reach, cfgBeak)
  local y = 16 - lift * (cfgBeak or 0.78)
  if facing == "left" then return 8 - reach, y end
  if facing == "right" then return 8 + reach, y end
  if facing == "up" then return 8, y - 2 end
  -- facing the camera: across its front, about halfway down its head (not on top of it)
  return 8, 16 - lift * 0.4
end

--- Appends the Pokemon in `e`'s beak (nothing while it is not holding one).
function EcoAir.collectCatch(e, actors)
  local s = e.eco
  local f = s and s.kind == "catch" and s.fish
  if not f or (s.k or 1) <= 0 then return end
  local r = e.renderer
  local lift = (r and r.headLift and r:headLift()) or 24
  local reach = (r and r.frontReach and r:frontReach(e.facing))
    or ((r and r.visualWidth and r:visualWidth() or 24) * 0.4)
  local bx, by = EcoAir.beakAt(e.facing, lift, reach, Config.ECO.fish.catch.beak)
  -- the fish is drawn standing on the beak point: its feet there, a little below for its size
  local fishFacing = (e.facing == "right" or e.facing == "up") and "right" or "left"
  actors[#actors + 1] = { kind = "wild_mon", i = 98000 + (e.id or 0),
    x = e.px + bx - 8, y = e.py + by - 16 + 4, sortY = e.py + (e.facing == "up" and -1 or 1),
    elevation = e.elevation, facing = fishFacing, walkPhase = 0, renderer = f }
end

--- A splash event in a fishing flight (lib/spawn_manager.lua, each tick of a travelling one):
--- droplets, a ripple and rings where it hits / leaves the water.
function EcoAir.onFlightEvents(e)
  local plan = e.fx and e.fx.plan
  local s = plan and plan._s
  local ev = s and s.events
  if ev and ev[1] == "splash" and e.fx.fishing then EcoWater.splash(e, e.cellX, e.cellY) end
end

return EcoAir
