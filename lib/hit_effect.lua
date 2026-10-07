-- The impact flash when a move lands in an overworld skirmish.
--
-- The engine's battle "hit" sprite lives in the battle animation system (it
-- needs a running animation VM), so it cannot be drawn on the field. What the
-- field does have is the engine's own ground-impact dust sheet
-- (field_effects "ground_impact_dust"): that plays under the defender, with a
-- small burst of lines drawn over it. Either half is optional -- no engine
-- sheet means just the burst, no love.graphics means nothing at all.
local V = ...
local EnginePatch = V.require("engine_patch")

local HitEffect = {}

HitEffect.LIFE = 12 -- ticks

--- Burst geometry for an effect `age` ticks old: ray length / thickness and
--- how far the rays have flown out. Pure (tested).
function HitEffect.burst(age)
  local t = math.max(0, math.min(1, age / HitEffect.LIFE))
  return { reach = 3 + 7 * t, length = 4 * (1 - t) + 1, alpha = 1 - t * t }
end

--- Which of the engine's 3 dust frames to show at `age` (nil when over).
function HitEffect.dustFrame(age)
  if age < 0 or age >= HitEffect.LIFE then return nil end
  return math.min(2, math.floor(age * 3 / HitEffect.LIFE))
end

--- The effect as a field actor at the tile whose top-left is (wx, wy), `age`
--- ticks into its life; `heavy` (a super-effective or critical hit) widens it.
function HitEffect.actor(wx, wy, age, heavy, elevation, id)
  if age >= HitEffect.LIFE then return nil end
  local cx, cy = wx + 8, wy + 6
  return {
    kind = "ow_hit_effect",
    elevation = elevation or 3,
    sortY = wy + 90,
    x = cx, y = cy,
    i = 90800 + (tonumber(id) or 0),
    draw = function(_, camX, camY)
      if not (love and love.graphics and love.graphics.line) then return end
      local g = love.graphics
      local sx, sy = math.floor(cx - camX), math.floor(cy - camY)
      -- the engine's impact dust under the feet
      local frame = HitEffect.dustFrame(age)
      local sheet = frame and EnginePatch.fieldEffectSheet("ground_impact_dust", 16, 8, 3)
      if sheet and sheet.image and sheet.quads and sheet.quads[frame] then
        g.setColor(1, 1, 1, 1)
        g.draw(sheet.image, sheet.quads[frame], sx - 8, sy + 6)
      end
      -- the burst
      local b = HitEffect.burst(age)
      local rays = heavy and 8 or 6
      g.setColor(1, 0.95, 0.5, b.alpha)
      for i = 0, rays - 1 do
        local a = (i / rays) * math.pi * 2 + 0.3
        local x1, y1 = sx + math.cos(a) * b.reach, sy + math.sin(a) * b.reach
        local x2, y2 = sx + math.cos(a) * (b.reach + b.length), sy + math.sin(a) * (b.reach + b.length)
        g.line(math.floor(x1), math.floor(y1), math.floor(x2), math.floor(y2))
      end
      g.setColor(1, 1, 1, b.alpha)
      g.circle("fill", sx, sy, 1 + (1 - age / HitEffect.LIFE) * (heavy and 4 or 3))
      g.setColor(1, 1, 1, 1)
    end,
  }
end

return HitEffect
