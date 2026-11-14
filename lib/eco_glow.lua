-- Lights in the dark (part of Wild Reacts' ecology): at night a Pokemon whose profile has a
-- `glow` (lib/eco_species.lua) shows its light -- Volbeat's tail, Chinchou's and Lanturn's lures,
-- Litwick's flame, Morelull's caps, Charmander's tail flame ... -- a soft code-drawn light on
-- its art, pulsing gently. A `trail` glow (a firefly) leaves a fading line of light behind it
-- as it moves. Under the water (diving, sunk) the light still shows, dimmer and wider.
--
--   glow = { color = { r, g, b }, at = "top" | "body" | "tail", trail = true | nil }
--
-- No tables are built per frame: each Pokemon keeps its trail in a small ring it reuses, and
-- one draw function reads the actor's fields.
local V = ...
local Config = V.require("config")

local EcoGlow = {}

--- Where the light sits, px from the Pokemon's tile top-left, for art reaching `lift` px above
--- the tile's bottom and `reach` px ahead of its centre (left / right). Pure.
function EcoGlow.pointOf(at, facing, lift, reach)
  if at == "top" then return 8, 16 - lift + 3 end
  if at == "body" then return 8, 16 - lift * 0.5 end
  -- a tail: behind it, low down
  local y = 16 - lift * 0.35
  if facing == "left" then return 8 + reach * 0.8, y end
  if facing == "right" then return 8 - reach * 0.8, y end
  if facing == "up" then return 8, y + 2 end
  return 8, y - 2
end

--- The light's strength at tick `t`: a slow breath between 0.75 and 1. Pure.
function EcoGlow.pulse(t, id)
  local cfg = Config.ECO.glow
  return 0.75 + 0.25 * (0.5 + 0.5 * math.sin((t + (id or 0) * 17) / cfg.pulseTicks * 2 * math.pi))
end

local function lightPoint(e)
  local g = e.profile and e.profile.glow
  local r = e.renderer
  local lift = (r and r.headLift and r:headLift()) or 20
  local reach = 0
  if g.at == "tail" then
    reach = (r and r.frontReach and r:frontReach(e.facing)) or ((r and r.visualWidth and r:visualWidth() or 20) * 0.4)
  end
  local x, y = EcoGlow.pointOf(g.at, e.facing, lift, reach)
  local act = r and r.act
  if act then x, y = x + (act.dx or 0), y + (act.dy or 0) end
  return e.px + x, e.py + y + (r and r.bobDy or 0)
end

--- One tick: a trail glow drops a point of light behind it every few ticks while it moves;
--- the points fade. `night`: lights are on.
function EcoGlow.tick(e, night)
  local g = e.profile and e.profile.glow
  if not g then return end
  local cfg = Config.ECO.glow
  local trail = e.glowTrail
  if trail then
    for i = 1, #trail do local p = trail[i] if p.age < cfg.trailTicks then p.age = p.age + 1 end end
  end
  if not (night and g.trail) then return end
  e.glowT = (e.glowT or 0) + 1
  local moving = e.moving or e.riderMoving
  if not moving or e.glowT % cfg.trailEvery ~= 0 then return end
  if not trail then trail = {} e.glowTrail = trail end
  -- the ring: reuse the oldest point
  local slot = (e.glowNext or 0) % cfg.trailMax + 1
  e.glowNext = slot
  local p = trail[slot]
  if not p then p = {} trail[slot] = p end
  p.x, p.y = lightPoint(e)
  p.age = 0
end

local function setLight(g, c, a)
  g.setColor(c[1], c[2], c[3], a)
end

-- one light: a bright core, a halo, a faint outer glow (additive)
local function drawLight(a, camX, camY)
  local g = love and love.graphics
  if not (g and g.circle) then return end
  local x, y = math.floor(a.x - camX) + 0.5, math.floor(a.y - camY) + 0.5
  local c, k, rad = a.color, a.strength, a.radius
  local blend, alphaMode = g.getBlendMode()
  local r0, g0, b0, a0 = g.getColor()
  -- (the coloured halo is painted, not added: Gen 3 has no dark nights, and light added to a
  -- bright field barely shows; only the hot core is added light)
  if a.points then
    -- a trail: fading dots of its colour, each with a bright heart
    local cfg = Config.ECO.glow
    for _, p in ipairs(a.points) do
      if p.age < cfg.trailTicks then
        local f = 1 - p.age / cfg.trailTicks
        local px, py = math.floor(p.x - camX) + 0.5, math.floor(p.y - camY) + 0.5
        g.setBlendMode("alpha")
        setLight(g, c, 0.7 * f * k)
        g.circle("fill", px, py, 1 + f)
        g.setBlendMode("add")
        g.setColor(1, 1, 1, 0.5 * f * k)
        g.circle("fill", px, py, 0.8)
      end
    end
  else
    g.setBlendMode("alpha")
    setLight(g, c, 0.18 * k)
    g.circle("fill", x, y, rad * 4)
    setLight(g, c, 0.45 * k)
    g.circle("fill", x, y, rad * 2.2)
    if not a.under then
      g.setBlendMode("add")
      g.setColor(1, 1, 1, 0.9 * k)
      g.circle("fill", x, y, rad)
    end
  end
  g.setBlendMode(blend, alphaMode)
  g.setColor(r0, g0, b0, a0)
end
EcoGlow._draw = drawLight

--- Appends `e`'s light (and its trail) at night. `t`: the clock for its pulse.
function EcoGlow.collect(e, actors, t)
  local g = e.profile and e.profile.glow
  if not g then return end
  local cfg = Config.ECO.glow
  local r = e.renderer
  local sink = (r and r.act and r.act.sink) or 0
  local under = sink >= 0.5 or (e.fx and e.fx.under) or false
  local k = EcoGlow.pulse(t or 0, e.id) * (under and cfg.underAlpha or 1)
  local x, y = lightPoint(e)
  actors[#actors + 1] = { kind = "ow_glow", i = 99000 + (e.id or 0), x = x, y = y, sortY = e.py + 1,
    elevation = e.elevation, color = g.color, strength = k, under = under,
    radius = under and cfg.radius * cfg.underGrow or cfg.radius, draw = drawLight }
  if e.glowTrail then
    actors[#actors + 1] = { kind = "ow_glow", i = 99500 + (e.id or 0), x = x, y = y, sortY = e.py + 1,
      elevation = e.elevation, color = g.color, strength = 1, points = e.glowTrail, draw = drawLight }
  end
end

return EcoGlow
