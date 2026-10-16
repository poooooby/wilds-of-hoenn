-- The Battler's knockout blow (lib/overworld_battle.lua): an effect matching the TYPE of
-- the finishing move -- a splash of water exploding outward, a burst of flame, flying leaves, a bolt,
-- shards of ice or rock, Fairy sparkles and hearts ... one per type, Fairy included
-- (type 18, which National Dex Gen 3 adds).
--
-- Each recipe is the engine's own field-effect art where the game has a fitting sheet
-- (EnginePatch.fieldEffectSheet: jump_big_splash, cut_grass, deoxys_rock_fragments,
-- sparkle ...) plus code-drawn particles (lib/pixel_shapes.lua shapes, lines, rings).
-- Every recipe looks right with the code-drawn part alone -- the Game Boy games and an
-- engine without the sheet get exactly that. `shade` tints the defeated Pokemon while it
-- goes down; `fade` makes it fade out instead of sinking (Ghost); `se` is the matching
-- battle move sound, played as the blow lands.
--
-- `FinisherFx.particles(kind, age)` is pure (tested); `FinisherFx.actor` draws it as one
-- untagged field actor (gen3-hd-sprites spends no layer on it).
local V = ...
local EnginePatch = V.require("engine_patch")
local PixelShapes = V.require("pixel_shapes")
V.require("mood_fx") -- registers its shapes (flame, spark, snow, bubble, sparkle, heart)

local FinisherFx = {}

FinisherFx.TICKS = 56 -- the whole effect (the defeated Pokemon holds Config.OW_BATTLE.winPause
                      -- ticks, past the effect's peak, before it goes down)

-- ------------------------------------------------------------------ shapes
PixelShapes.defineAll({
  droplet = {
    rows = { { 0, 1, 0 }, { 1, 2, 1 }, { 1, 1, 1 }, { 0, 1, 0 } },
    colours = { { 0.36, 0.62, 1.0 }, { 0.86, 0.95, 1.0 } },
  },
  leaf = {
    rows = { { 0, 0, 1, 1 }, { 0, 1, 2, 1 }, { 1, 2, 1, 0 }, { 1, 1, 0, 0 } },
    colours = { { 0.20, 0.58, 0.22 }, { 0.55, 0.86, 0.38 } },
  },
  rock = {
    rows = { { 0, 1, 1, 0 }, { 1, 2, 1, 1 }, { 1, 1, 1, 3 }, { 0, 1, 3, 0 } },
    colours = { { 0.55, 0.48, 0.40 }, { 0.78, 0.72, 0.62 }, { 0.36, 0.30, 0.26 } },
  },
  crystal = {
    rows = { { 0, 1, 0 }, { 1, 2, 1 }, { 1, 2, 1 }, { 1, 2, 1 }, { 0, 1, 0 } },
    colours = { { 0.45, 0.75, 1.0 }, { 0.92, 0.98, 1.0 } },
  },
  feather = {
    rows = { { 0, 0, 0, 1 }, { 0, 0, 1, 2 }, { 0, 1, 2, 0 }, { 1, 2, 0, 0 }, { 1, 0, 0, 0 } },
    colours = { { 0.80, 0.82, 0.88 }, { 1, 1, 1 } },
  },
  wisp = {
    rows = { { 0, 1, 0 }, { 1, 2, 1 }, { 1, 2, 1 }, { 0, 1, 1 }, { 0, 0, 1 } },
    colours = { { 0.42, 0.22, 0.62 }, { 0.78, 0.60, 0.95 } },
  },
  star = {
    rows = {
      { 0, 0, 0, 1, 0, 0, 0 },
      { 0, 0, 1, 2, 1, 0, 0 },
      { 1, 1, 2, 2, 2, 1, 1 },
      { 0, 1, 2, 2, 2, 1, 0 },
      { 0, 1, 2, 1, 2, 1, 0 },
      { 1, 1, 0, 0, 0, 1, 1 },
    },
    colours = { { 0.98, 0.78, 0.30 }, { 1, 1, 0.92 } },
  },
  ember = {
    rows = { { 1, 2 }, { 2, 1 } },
    colours = { { 1.0, 0.55, 0.12 }, { 1.0, 0.88, 0.40 } },
  },
  speck = {
    rows = { { 1, 1 }, { 1, 1 } },
    colours = { { 0.60, 0.78, 0.22 } },
  },
  dust = {
    rows = { { 0, 1, 0 }, { 1, 2, 1 }, { 0, 1, 0 } },
    colours = { { 0.62, 0.48, 0.30 }, { 0.80, 0.68, 0.48 } },
  },
  pinkheart = {
    rows = {
      { 0, 2, 0, 2, 0 },
      { 2, 1, 2, 1, 2 },
      { 2, 1, 1, 1, 2 },
      { 0, 2, 1, 2, 0 },
      { 0, 0, 2, 0, 0 },
    },
    colours = { { 1.0, 0.72, 0.86 }, { 0.88, 0.36, 0.62 } },
  },
  dragonflame = {
    rows = {
      { 0, 0, 1, 0, 0 },
      { 0, 1, 1, 0, 0 },
      { 0, 1, 2, 1, 0 },
      { 1, 2, 3, 2, 1 },
      { 1, 2, 3, 2, 1 },
      { 0, 1, 2, 1, 0 },
    },
    colours = { { 0.34, 0.20, 0.72 }, { 0.46, 0.46, 0.96 }, { 0.80, 0.86, 1.0 } },
  },
  metal = {
    rows = { { 0, 1, 0 }, { 1, 2, 1 }, { 0, 1, 0 } },
    colours = { { 0.62, 0.66, 0.74 }, { 1, 1, 1 } },
  },
})

-- ------------------------------------------------------------------ motion (pure)
-- every helper appends parts to `out`:
--   { "shape", name, dx, dy, alpha [, scale] }      centred on (dx, dy)
--   { "line", x1, y1, x2, y2, r, g, b, alpha }
--   { "ring", radius, r, g, b, alpha }
--   { "flash", r, g, b, alpha }                     a soft disc over the body
-- dx / dy from the body's centre (dy negative = up).

local function clamp01(v) return v < 0 and 0 or (v > 1 and 1 or v) end
local function fade(p, inn, out) return clamp01(p / inn) * clamp01((1 - p) / out) end

-- `n` shapes flung out from the centre, slowing, dropping under `grav`, fading
local function burst(out, age, name, n, speed, life, grav, delay, scale, turn)
  local t = age - (delay or 0)
  if t < 0 or t >= life then return end
  local p = t / life
  for i = 1, n do
    local a = (i - 1) / n * math.pi * 2 + (turn or 0.4)
    local d = speed * life * (1 - (1 - p) * (1 - p)) * 0.5
    out[#out + 1] = { "shape", name, math.cos(a) * d, math.sin(a) * d * 0.7 + (grav or 0) * t * t * 0.0025,
      fade(p, 0.08, 0.35), scale }
  end
end

-- `n` shapes rising from the body (staggered), swaying
local function rise(out, age, name, n, spread, height, life, delay, scale)
  for i = 1, n do
    local t = age - (delay or 0) - (i - 1) * 4
    if t >= 0 and t < life then
      local p = t / life
      local side = ((i - 1) % 3 - 1) * spread
      out[#out + 1] = { "shape", name, side + math.sin(p * 6 + i) * 2, 2 - height * p, fade(p, 0.15, 0.35), scale }
    end
  end
end

-- `n` shapes drifting down from above the body
local function fall(out, age, name, n, spread, life, delay)
  for i = 1, n do
    local t = age - (delay or 0) - (i - 1) * 5
    if t >= 0 and t < life then
      local p = t / life
      local x = ((i - 1) / math.max(1, n - 1) - 0.5) * 2 * spread
      out[#out + 1] = { "shape", name, x + math.sin(p * 5 + i) * 3, -14 + 22 * p, fade(p, 0.15, 0.3) }
    end
  end
end

-- `n` rings growing out of the body, staggered
local function rings(out, age, n, r, g, b, life, maxR, stagger)
  for i = 1, n do
    local t = age - (i - 1) * (stagger or 7)
    if t >= 0 and t < life then
      local p = t / life
      out[#out + 1] = { "ring", 3 + (maxR - 3) * (1 - (1 - p) * (1 - p)), r, g, b, 1 - p }
    end
  end
end

local function flash(out, age, r, g, b, life, peak)
  if age < life then out[#out + 1] = { "flash", r, g, b, (peak or 0.8) * (1 - age / life) } end
end

-- a zig-zag bolt from above down onto the body, flickering
local function bolt(out, age, life)
  if age >= life or (age % 4) >= 3 then return end
  local pts = { { -2, -40 }, { 4, -30 }, { -3, -22 }, { 3, -12 }, { -1, -4 }, { 0, 2 } }
  local a = 1 - age / life
  for i = 1, #pts - 1 do
    local p, q = pts[i], pts[i + 1]
    out[#out + 1] = { "line", p[1], p[2], q[1], q[2], 1.0, 0.95, 0.40, a }
    out[#out + 1] = { "line", p[1] + 1, p[2], q[1] + 1, q[2], 1.0, 1.0, 0.85, a * 0.7 }
  end
end

-- straight streaks sweeping across (wind, a slash)
local function streaks(out, age, n, life, len, r, g, b, slope, delay)
  local t = age - (delay or 0)
  if t < 0 or t >= life then return end
  local p = t / life
  for i = 1, n do
    local y = -10 + (i - 1) * (16 / math.max(1, n - 1))
    local x = -18 + 36 * p + (i % 2) * 4
    out[#out + 1] = { "line", x - len, y - len * slope, x, y, r, g, b, fade(p, 0.1, 0.4) }
  end
end

-- ------------------------------------------------------------------ recipes
-- sheet = { name, fw, fh, frames, every (ticks a frame), dy (px down from the body's centre),
--           tint }; shade = {r, g, b} on the defeated Pokemon; fade = it fades, not sinks
-- se = the engine's own move sound (an SE_* name, played through the game's SFX volume)
local RECIPES = {
  WATER = {
    se = "SE_M_WATERFALL",
    sheet = { "jump_big_splash", 16, 16, 4, 6, 2 },
    particles = function(out, age)
      -- a splash exploding outward: two waves of droplets, no falling back
      flash(out, age, 0.55, 0.78, 1.0, 10, 0.6)
      burst(out, age, "droplet", 10, 0.85, 26, 0, 0)
      burst(out, age, "droplet", 8, 1.2, 22, 0, 4, nil, 0)
      rings(out, age, 1, 0.55, 0.78, 1.0, 22, 20)
    end,
  },
  FIRE = {
    se = "SE_M_FLAME_WHEEL",
    sheet = { "ash", 16, 16, 5, 6, -2, { 1.0, 0.62, 0.40 } },
    shade = { 1.0, 0.62, 0.45 },
    particles = function(out, age)
      flash(out, age, 1.0, 0.55, 0.15, 14, 0.75)
      burst(out, age, "flame", 6, 0.45, 26, 0, 0, 1)
      rise(out, age, "ember", 6, 5, 22, 36, 4)
    end,
  },
  GRASS = {
    se = "SE_M_PETAL_DANCE",
    sheet = { "cut_grass", 8, 8, 1, 30, 0 },
    particles = function(out, age)
      burst(out, age, "leaf", 7, 0.55, 26, 8, 0)
      fall(out, age, "leaf", 4, 10, 32, 14)
    end,
  },
  ELECTRIC = {
    se = "SE_M_THUNDERBOLT",
    shade = { 1.0, 1.0, 0.55 },
    particles = function(out, age)
      bolt(out, age, 16)
      flash(out, age, 1.0, 0.95, 0.45, 12, 0.8)
      burst(out, age, "spark", 6, 0.45, 22, 0, 6)
    end,
  },
  ICE = {
    se = "SE_M_ICY_WIND",
    shade = { 0.62, 0.84, 1.0 },
    particles = function(out, age)
      flash(out, age, 0.80, 0.94, 1.0, 12, 0.7)
      burst(out, age, "crystal", 8, 0.5, 26, 6, 0)
      fall(out, age, "snow", 4, 12, 34, 10)
    end,
  },
  GROUND = {
    se = "SE_M_EARTHQUAKE",
    sheet = { "ground_impact_dust", 16, 8, 3, 6, 6 },
    particles = function(out, age)
      -- the ground bursts: rocks and dust blasted straight out
      flash(out, age, 0.78, 0.62, 0.38, 12, 0.6)
      burst(out, age, "rock", 8, 0.9, 28, 0, 0)
      burst(out, age, "dust", 10, 1.2, 22, 0, 2, nil, 0)
      rings(out, age, 2, 0.70, 0.56, 0.36, 26, 22, 6)
    end,
  },
  ROCK = {
    se = "SE_M_ROCK_THROW",
    sheet = { "deoxys_rock_fragments", 8, 8, 4, 6, 0 },
    particles = function(out, age)
      flash(out, age, 0.85, 0.78, 0.66, 10, 0.6)
      -- rocks blasted straight out (no falling: they would drop off the bottom of the view)
      burst(out, age, "rock", 8, 0.9, 30, 0, 0, 1.5)
      burst(out, age, "rock", 6, 1.2, 26, 0, 4, 1, 0)
    end,
  },
  FAIRY = {
    se = "SE_M_CHARM",
    sheet = { "sparkle", 16, 16, 6, 5, -4 },
    shade = { 1.0, 0.82, 0.94 },
    particles = function(out, age)
      flash(out, age, 1.0, 0.80, 0.92, 14, 0.6)
      burst(out, age, "sparkle", 6, 0.45, 30, 0, 0)
      rise(out, age, "pinkheart", 4, 6, 20, 38, 6)
    end,
  },
  PSYCHIC = {
    se = "SE_M_PSYBEAM",
    shade = { 1.0, 0.72, 0.94 },
    particles = function(out, age)
      rings(out, age, 3, 0.95, 0.45, 0.85, 26, 22, 7)
      flash(out, age, 0.95, 0.55, 0.90, 10, 0.4)
    end,
  },
  GHOST = {
    se = "SE_M_NIGHTMARE",
    shade = { 0.62, 0.46, 0.82 }, fade = true,
    particles = function(out, age)
      rise(out, age, "wisp", 6, 7, 24, 40, 0)
      rings(out, age, 1, 0.42, 0.22, 0.62, 30, 16)
    end,
  },
  POISON = {
    se = "SE_M_TOXIC",
    sheet = { "bubbles", 16, 32, 8, 5, -8, { 0.85, 0.55, 1.0 } },
    shade = { 0.86, 0.62, 1.0 },
    particles = function(out, age)
      rise(out, age, "bubble", 6, 6, 20, 36, 0)
      flash(out, age, 0.70, 0.30, 0.85, 10, 0.4)
    end,
  },
  BUG = {
    se = "SE_M_STRING_SHOT",
    particles = function(out, age)
      burst(out, age, "speck", 8, 0.5, 24, 4, 0)
      rise(out, age, "speck", 4, 6, 14, 26, 8)
      flash(out, age, 0.70, 0.86, 0.30, 8, 0.35)
    end,
  },
  FLYING = {
    se = "SE_M_WING_ATTACK",
    particles = function(out, age)
      streaks(out, age, 4, 16, 8, 1, 1, 1, 0.25)
      fall(out, age, "feather", 4, 10, 36, 8)
    end,
  },
  FIGHTING = {
    se = "SE_M_BRICK_BREAK",
    particles = function(out, age)
      flash(out, age, 1, 1, 0.85, 10, 0.8)
      burst(out, age, "star", 1, 0, 18, 0, 0, 2)
      burst(out, age, "star", 5, 0.5, 22, 0, 2)
    end,
  },
  DRAGON = {
    se = "SE_M_DRAGON_RAGE",
    shade = { 0.72, 0.68, 1.0 },
    particles = function(out, age)
      flash(out, age, 0.40, 0.36, 0.95, 12, 0.6)
      burst(out, age, "dragonflame", 6, 0.45, 26, 0, 0)
      rise(out, age, "dragonflame", 3, 6, 18, 32, 8)
    end,
  },
  DARK = {
    se = "SE_M_BITE",
    shade = { 0.48, 0.40, 0.58 },
    particles = function(out, age)
      streaks(out, age, 3, 14, 10, 0.22, 0.12, 0.30, -0.8)
      rings(out, age, 2, 0.16, 0.08, 0.24, 24, 18, 6)
    end,
  },
  STEEL = {
    se = "SE_M_VICEGRIP",
    shade = { 0.86, 0.90, 1.0 },
    particles = function(out, age)
      flash(out, age, 0.95, 0.97, 1.0, 10, 0.85)
      burst(out, age, "metal", 7, 0.55, 24, 4, 0)
      streaks(out, age, 2, 12, 6, 1, 1, 1, -1, 6)
    end,
  },
  NORMAL = {
    se = "SE_M_TAKE_DOWN",
    particles = function(out, age)
      flash(out, age, 1, 1, 0.9, 8, 0.6)
      burst(out, age, "star", 1, 0, 14, 0, 0, 1)
      burst(out, age, "sparkle", 6, 0.5, 18, 0, 0)
    end,
  },
}
FinisherFx.RECIPES = RECIPES

--- The recipe name for a type name / id ("WATER", 11, "FAIRY", 18 ...): unknown -> NORMAL.
function FinisherFx.kindFor(t)
  local name = EnginePatch.typeName and EnginePatch.typeName(t) or (type(t) == "string" and t:upper())
  return (name and RECIPES[name]) and name or "NORMAL"
end

function FinisherFx.recipe(kind) return RECIPES[kind] or RECIPES.NORMAL end

--- The sound effect for `kind` (an SE_* name; NORMAL's for an unknown kind).
function FinisherFx.soundFor(kind) return FinisherFx.recipe(kind).se end

--- The code-drawn parts `age` ticks into `kind`'s effect. Pure.
function FinisherFx.particles(kind, age)
  local out = {}
  age = math.max(0, math.floor(tonumber(age) or 0))
  if age >= FinisherFx.TICKS then return out end
  FinisherFx.recipe(kind).particles(out, age)
  return out
end

-- ------------------------------------------------------------------ every hit
-- An ordinary blow gets a small spark of its move's type (a few droplets, embers, leaves
-- ...), sized by how well it landed, as the real battle's hit sound picks: super effective
-- bigger and brighter, not very effective small and greyed, no effect just a grey puff.
-- A critical hit adds a star and a white pulse.
FinisherFx.HIT_TICKS = 18

-- per type: the shape flung out (or "ring" / "streak" for a type drawn without one), how
-- it moves ("burst" out, "rise" up) and the colour of its flash
local SPARKS = {
  WATER = { "droplet", hue = { 0.55, 0.78, 1.0 } },
  FIRE = { "ember", hue = { 1.0, 0.55, 0.15 } },
  GRASS = { "leaf", hue = { 0.45, 0.80, 0.30 } },
  ELECTRIC = { "spark", hue = { 1.0, 0.95, 0.45 } },
  ICE = { "crystal", hue = { 0.80, 0.94, 1.0 } },
  GROUND = { "dust", hue = { 0.78, 0.62, 0.38 } },
  ROCK = { "rock", hue = { 0.85, 0.78, 0.66 } },
  FAIRY = { "sparkle", hue = { 1.0, 0.80, 0.92 } },
  PSYCHIC = { "ring", hue = { 0.95, 0.45, 0.85 } },
  GHOST = { "wisp", mode = "rise", hue = { 0.62, 0.46, 0.82 } },
  POISON = { "bubble", mode = "rise", hue = { 0.70, 0.30, 0.85 } },
  BUG = { "speck", hue = { 0.70, 0.86, 0.30 } },
  FLYING = { "feather", hue = { 1.0, 1.0, 1.0 } },
  FIGHTING = { "star", hue = { 1.0, 1.0, 0.85 } },
  DRAGON = { "dragonflame", hue = { 0.40, 0.36, 0.95 } },
  DARK = { "streak", hue = { 0.22, 0.12, 0.30 } },
  STEEL = { "metal", hue = { 0.95, 0.97, 1.0 } },
  NORMAL = { "star", hue = { 1.0, 1.0, 0.90 } },
}
FinisherFx.SPARKS = SPARKS

local GREY = { 0.62, 0.62, 0.66 }
-- how a blow landed -> { pieces, speed, scale, flash peak, greyed }
local POWER = {
  super = { 6, 0.95, 1, 0.75 },
  normal = { 4, 0.70, 1, 0.45 },
  weak = { 3, 0.45, 1, 0.20, true },
}

--- "super" | "normal" | "weak" | "immune" for an effectiveness multiplier (the engine's own
--- cut-offs, battle/anim_seq.lua effectiveness_se).
function FinisherFx.powerFor(eff)
  eff = tonumber(eff) or 1
  if eff == 0 then return "immune" end
  if eff >= 2 then return "super" end
  if eff < 1 then return "weak" end
  return "normal"
end

--- The engine's hit sound for an effectiveness multiplier, as the real battle plays it
--- (nil: a move with no effect plays none).
function FinisherFx.hitSound(eff)
  local p = FinisherFx.powerFor(eff)
  if p == "immune" then return nil end
  if p == "super" then return "SE_SUPER_EFFECTIVE" end
  if p == "weak" then return "SE_NOT_EFFECTIVE" end
  return "SE_EFFECTIVE"
end

--- The code-drawn parts `age` ticks into an ordinary hit of `kind`, landed with `power`
--- (FinisherFx.powerFor), `crit` = a critical hit. Pure.
function FinisherFx.hitParticles(kind, age, power, crit)
  local out = {}
  age = math.max(0, math.floor(tonumber(age) or 0))
  if age >= FinisherFx.HIT_TICKS then return out end
  if power == "immune" then
    rings(out, age, 1, GREY[1], GREY[2], GREY[3], 14, 10)
    burst(out, age, "dust", 3, 0.3, 14, 0, 0, nil, 0)
    for _, p in ipairs(out) do if p[1] == "shape" then p[7] = GREY end end
    return out
  end
  local pw = POWER[power] or POWER.normal
  local s = SPARKS[kind] or SPARKS.NORMAL
  local hue = pw[5] and GREY or s.hue
  local life = FinisherFx.HIT_TICKS - 2
  flash(out, age, hue[1], hue[2], hue[3], 8, pw[4])
  if s[1] == "ring" then
    rings(out, age, power == "super" and 2 or 1, hue[1], hue[2], hue[3], life, 6 + pw[1] * 2, 5)
  elseif s[1] == "streak" then
    streaks(out, age, math.max(2, pw[1] - 2), life, 6, hue[1], hue[2], hue[3], -0.8)
  elseif s.mode == "rise" then
    rise(out, age, s[1], pw[1] - 1, 4, 12, life - 4, 0)
  else
    burst(out, age, s[1], pw[1], pw[2], life, 0, 0, pw[3])
  end
  if pw[5] then
    for _, p in ipairs(out) do if p[1] == "shape" then p[5], p[7] = p[5] * 0.8, GREY end end
  end
  if crit then
    flash(out, age, 1, 1, 1, 6, 0.95)
    burst(out, age, "star", 1, 0, 12, 0, 0, 1.5)
  end
  return out
end

--- The engine sheet frame `age` ticks in (0-based), or nil when its animation is over.
function FinisherFx.sheetFrame(kind, age)
  local s = FinisherFx.recipe(kind).sheet
  if not s then return nil end
  local f = math.floor((tonumber(age) or 0) / s[5])
  if f >= s[4] then return nil end
  return f
end

-- ------------------------------------------------------------------ drawing
local sheets = {} -- name -> sheet (false: the engine has none)

local function sheetFor(spec)
  local hit = sheets[spec[1]]
  if hit ~= nil then return hit or nil end
  local s = EnginePatch.fieldEffectSheet and EnginePatch.fieldEffectSheet(spec[1], spec[2], spec[3], spec[4])
  sheets[spec[1]] = (type(s) == "table" and s.image and s.quads) and s or false
  return sheets[spec[1]] or nil
end

local function drawPart(g, p, cx, cy)
  local kind = p[1]
  if kind == "shape" then
    local w, h = PixelShapes.size(p[2])
    local sc = p[6] or 1
    PixelShapes.draw(g, p[2], math.floor(cx + p[3] - w * sc / 2), math.floor(cy + p[4] - h * sc / 2), p[5], p[7], sc)
  elseif kind == "line" then
    g.setColor(p[6], p[7], p[8], p[9])
    g.line(math.floor(cx + p[2]) + 0.5, math.floor(cy + p[3]) + 0.5, math.floor(cx + p[4]) + 0.5, math.floor(cy + p[5]) + 0.5)
  elseif kind == "ring" then
    g.setColor(p[3], p[4], p[5], p[6])
    g.ellipse("line", math.floor(cx) + 0.5, math.floor(cy + 4) + 0.5, p[2], p[2] * 0.6)
  elseif kind == "flash" then
    g.setColor(p[2], p[3], p[4], p[5] * 0.6)
    g.circle("fill", cx, cy, 10)
    g.setColor(p[2], p[3], p[4], p[5])
    g.circle("fill", cx, cy, 6)
  end
end

--- The effect as one field actor: the tile whose top-left is world (x, y), `age` ticks in.
function FinisherFx.actor(kind, age, x, y, elevation, id)
  if (tonumber(age) or 0) >= FinisherFx.TICKS then return nil end
  local recipe = FinisherFx.recipe(kind)
  return {
    kind = "ow_finisher_fx", elevation = elevation or 3, oamPriority = 1,
    sortY = y + 96, x = x + 8, y = y + 8,
    i = 90900 + (tonumber(id) or 0),
    draw = function(_, camX, camY)
      if not (love and love.graphics and love.graphics.rectangle) then return end
      local g = love.graphics
      local r, gg, b, a = g.getColor()
      local lw = g.getLineWidth and g.getLineWidth()
      if g.setLineWidth then g.setLineWidth(1) end
      local cx, cy = math.floor(x + 8 - camX), math.floor(y + 8 - camY)
      local spec = recipe.sheet
      local frame = spec and FinisherFx.sheetFrame(kind, age)
      local sheet = frame and sheetFor(spec)
      if sheet and sheet.quads[frame] then
        local tint = spec[7]
        g.setColor(tint and tint[1] or 1, tint and tint[2] or 1, tint and tint[3] or 1, 1)
        g.draw(sheet.image, sheet.quads[frame], cx - math.floor(spec[2] / 2), cy - math.floor(spec[3] / 2) + (spec[6] or 0))
      end
      for _, p in ipairs(FinisherFx.particles(kind, age)) do drawPart(g, p, cx, cy) end
      if lw and g.setLineWidth then g.setLineWidth(lw) end
      g.setColor(r, gg, b, a)
    end,
  }
end

--- An ordinary hit's type spark as one field actor (see FinisherFx.hitParticles).
function FinisherFx.hitActor(kind, age, x, y, power, crit, elevation, id)
  if (tonumber(age) or 0) >= FinisherFx.HIT_TICKS then return nil end
  return {
    kind = "ow_hit_spark", elevation = elevation or 3, oamPriority = 1,
    sortY = y + 95, x = x + 8, y = y + 8,
    i = 90950 + (tonumber(id) or 0),
    draw = function(_, camX, camY)
      if not (love and love.graphics and love.graphics.rectangle) then return end
      local g = love.graphics
      local r, gg, b, a = g.getColor()
      local lw = g.getLineWidth and g.getLineWidth()
      if g.setLineWidth then g.setLineWidth(1) end
      local cx, cy = math.floor(x + 8 - camX), math.floor(y + 8 - camY)
      for _, p in ipairs(FinisherFx.hitParticles(kind, age, power, crit)) do drawPart(g, p, cx, cy) end
      if lw and g.setLineWidth then g.setLineWidth(lw) end
      g.setColor(r, gg, b, a)
    end,
  }
end

return FinisherFx
