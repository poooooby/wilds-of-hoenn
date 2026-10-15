-- How a flying Pokemon moves and how high up it looks (pure; lib/sky_flyers.lua and
-- lib/spawn_manager.lua drive it, lib/sky_draw.lua draws it).
--
-- The field camera looks straight down, so height is depth: a bird higher up is CLOSER
-- to the camera. It is drawn bigger, it slides across the ground faster than the ground
-- does when the view scrolls, and it is out of focus. `h` runs 0 (on the ground / low)
-- to 1 (high); FlightPath.look(h) gives every value for it from Config.FLYERS.layers.
--
-- Positions are world px of the bird's ground point (the top-left of the 16 px tile it
-- is over, like every actor). A bird at height h is seen at
--     screen = centre + (world - camera - centre) * parallax(h)
-- (centre = the middle of the view), so a low bird sits exactly on its tile and a high
-- one is pushed out from the middle of the view, as perspective does.
--
-- A flight is a PLAN: a list of phases run one after another, each `n` ticks:
--   fly   from {x, y, h} to {x, y, h}: eased, with a gentle sideways curve
--   sit   at {x, y} (lift px up: a roof, a sign); turns and little hops now and then
--   hop   from {x, y, lift} to {x, y, lift}: a short arc (off a perch to the ground)
--   sink  into the water (sink 0 -> 1), `rise` back out (1 -> 0)
--   under hidden below the water
-- A phase may carry `event` ("splash", "rustle", "land" ...): reported on its first tick.
local V = ...
local Config = V.require("config")
local RecallMath = V.require("recall_math")

local FlightPath = {}

local function lerp(a, b, t) return a + (b - a) * t end

--- Every look value for height `h` (clamped to 0..1), interpolated between the layers:
--- { scale, parallax, blur, alpha, haze }. Filled into `out` when given (no new table:
--- it is asked for every bird every frame).
function FlightPath.look(h, layers, out)
  layers = layers or Config.FLYERS.layers
  h = math.max(0, math.min(1, tonumber(h) or 0))
  local lo, hi = layers[1], layers[#layers]
  for i = 1, #layers - 1 do
    if h >= layers[i].h and h <= layers[i + 1].h then lo, hi = layers[i], layers[i + 1] break end
  end
  local span = hi.h - lo.h
  local t = span > 0 and (h - lo.h) / span or 0
  out = out or {}
  out.scale, out.parallax = lerp(lo.scale, hi.scale, t), lerp(lo.parallax, hi.parallax, t)
  out.blur, out.alpha, out.haze = lerp(lo.blur, hi.blur, t), lerp(lo.alpha, hi.alpha, t), lerp(lo.haze, hi.haze, t)
  return out
end

--- Just the parallax at height `h` (FlightPath.look's, without building a look).
function FlightPath.parallaxAt(h, layers)
  layers = layers or Config.FLYERS.layers
  h = math.max(0, math.min(1, tonumber(h) or 0))
  local lo, hi = layers[1], layers[#layers]
  for i = 1, #layers - 1 do
    if h >= layers[i].h and h <= layers[i + 1].h then lo, hi = layers[i], layers[i + 1] break end
  end
  local span = hi.h - lo.h
  return lerp(lo.parallax, hi.parallax, span > 0 and (h - lo.h) / span or 0)
end

--- Where a bird over world point (wx, wy) at `parallax` is seen on screen (px from the
--- view's top-left), the view being `vw` x `vh` with its top-left at (camX, camY).
function FlightPath.toScreen(wx, wy, parallax, camX, camY, vw, vh)
  local cx, cy = vw / 2, vh / 2
  return cx + (wx - camX - cx) * parallax, cy + (wy - camY - cy) * parallax
end

--- The world point a bird at `parallax` must be over to be seen at screen (sx, sy).
function FlightPath.fromScreen(sx, sy, parallax, camX, camY, vw, vh)
  local cx, cy = vw / 2, vh / 2
  return camX + cx + (sx - cx) / parallax, camY + cy + (sy - cy) / parallax
end

--- The facing for moving by (dx, dy): the stronger axis wins; nil when not moving.
function FlightPath.facing(dx, dy)
  if math.abs(dx) < 1e-6 and math.abs(dy) < 1e-6 then return nil end
  if math.abs(dx) >= math.abs(dy) then return dx < 0 and "left" or "right" end
  return dy < 0 and "up" or "down"
end

--- A point just outside the view (px from its top-left, `margin` beyond the edge) on a
--- random side, and the side ("left" | "right" | "top" | "bottom").
function FlightPath.edgePoint(vw, vh, margin, rng, side)
  rng = rng or math.random
  side = side or ({ "left", "right", "top", "bottom" })[rng(1, 4)]
  if side == "left" then return -margin, rng(0, vh), side end
  if side == "right" then return vw + margin, rng(0, vh), side end
  if side == "top" then return rng(0, vw), -margin, side end
  return rng(0, vw), vh + margin, side
end

local OPPOSITE = { left = "right", right = "left", top = "bottom", bottom = "top" }
FlightPath.OPPOSITE = OPPOSITE

-- ------- plans ---------------------------------------------------------------

--- A new plan running `phases` in order. `rng(a, b)` (default math.random) picks the
--- fidgets of a sit.
function FlightPath.plan(phases, rng)
  return { phases = phases, i = 1, t = 0, rng = rng or math.random, facing = "down" }
end

--- The phase now running, or nil once the plan is done.
function FlightPath.current(plan)
  return plan and plan.phases[plan.i]
end

--- True once every phase has run.
function FlightPath.done(plan)
  return not plan or plan.i > #plan.phases
end

-- a sit's turns and hops: the next one `fidget` ticks on (either, or both in a row)
local function scheduleFidget(plan, ph)
  local f = ph.fidget or Config.FLYERS.perch.fidget
  ph.nextFidget = (ph.age or 0) + plan.rng(f[1], f[2])
end

local FACINGS = { "down", "left", "right", "up" }

--- Ends the phase now running (a perched bird scared off: the next phase starts at once).
function FlightPath.skip(plan)
  if FlightPath.done(plan) then return end
  plan.i, plan.t = plan.i + 1, 0
end

--- Replaces everything after the phase now running (or, with `now`, the phase too).
function FlightPath.replaceRest(plan, phases, now)
  local keep = now and plan.i - 1 or plan.i
  for k = #plan.phases, keep + 1, -1 do plan.phases[k] = nil end
  for _, p in ipairs(phases) do plan.phases[#plan.phases + 1] = p end
  if now then plan.t = 0 end
end

--- One tick of the plan. Returns the bird's state now:
--- { x, y, h, lift, sink, hidden, flapping, sitting, facing, events = {...} } (events:
--- this tick's phase-start events), or nil once the plan is done.
local NO_EVENTS = setmetatable({}, { __newindex = function() error("FlightPath: events are read only") end })

function FlightPath.step(plan)
  local ph = FlightPath.current(plan)
  if not ph then return nil end
  -- one state table per plan, refilled every tick (read it before the next step)
  local s = plan._s
  if not s then s = {} plan._s = s end
  s.events = NO_EVENTS
  if plan.t == 0 then
    if ph.event then
      local ev = plan._ev
      if not ev then ev = {} plan._ev = ev end
      ev[1] = ph.event
      s.events = ev
    end
    if ph.type == "sit" then ph.age = 0 scheduleFidget(plan, ph) end
  end
  plan.t = plan.t + 1
  local n = math.max(1, ph.n or 1)
  local p = math.min(1, plan.t / n)
  s.h, s.lift, s.sink = 0, 0, 0
  s.x, s.y, s.flapping, s.alpha, s.sitting, s.hop, s.hidden = nil, nil, nil, nil, nil, nil, nil

  if ph.type == "fly" then
    local a, b = ph.from, ph.to
    local e = RecallMath.ease(p)
    local x, y = lerp(a.x, b.x, e), lerp(a.y, b.y, e)
    -- a gentle curve, sideways to the line flown
    local dx, dy = b.x - a.x, b.y - a.y
    local len = math.sqrt(dx * dx + dy * dy)
    if len > 0 and (ph.curve or 0) ~= 0 then
      local bow = math.sin(math.pi * e) * ph.curve
      x, y = x - dy / len * bow, y + dx / len * bow
    end
    -- a swimmer's wiggle: a small side to side wave along the way (`wave` = { amp, cycles })
    if len > 0 and ph.wave then
      local w = math.sin(p * math.pi * 2 * ph.wave[2]) * ph.wave[1]
      x, y = x - dy / len * w, y + dx / len * w
    end
    -- a bird's bob: up and down with its wing beat (`bob` = { amp, ticks }: px either way, a
    -- full rise and fall every `ticks`), in the plan's own units (screen px for a passer)
    if ph.bob then
      y = y + math.sin(plan.t / ph.bob[2] * math.pi * 2) * ph.bob[1]
    end
    s.x, s.y = x, y
    s.h = lerp(a.h or 0, b.h or 0, e)
    s.lift = lerp(a.lift or 0, b.lift or 0, e)
    s.flapping = true
    plan.facing = FlightPath.facing(dx, dy) or plan.facing
    -- fading out over its last fifth (a bird leaving: should the view have followed it, it
    -- never just vanishes on screen)
    if ph.fadeOut then s.alpha = math.max(0, math.min(1, (1 - p) / 0.2)) end
  elseif ph.type == "sit" then
    ph.age = (ph.age or 0) + 1
    s.x, s.y, s.lift, s.sitting = ph.at.x, ph.at.y, ph.at.lift or 0, true
    if ph.facing and plan.t == 1 then plan.facing = ph.facing end
    if ph.age >= ph.nextFidget then
      local roll = plan.rng(1, 3)
      if roll ~= 2 then -- turn (1) or turn then hop (3)
        local cur, pick = plan.facing, plan.facing
        for _ = 1, 4 do
          pick = FACINGS[plan.rng(1, #FACINGS)]
          if pick ~= cur then break end
        end
        plan.facing = pick
      end
      if roll ~= 1 then ph.hopAt = ph.age end
      scheduleFidget(plan, ph)
    end
    local hopTicks = Config.FLYERS.hopTicks
    if ph.hopAt and ph.age - ph.hopAt < hopTicks then
      s.hop = math.sin(math.pi * (ph.age - ph.hopAt) / hopTicks) * Config.FLYERS.hopHeight
    end
  elseif ph.type == "hop" then
    local a, b = ph.from, ph.to
    s.x, s.y = lerp(a.x, b.x, p), lerp(a.y, b.y, p)
    s.lift = lerp(a.lift or 0, b.lift or 0, p)
    s.hop = math.sin(math.pi * p) * (ph.height or 8)
    s.flapping = true
    plan.facing = FlightPath.facing(b.x - a.x, b.y - a.y) or plan.facing
  elseif ph.type == "sink" or ph.type == "rise" or ph.type == "under" then
    s.x, s.y = ph.at.x, ph.at.y
    if ph.type == "under" then s.sink, s.hidden = 1, true
    else
      local e = RecallMath.ease(p)
      s.sink = ph.type == "sink" and e or 1 - e
    end
  end
  s.facing = plan.facing
  if plan.t >= n then plan.i, plan.t = plan.i + 1, 0 end
  return s
end

return FlightPath
