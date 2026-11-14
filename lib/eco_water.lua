-- Wild Ecology in the water (lib/eco.lua activities for visible WATER spawns, by
-- lib/eco_profile.lua `water`): a fish leaps out of the water in an arc and lands a tile on
-- (or back where it went in), a whale lies at the surface and blows a spout or two before it
-- sounds. The motion is Water Life's own (lib/water_life.lua leap height / spray), now on the
-- real, battle-able Pokemon instead of an ambient copy.
--
-- Mid-leap a Pokemon is `untouchable` (in the air: the player cannot meet it), its landing
-- cell is reserved (`e.eco.rx / ry`, lib/spawn_manager.lua occupiedBy), and its art is the
-- LAND art for the arc (PMD's swim crop would cut the leap off) -- put back when it lands or
-- the leap is cut short. Splash droplets and spouts are drawn in code (`e.ecoFx`, aged and
-- drawn by lib/spawn_manager.lua through EcoWater.ageFx / collectFx).
local V = ...
local Config = V.require("config")
local EnginePatch = V.require("engine_patch")
local Eco = V.require("eco")
local SpriteSource = V.require("sprite_source")
local WaterLife = V.require("water_life")
local RendererFactory = V.require("renderer_factory")

local EcoWater = {}

local function between(rng, r) return rng(r[1], r[2]) end

-- ------- effects (droplets): { kind = "splash" | "spray", x, y (world px), age, seed, n, power }
-- (or any other kind with `life` ticks, `parts(age, seed)` -> particles and a `color`: a
-- burrower's dust, lib/eco_burrow.lua)

local function addFx(e, fx)
  local list = e.ecoFx
  if not list then list = {} e.ecoFx = list end
  list[#list + 1] = fx
end
EcoWater.addFx = addFx

--- A splash where `e` leaves / meets the water at cell (cx, cy): droplets, a ripple, rings.
function EcoWater.splash(e, cx, cy)
  EcoWater.splashAt(e, cx * 16, cy * 16)
  e.rings = { age = 0 }
end

--- A splash at a sprite's place in px (its tile-space top left, like e.px / e.py), for a
--- group member drawn off its tile: droplets and the nearest tile's ripple (no rings: they
--- are drawn on the entity's own tile).
function EcoWater.splashAt(e, x, y)
  addFx(e, { kind = "splash", x = x + 8, y = y + 13, sortY = y + 1, age = 0,
             seed = (e.id or 1) * 7 + math.floor(x / 16) })
  if EnginePatch.startRipple then EnginePatch.startRipple(math.floor((x + 8) / 16), math.floor((y + 8) / 16)) end
end

--- Ages `e`'s droplets one tick (drops the finished ones). Called for every Pokemon each tick.
function EcoWater.ageFx(e)
  local list = e.ecoFx
  if not list then return end
  local keep = 0
  for i = 1, #list do
    local f = list[i]
    f.age = f.age + 1
    local alive = (f.life and f.age < f.life) or (f.kind == "splash" and f.age < 26)
      or (f.kind == "spray" and f.age < (f.n or 48) + 34)
    if alive then keep = keep + 1 list[keep] = f end
  end
  for i = #list, keep + 1, -1 do list[i] = nil end
  if keep == 0 then e.ecoFx = nil end
end

-- an effect with its own `parts` (a burrower's dust / mound) is drawn straight from one
-- scratch list its draw fills: no particle tables per frame
local partsScratch = {}
local function drawParts(a, camX, camY)
  local g = love and love.graphics
  if not (g and g.rectangle) then return end
  local list, n = a.parts(a.age, a.seed, partsScratch)
  local c = a.color
  local r, gg, b, al = g.getColor()
  for k = 1, n do
    local d = list[k]
    local size = d[4] or 1
    g.setColor(c[1], c[2], c[3], d[3])
    g.rectangle("fill", math.floor(a.x + d[1] - camX), math.floor(a.y + d[2] - camY), size, size)
  end
  g.setColor(r, gg, b, al)
end
local WHITE = { 1, 1, 1 }

--- Appends `e`'s droplet actors.
function EcoWater.collectFx(e, actors)
  local list = e.ecoFx
  if not list then return end
  for _, f in ipairs(list) do
    local d
    if f.parts then
      actors[#actors + 1] = { kind = "ow_water_droplets", elevation = 3, sortY = f.sortY, x = f.x, y = f.y,
        i = 96000 + (e.id or 0), parts = f.parts, age = f.age, seed = f.seed, color = f.color or WHITE,
        draw = drawParts }
    elseif f.kind == "splash" then
      d = WaterLife.splash(f.age, f.seed)
    else
      d = WaterLife.spray(f.age, f.n or 48, f.seed, f.power)
    end
    if d and #d > 0 then actors[#actors + 1] = WaterLife._dropletActor(d, f.x, f.y, f.sortY, e.id or 0, f.color) end
  end
end

-- ------- the renderer while in the air: its land art, whole (not cut at a waterline)

local function toAir(e, s)
  local r = e.renderer
  if not r then return end
  s.basePresentation, s.baseSwimming = r.presentation, r.swimming
  r.presentation = SpriteSource.PRESENTATION_LAND
  if r.isPmd then r.swimming = false end
  r.bobDy = 0
end

local function backToWater(e, s)
  local r = e.renderer
  if not r then return end
  if s.basePresentation then r.presentation = s.basePresentation end
  if r.isPmd then r.swimming = s.baseSwimming end
  if r.act and r.act.ecoLeap then r.act = nil end
end
EcoWater.toAir, EcoWater.backToWater = toAir, backToWater

-- ------- leap

-- the cell a leap from (x, y) heading `dir` (-1 / 1) lands on: one tile on when it is open
-- water nobody holds, else back where it went in
local function landingCell(e, sm, dir)
  local x, y = e.cellX + dir, e.cellY
  if EnginePatch.terrainAt(x, y) ~= "water" then return e.cellX, e.cellY end
  if EnginePatch.isWater and not EnginePatch.isWater(x, y + 1) then return e.cellX, e.cellY end
  if sm and sm.occupiedBy and sm:occupiedBy(x, y, e) then return e.cellX, e.cellY end
  local p = EnginePatch.playerCell and EnginePatch.playerCell()
  if p and ((p.x == x and p.y == y) or (p.moving and p.targetX == x and p.targetY == y)) then return e.cellX, e.cellY end
  return x, y
end
EcoWater._landingCell = landingCell

--- The state a leap starts with (for Eco.start).
function EcoWater.leapState(e, sm, rng)
  rng = rng or math.random
  local cfg = Config.ECO.water.leap
  local dir
  if e.facing == "left" then dir = -1 elseif e.facing == "right" then dir = 1 else dir = rng(0, 1) == 0 and -1 or 1 end
  local lx, ly = landingCell(e, sm, dir)
  return { n = between(rng, cfg.ticks), dir = dir, cx = e.cellX, cy = e.cellY, rx = lx, ry = ly,
           untouchable = true }
end

Eco.register("leap", {
  step = function(e, _ctx, _sm, s)
    local cfg = Config.ECO.water.leap
    local r = e.renderer
    if s.t == 1 then
      toAir(e, s)
      e.facing = s.dir < 0 and "left" or "right"
      EcoWater.splash(e, s.cx, s.cy)
      if EnginePatch.playSeNamed and cfg.se then pcall(EnginePatch.playSeNamed, cfg.se) end
    end
    local p = math.min(1, s.t / s.n)
    local height = (r and r.isPmd) and cfg.pmdHeight or cfg.height
    e.px = (s.cx + (s.rx - s.cx) * p) * 16
    e.py = (s.cy + (s.ry - s.cy) * p) * 16
    local sink = 0
    if p < 0.15 then sink = 1 - p / 0.15 elseif p > 0.85 then sink = (p - 0.85) / 0.15 end
    if r then
      r.act = { dy = -math.sin(math.pi * p) * height, sink = math.min(0.95, sink), ecoLeap = true }
      if r.isPmd and r.advanceAs then r:advanceAs("hop", 1, "idle") end
    end
    if s.t >= s.n then
      e.cellX, e.cellY = s.rx, s.ry
      e.px, e.py = s.rx * 16, s.ry * 16
      e.swim = nil
      EcoWater.splash(e, s.rx, s.ry)
      return true
    end
    return false
  end,
  abort = function(e, _sm, s)
    backToWater(e, s)
    e.px, e.py = e.cellX * 16, e.cellY * 16
  end,
})

-- ------- whale: lies at the surface, blows, then sounds (the dive cycle takes it under)

function EcoWater.spoutState(e, rng)
  rng = rng or math.random
  local cfg = Config.ECO.water.whale
  local stay = between(rng, cfg.stay)
  local sprays, at = between(rng, cfg.sprays), {}
  for k = 1, sprays do at[k] = math.floor(stay * k / (sprays + 1)) end
  return { n = stay, sprayAt = at }
end

Eco.register("spout", {
  step = function(e, _ctx, sm, s)
    local cfg = Config.ECO.water.whale
    local r = e.renderer
    -- it rears up as it blows (PMD RearUp where the species has one), else lies there
    local blowing = false
    for _, at in ipairs(s.sprayAt) do
      if s.t >= at and s.t < at + cfg.rearTicks then blowing = true end
    end
    if r and r.isPmd and blowing and r.advanceAs then
      r:advanceAs("rearup", 1, "idle")
    elseif r and r.advance then
      r:advance(false)
    end
    for _, at in ipairs(s.sprayAt) do
      if s.t == at then
        local lift = (r and r.headLift and r:headLift()) or 20
        addFx(e, { kind = "spray", x = e.px + 8, y = e.py + 16 - lift + 2, sortY = e.py + 2, age = 0,
                   seed = (e.id or 1) * 13 + at, n = cfg.sprayTicks, power = 1 })
      end
    end
    if s.t >= s.n then
      -- it sounds: down under the water, up again somewhere near (lib/spawn_manager.lua)
      if sm and sm.startDive then sm:startDive(e) end
      return true
    end
    return false
  end,
})

-- ------- a school gathering into one big shape under the water (Wishiwashi's School Form)
--
-- The Pokemon (and its group) sink with rings, then the big form (profile `schoolForm`: an art
-- key, "746-school") swims slow circles under the surface as a dark shape, and breaks up again:
-- they come back up where they went down. Under the water it is `untouchable`.

--- The dark shape's renderer: the form's PMD art whatever the Sprite Style (only its outline
--- shows), else the species' own art grown `hgssScale` times.
function EcoWater.schoolShadow(mod, key, base)
  local cfg = Config.ECO.water.school
  local r, grow
  if Config.hasPmdArt and Config.hasPmdArt(mod) then
    r = RendererFactory.new(mod, key, false, SpriteSource.STYLE_PMD, SpriteSource.PRESENTATION_LAND)
    if r and not r.isPmd then r = nil end
  end
  if not r then
    r = RendererFactory.new(mod, base, false, Config.spriteStyle(mod), SpriteSource.PRESENTATION_LAND)
    grow = cfg.hgssScale
  end
  if not r then return nil end
  r.silhouette, r.swimming, r.alpha = true, false, 0
  if grow then r.act = { scale = grow } end
  return r
end

function EcoWater.schoolState(e, sm, rng)
  rng = rng or math.random
  local cfg = Config.ECO.water.school
  local key = e.profile and e.profile.schoolForm
  local base = (e.renderer and e.renderer.dex) or (EnginePatch.nationalFor and EnginePatch.nationalFor(e.species))
  local shadow = key and EcoWater.schoolShadow(sm and sm.mod, key, base)
  return { phase = "sink", pt = 0, n = between(rng, cfg.under), shadow = shadow,
           spin = rng(0, 1) == 0 and -1 or 1, phase0 = rng(0, 628) / 100 }
end

--- Where the shape is `t` ticks under: a slow ellipse round the spot they went down, and
--- the way it faces (along its path). Pure.
function EcoWater.schoolPlace(t, s, cx, cy)
  local cfg = Config.ECO.water.school
  local a = s.phase0 + s.spin * (t / cfg.lapTicks) * 2 * math.pi
  local x, y = cx + math.cos(a) * cfg.ring[1], cy + math.sin(a) * cfg.ring[2]
  local vx, vy = -math.sin(a) * s.spin * cfg.ring[1], math.cos(a) * s.spin * cfg.ring[2]
  local facing
  if math.abs(vx) >= math.abs(vy) then facing = vx > 0 and "right" or "left"
  else facing = vy > 0 and "down" or "up" end
  return x, y, facing
end

-- the Pokemon and the rest of its group, sunk `k` (0 .. 1) under
local function sinkAll(e, sm, k)
  local function one(m)
    local r = m.renderer
    if not r then return end
    if k <= 0 then
      if r.act and r.act.ecoSchool then r.act = nil end
      return
    end
    local act = (r.act and r.act.ecoSchool) and r.act or { ecoSchool = true }
    act.sink = k
    r.act = act
  end
  one(e)
  for _, mid in ipairs(e.group and e.group.members or {}) do
    local m = sm and sm.entities and sm.entities[mid]
    if m and m ~= e and m.rider then one(m) end
  end
end

local function splashAll(e, sm)
  EcoWater.splash(e, e.cellX, e.cellY)
  for _, mid in ipairs(e.group and e.group.members or {}) do
    local m = sm and sm.entities and sm.entities[mid]
    if m and m ~= e and m.rider then EcoWater.splashAt(e, m.px, m.py) end
  end
end

Eco.register("school", {
  step = function(e, ctx, sm, s)
    local cfg = Config.ECO.water.school
    s.pt = s.pt + 1
    local r = e.renderer
    if r and r.advance then r:advance(false) end
    local sh = s.shadow
    if s.phase == "sink" then
      if s.pt == 1 then
        splashAll(e, sm)
        local p = ctx and ctx.player
        if p and math.max(math.abs(p.x - e.cellX), math.abs(p.y - e.cellY)) <= cfg.cryRadius
            and EnginePatch.playCry then
          pcall(EnginePatch.playCry, e.species)
        end
      end
      sinkAll(e, sm, math.min(1, s.pt / cfg.sinkTicks))
      if s.pt >= cfg.sinkTicks then s.phase, s.pt, s.untouchable = "under", 0, true end
    elseif s.phase == "under" then
      sinkAll(e, sm, 1)
      if sh then
        local fade = math.min(1, s.pt / cfg.fadeTicks, (s.n - s.pt) / cfg.fadeTicks)
        sh.alpha = cfg.alpha * math.max(0, fade)
        local _, _, facing = EcoWater.schoolPlace(s.pt, s, 0, 0)
        s.facing = facing
        if sh.advance then sh:advance(true) end
      end
      if s.pt >= s.n then
        s.phase, s.pt, s.untouchable = "rise", 0, nil
        if sh then sh.alpha = 0 end
        splashAll(e, sm)
      end
    else
      sinkAll(e, sm, math.max(0, 1 - s.pt / cfg.sinkTicks))
      if s.pt >= cfg.sinkTicks then return true end
    end
    return false
  end,
  abort = function(e, sm, s)
    sinkAll(e, sm, 0)
    if s then s.untouchable, s.shadow = nil, nil end
  end,
})

--- Appends the dark shape of a school under the water (nothing before it has formed).
function EcoWater.collectSchool(e, actors)
  local s = e.eco
  local sh = s and s.kind == "school" and s.shadow
  if not (sh and s.phase == "under" and (sh.alpha or 0) > 0) then return end
  local x, y = EcoWater.schoolPlace(s.pt, s, e.px, e.py)
  actors[#actors + 1] = { kind = "wild_mon", i = 97000 + (e.id or 0), x = x, y = y, sortY = e.py - 8,
    elevation = e.elevation, facing = s.facing or e.facing, walkPhase = 0, renderer = sh }
end

-- ------- what a water Pokemon does next (an Eco chooser)

--- Is (`e`) a water spawn that can do its kind's thing here and now?
local function surfaceSwimmer(e, sm)
  return e.terrain == "water" and not (sm and sm.underwater) and not e.roamer and not e.isFlyer
    and not e.lured and not e.react and not e.engaged and not e.fx and not e.moving
end

-- per Pokemon: when its next leap / spout is due (ticks of its own clock)
local function due(e, key, range, rng, now)
  e.ecoDue = e.ecoDue or {}
  local at = e.ecoDue[key]
  if not at then
    e.ecoDue[key] = now + between(rng, range)
    return false
  end
  if now < at then return false end
  e.ecoDue[key] = now + between(rng, range)
  return true
end
EcoWater._due = due

function EcoWater.choose(e, ctx, sm)
  if not surfaceSwimmer(e, sm) then return nil end
  local prof = e.profile
  if not prof then return nil end
  local rng, now = ctx.rng or math.random, ctx.now or 0
  local p = ctx.player
  local cfg = Config.ECO.water
  -- never right beside the player: a leap onto / a spout over them reads wrong
  if p and math.max(math.abs(p.x - e.cellX), math.abs(p.y - e.cellY)) <= cfg.clearRadius then return nil end
  -- a school that gathers into one big shape now and then (Wishiwashi)
  if prof.schoolForm and due(e, "school", cfg.school.every, rng, now) then
    return "school", EcoWater.schoolState(e, sm, rng)
  end
  if prof.water == "leaper" and due(e, "leap", cfg.leap.every, rng, now) then
    return "leap", EcoWater.leapState(e, sm, rng)
  end
  if prof.water == "whale" and due(e, "spout", cfg.whale.every, rng, now) then
    return "spout", EcoWater.spoutState(e, rng)
  end
  return nil
end
Eco.addChooser(EcoWater.choose)

return EcoWater
