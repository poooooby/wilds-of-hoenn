-- Little touches on your partner, drawn the same way as the Battler's type effects
-- (lib/finisher_fx.lua shapes and parts):
--
--   levelUp     a gold ring and sparkles rising round it when a Battler win levels it up
--   evolveGlow  sparkles drifting up round it, now and then, while it is ready to evolve
--   typePuff    a soft puff of its own type (embers, droplets, leaves ...) -- while you Pet /
--               Play / Talk with it, and, with the Type Aura option, slowly while it walks
--
-- Every `*Parts` function is pure (tested): parts relative to the body's centre.
local V = ...
local FinisherFx = V.require("finisher_fx")
local EnginePatch = V.require("engine_patch")

local PartnerFx = {}

PartnerFx.LEVEL_TICKS = 60
PartnerFx.EVOLVE_PERIOD = 120 -- ticks per drift of evolve sparkles
PartnerFx.PUFF_PERIOD = 45    -- ticks between puffs while you interact with it
PartnerFx.AURA_PERIOD = 200   -- ... and with the Type Aura option, while it is out

local GOLD = { 1.0, 0.86, 0.30 }

local function clamp01(v) return v < 0 and 0 or (v > 1 and 1 or v) end

--- The partner's type kind (a FinisherFx kind): its first type, or its second when the first
--- is Normal (a Pidgey reads as Flying). nil when unknown.
function PartnerFx.kindFor(species)
  if not EnginePatch.speciesTypes then return nil end
  local a, b = EnginePatch.speciesTypes(species)
  if a == nil then return nil end
  local ka, kb = FinisherFx.kindFor(a), b and FinisherFx.kindFor(b) or nil
  if ka == "NORMAL" and kb and kb ~= "NORMAL" then return kb end
  return ka
end

--- `age` ticks into the level-up flourish.
function PartnerFx.levelUpParts(age)
  local out = {}
  age = tonumber(age) or 0
  if age < 0 or age >= PartnerFx.LEVEL_TICKS then return out end
  local p = age / PartnerFx.LEVEL_TICKS
  -- a gold ring rising from the feet to over the head
  out[#out + 1] = { "ring", 9 - 3 * p, GOLD[1], GOLD[2], GOLD[3], 1 - p, 0, 6 - 22 * p }
  -- sparkles spiralling up
  for i = 0, 3 do
    local t = age - i * 6
    if t >= 0 and t < 40 then
      local q = t / 40
      local a = i * math.pi / 2 + q * 4
      out[#out + 1] = { "shape", "sparkle", math.cos(a) * 9, 6 - 26 * q, clamp01((1 - q) * 1.5) }
    end
  end
  return out
end

--- `age` ticks into being ready to evolve (it repeats every EVOLVE_PERIOD).
function PartnerFx.evolveParts(age)
  local out = {}
  local t = (tonumber(age) or 0) % PartnerFx.EVOLVE_PERIOD
  for i = 0, 2 do
    local u = t - i * 10
    if u >= 0 and u < 50 then
      local q = u / 50
      local side = (i - 1) * 7
      out[#out + 1] = { "shape", "sparkle", side + math.sin(q * 5 + i) * 2, 4 - 20 * q, math.sin(q * math.pi) * 0.9 }
    end
  end
  return out
end

--- A soft puff of `kind` `age` ticks into a cycle of `period` ticks (one puff each cycle).
function PartnerFx.typePuffParts(kind, age, period)
  local out = {}
  period = period or PartnerFx.PUFF_PERIOD
  local t = (tonumber(age) or 0) % period
  if t >= 30 then return out end
  local q = t / 30
  local s = FinisherFx.SPARKS[kind] or FinisherFx.SPARKS.NORMAL
  local shape = (s[1] ~= "ring" and s[1] ~= "streak") and s[1] or nil
  local fade = math.sin(q * math.pi) * 0.85
  if shape then
    for i = 0, 1 do
      local side = i == 0 and -5 or 5
      out[#out + 1] = { "shape", shape, side + math.sin(q * 4 + i) * 2, -2 - 10 * q, fade }
    end
  elseif s[1] == "ring" then
    out[#out + 1] = { "ring", 3 + 6 * q, s.hue[1], s.hue[2], s.hue[3], fade, 0, -8 }
  else
    out[#out + 1] = { "line", -6 + 12 * q, -8, -2 + 12 * q, -10, s.hue[1], s.hue[2], s.hue[3], fade }
  end
  return out
end

--- A field actor drawing `parts` round the body whose tile top-left is world (x, y),
--- `lift` = its height (the body's centre is half of it above the ground point).
function PartnerFx.actor(parts, x, y, lift, elevation, id)
  if #parts == 0 then return nil end
  local cy = y + 15 - (tonumber(lift) or 16) / 2
  return {
    kind = "ow_partner_fx", elevation = elevation or 3, oamPriority = 1, parts = parts,
    sortY = y + 93, x = x + 8, y = cy,
    i = 90970 + (tonumber(id) or 0),
    draw = function(_, camX, camY)
      if not (love and love.graphics and love.graphics.rectangle) then return end
      FinisherFx.drawParts(love.graphics, parts, math.floor(x + 8 - camX), math.floor(cy - camY))
    end,
  }
end

return PartnerFx
