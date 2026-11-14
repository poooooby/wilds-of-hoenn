-- How a visible wild Pokemon arrives and leaves (lib/spawn_manager.lua drives it).
--
-- Three looks, picked by the tile it stands on:
--   "grass" -- it rises out of the grass (the renderer's `act.sink` going 1 -> 0, the
--              same squash-to-the-feet an overworld Battler sinks with), and the grass
--              on its tile rustles once (the engine's own rustle frames, drawn by
--              SpawnFx.rustleActor in front of the Pokemon so it comes up from behind
--              the blades);
--   "water" -- it surfaces the same way, with one of the engine's ripples;
--   "fade"  -- anywhere else (cave floors, sand) it fades in (`renderer.alpha` 0 -> 1).
-- Leaving plays the same in reverse. Everything here but the actor's draw is pure.
local V = ...
local RecallMath = V.require("recall_math")

local SpawnFx = {}

--- A new effect: `kind` "appear" | "leave", `mode` "grass" | "water" | "fade", `n` ticks.
function SpawnFx.new(kind, mode, n)
  return { kind = kind, mode = mode, t = 0, n = math.max(1, tonumber(n) or 1) }
end

--- How far along it is, eased (0 at the start, 1 at the end).
function SpawnFx.progress(fx)
  if not fx then return 1 end
  return RecallMath.ease(math.max(0, math.min(1, fx.t / fx.n)))
end

--- What the renderer shows now: `sink` (0 = standing, 1 = gone below the grass / water
--- line) for grass and water, `alpha` for a fade. Appear runs sink 1 -> 0 / alpha 0 -> 1,
--- leave the other way.
function SpawnFx.visual(fx)
  local p = SpawnFx.progress(fx)
  local shown = (fx and fx.kind == "leave") and (1 - p) or p -- 1 = fully there
  if fx and fx.mode == "fade" then return { alpha = shown } end
  return { sink = 1 - shown }
end

--- One tick on; true once it has finished.
function SpawnFx.step(fx)
  fx.t = fx.t + 1
  return fx.t >= fx.n
end

--- The rustle frame `age` ticks in, from `frames` = { {frame, ticks}, ... }, or nil once
--- the rustle has played (the static grass cover takes over).
function SpawnFx.rustleFrame(frames, age)
  if type(frames) ~= "table" then return nil end
  local t = math.max(0, tonumber(age) or 0)
  for _, f in ipairs(frames) do
    if t < f[2] then return f[1] end
    t = t - f[2]
  end
  return nil
end

--- The rustle on the tile whose top-left is (gx, gy), as a field actor, or nil when it
--- has played out. Same geometry as the engine's grass cover (lib/grass_cover.lua): the
--- 16 x 16 frame on the tile's lower half, drawn in front of the Pokemon on it.
function SpawnFx.rustleActor(sheet, frames, age, gx, gy, py, elevation, id)
  local frame = SpawnFx.rustleFrame(frames, age)
  local q = frame and sheet and sheet.quadsFront and sheet.quadsFront[frame]
  if not q then return nil end
  local x, y = gx, gy + 8
  return {
    kind = "ow_spawn_rustle",
    elevation = elevation or 3,
    sortY = py + 0.6,
    x = x, y = y,
    i = 91600 + (tonumber(id) or 0),
    draw = function(_, camX, camY)
      if not (love and love.graphics and love.graphics.draw) then return end
      love.graphics.setColor(1, 1, 1, 1)
      love.graphics.draw(sheet.image, q, x - camX, y - camY)
    end,
  }
end

-- ------- water: three rings growing outward from where it surfaces / sinks

SpawnFx.RING_COUNT = 3     -- rings, one after another
SpawnFx.RING_GAP = 7       -- ticks between them
SpawnFx.RING_LIFE = 30     -- one ring's life, ticks
SpawnFx.RING_R0, SpawnFx.RING_R1 = 6, 22 -- its half-width (px) from start to end: out past the Pokemon
SpawnFx.RING_FLAT = 0.42   -- height / width: a ring lying on the water

--- How long the rings take, all told.
function SpawnFx.ringsTicks()
  return (SpawnFx.RING_COUNT - 1) * SpawnFx.RING_GAP + SpawnFx.RING_LIFE
end

--- The rings `age` ticks in: { {rx, ry, alpha}, ... } for those showing now (each
--- starts RING_GAP after the last, grows from RING_R0 to RING_R1 easing out, and fades
--- as it spreads). Pure (tested).
-- ring i (1..RING_COUNT) `age` ticks in: rx, ry, alpha, or nil when it is not showing
local function ringAt(age, i)
  local t = age - (i - 1) * SpawnFx.RING_GAP
  if t < 0 or t >= SpawnFx.RING_LIFE then return nil end
  local p = t / SpawnFx.RING_LIFE
  local grow = 1 - (1 - p) * (1 - p) -- fast at first, slowing as it spreads
  local rx = SpawnFx.RING_R0 + (SpawnFx.RING_R1 - SpawnFx.RING_R0) * grow
  return rx, rx * SpawnFx.RING_FLAT, math.min(1, p / 0.12) * (1 - p) * 0.9
end

function SpawnFx.rings(age)
  age = tonumber(age) or 0
  local out = {}
  for i = 1, SpawnFx.RING_COUNT do
    local rx, ry, alpha = ringAt(age, i)
    if rx then out[#out + 1] = { rx = rx, ry = ry, alpha = alpha } end
  end
  return out
end

--- The whole pixels of a ring outline, half-widths `rx` x `ry`, around (0, 0): one
--- crisp 1 px line like the game's own art (an anti-aliased ellipse at the field's low
--- resolution reads as a soft blur). Pure (tested).
local ringPixelCache, ringPixelCount = {}, 0
function SpawnFx.ringPixels(rx, ry)
  -- Memoized on quarter-px radii: the eased radii repeat the same handful of integer
  -- shapes, and this runs per ring PER FRAME (a swimmer's wakes never stop coming) --
  -- unmemoized it built ~40 small tables per ring per frame. Callers must not mutate
  -- the returned list. The cache is bounded by the radii actually used; reset if abused.
  local kx = math.floor((tonumber(rx) or 0) * 4 + 0.5)
  local ky = math.floor((tonumber(ry) or 0) * 4 + 0.5)
  local key = kx * 8192 + ky
  local hit = ringPixelCache[key]
  if hit then return hit end
  rx, ry = kx / 4, ky / 4
  local seen, out = {}, {}
  local steps = math.max(32, math.floor((rx + ry) * 8)) -- dense enough for a gapless line
  for k = 0, steps - 1 do
    local th = (k / steps) * math.pi * 2
    local x = math.floor(math.cos(th) * rx + 0.5)
    local y = math.floor(math.sin(th) * ry + 0.5)
    local key = x * 1024 + y
    if not seen[key] then
      seen[key] = true
      out[#out + 1] = { x, y }
    end
  end
  if ringPixelCount >= 512 then ringPixelCache, ringPixelCount = {}, 0 end
  ringPixelCache[key], ringPixelCount = out, ringPixelCount + 1
  return out
end

-- The ring / wake actors are kept (one per owner and slot) and refilled each frame, drawn
-- by one shared function reading the actor's fields: a fresh actor + draw closure + ring
-- list per frame was the biggest piece of a water map's per-frame garbage. The field
-- reads an actor only in the frame it is pushed. Bounded: started over past POOL_MAX.
local pool, pooled = {}, 0
local POOL_MAX = 512

local function pooledActor(key, kind, draw)
  local a = pool[key]
  if not a then
    if pooled >= POOL_MAX then pool, pooled = {}, 0 end
    a = { kind = kind, draw = draw }
    pool[key] = a
    pooled = pooled + 1
  end
  return a
end

--- A new map: forget the kept actors.
function SpawnFx.reset()
  pool, pooled = {}, 0
end

local function ringOutline(g, ox, oy, rx, ry, alpha)
  g.setColor(0.88, 0.96, 1.0, alpha)
  local px = SpawnFx.ringPixels(rx, ry)
  for k = 1, #px do
    local p = px[k]
    g.rectangle("fill", ox + p[1], oy + p[2], 1, 1)
  end
end

local function drawRings(a, camX, camY)
  if not (love and love.graphics and love.graphics.rectangle) then return end
  local g = love.graphics
  local r, gg, b, al = g.getColor()
  local ox, oy = math.floor(a.x - camX), math.floor(a.y - camY)
  for i = 1, SpawnFx.RING_COUNT do
    local rx, ry, alpha = ringAt(a.age, i)
    if rx then ringOutline(g, ox, oy, rx, ry, alpha) end
  end
  g.setColor(r, gg, b, al)
end

local function drawWake(a, camX, camY)
  if not (love and love.graphics and love.graphics.rectangle) then return end
  local g = love.graphics
  local r, gg, b, al = g.getColor()
  ringOutline(g, math.floor(a.x - camX), math.floor(a.y - camY), a.rx, a.ry, a.alpha)
  g.setColor(r, gg, b, al)
end

--- The rings around the waterline of the tile whose top-left is (gx, gy), as a field
--- actor drawn on the water (under a Pokemon standing in it), or nil once they are done.
--- `slot` (optional, 1-8): which of the owner's ring sets it is, so each keeps its own actor.
function SpawnFx.ringsActor(age, gx, gy, py, elevation, id, slot)
  if age >= SpawnFx.ringsTicks() then return nil end
  local n = tonumber(id) or 0
  local a = pooledActor(n * 16 + ((tonumber(slot) or 1) - 1) % 8, "ow_spawn_rings", drawRings)
  a.elevation = elevation or 3
  a.sortY = py - 0.4 -- on the water: under the Pokemon surfacing through it
  a.x, a.y, a.i, a.age = gx + 8, gy + 15, 91700 + n, age
  return a
end

--- A wake ring `age` ticks after a swimmer left a tile: { rx, ry, alpha }, or nil once it
--- has faded. One small ring, growing r0 -> r1 (cfg = Config.SWIM.wake). Pure (tested).
-- the wake ring `age` ticks in: rx, ry, alpha, or nil once it has faded
local function wakeAt(age, cfg)
  local life = cfg and cfg.life or 28
  age = tonumber(age) or 0
  if age < 0 or age >= life then return nil end
  local p = age / life
  local grow = 1 - (1 - p) * (1 - p)
  local r0, r1 = cfg and cfg.r0 or 3, cfg and cfg.r1 or 10
  local rx = r0 + (r1 - r0) * grow
  return rx, rx * SpawnFx.RING_FLAT, math.min(1, p / 0.15) * (1 - p) * 0.7
end

function SpawnFx.wake(age, cfg)
  local rx, ry, alpha = wakeAt(age, cfg)
  if not rx then return nil end
  return { rx = rx, ry = ry, alpha = alpha }
end

--- A wake ring on the tile whose top-left is (gx, gy), as a field actor on the water, or nil.
--- `slot` (optional, 1-8): which of the owner's wakes it is, so each keeps its own actor.
function SpawnFx.wakeActor(age, cfg, gx, gy, elevation, id, slot)
  local rx, ry, alpha = wakeAt(age, cfg)
  if not rx then return nil end
  local n = tonumber(id) or 0
  local a = pooledActor(n * 16 + 8 + ((tonumber(slot) or 1) - 1) % 8, "ow_swim_wake", drawWake)
  a.elevation, a.sortY = elevation or 3, gy - 0.4
  a.x, a.y, a.i = gx + 8, gy + 15, 91800 + n
  a.rx, a.ry, a.alpha = rx, ry, alpha
  return a
end

return SpawnFx
