-- The herd battle: touching the leader of a wild group (lib/spawn_manager.lua _spawnGroup --
-- a pack, herd, swarm ... of one species) opens a battle with the whole group on screen:
-- "A wild ZIGZAGOON group appeared!", the others sliding in with the leader. Where they go
-- and what they do is by the group's KIND (WildHerd.kindOf): "land" walkers gather in a pack
-- beside the leader, hopping and barking to cheer it on; "float" (Magnemite, Gastly, Zubat,
-- Hoppip ...) hover behind it; "bird" flocks hop about aimlessly behind it; "swim" schools
-- and pods bob in the water behind it. The leader is the one fought (a plain wild single:
-- moves, catching, running as ever); CAUGHT, the others flee the battle screen at once
-- (WildHerd.flee); once the battle is over they scatter in the overworld (SpawnManager
-- _leaveGroup). lib/engine_patch.lua (EnginePatch.startWildHerd) does the drawing; this module
-- holds its pure parts (tested without the engine).
local WildHerd = {}

-- most Pokemon one herd battle shows, the leader included
WildHerd.MAX = 5

-- the intro's line (translated by the caller; %s = the leader's name, as the battle shows it)
WildHerd.TEXT = "A wild %s group appeared!"

-- the others' places: a loose pack in the open space LEFT of the leader, the middle left of
-- the screen (px from the leader's sprite centre, on its feet line) -- between the foe's health
-- box above and the player's Pokemon below. Not a line: a back row a little higher up (farther
-- off; it may reach further left, over the player's Pokemon) and a front row nearer the leader,
-- staggered, each at least ~22 px from the next (close, not hugging). One more each time the
-- group is bigger; the farthest back first in each list (drawn first). Mirrored (`FLIP`):
-- front pics face the player's way (left); over here they turn to face the battle and their
-- leader. Smaller (`SCALE`), a little darker (`SHADE`) and a little see-through (`ALPHA`): in
-- the background.
WildHerd.SLOTS = {
  { { -72, -8 } },
  { { -90, -16 }, { -62, -5 } },
  { { -104, -19 }, { -62, -18 }, { -84, -4 } },
  { { -76, -21 }, { -114, -20 }, { -96, -6 }, { -56, -5 } },
}
WildHerd.FLIP = true
WildHerd.SCALE = 0.75
WildHerd.SHADE = 0.85
WildHerd.ALPHA = 0.8

--- The group `leader` leads, as the herd battle's other Pokemon: a list of { species, level,
--- personality, id } (each member still there, never the leader itself), at most
--- WildHerd.MAX - 1. Empty unless `leader` leads a group of its own species (an escort's
--- companions are another species; nil `entities` -> empty). Pure.
function WildHerd.members(leader, entities)
  local out = {}
  local g = leader and leader.group
  if not (g and g.leader == leader.id and not g.escort and type(entities) == "table") then return out end
  for _, mid in ipairs(g.members or {}) do
    local m = mid ~= leader.id and entities[mid]
    if m and m.species == leader.species and #out < WildHerd.MAX - 1 then
      out[#out + 1] = { species = m.species, level = m.level, personality = m.personality, id = mid }
    end
  end
  return out
end

-- ...pulled in toward the leader (x, y factors) for a battle in WoobleView's 3D world (Battle
-- Scene: Overworld): its camera draws the player's Pokemon far bigger and the foes smaller, so
-- the open space left of the leader is narrower there
WildHerd.COMPACT = { x = 0.6, y = 0.8 }

--- Where the others stand for `n` of them (1 .. MAX - 1): a list of { dx, dy } (px from the
--- leader's sprite centre), WildHerd.SLOTS[n] -- or `kind`'s places (WildHerd.KINDS) --
--- (`compact`: drawn in by WildHerd.COMPACT), the farthest back first -- the order they are
--- drawn in. Pure.
function WildHerd.slots(n, compact, kind)
  local all = (WildHerd.KINDS[kind] or WildHerd.KINDS.land).slots
  n = math.max(0, math.min(#all, math.floor(tonumber(n) or 0)))
  local list = all[n] or {}
  if not compact then return list end
  local c, out = WildHerd.COMPACT, {}
  for i, p in ipairs(list) do out[i] = { math.floor(p[1] * c.x + 0.5), math.floor(p[2] * c.y + 0.5) } end
  return out
end

-- cheering their leader on, each to its own rhythm: every `every` ticks (its own length in that
-- range and its own start, by its place) a cheer of `hops` hops (one or two, turn about) of
-- `hopTicks` ticks, `hopGap` apart, `height` px up, a squash (`squash`) for `landTicks` as it
-- lands; and a bark: Growl's sound waves (the battle's NOISE_LINE sprite) bursting from its
-- mouth toward the leader `barkAt` ticks in, for `barkTicks`
WildHerd.CHEER = { every = { 80, 150 }, hopTicks = 12, hopGap = 3, height = 5, squash = 0.1, landTicks = 4,
                   barkAt = 4, barkTicks = 24 }

--- Where member `k` (1..) is in its cheer at tick `t` of the battle: dy (px, up < 0), sx, sy
--- (squash and stretch about its feet), and the bark's age (0..barkTicks-1) or nil. Pure.
function WildHerd.cheer(t, k)
  local c = WildHerd.CHEER
  k = math.max(1, math.floor(tonumber(k) or 1))
  local len = c.every[1] + (k * 37) % (c.every[2] - c.every[1] + 1)
  local at = math.max(0, math.floor(tonumber(t) or 0)) + (k * 53) % len
  local cycle, u = math.floor(at / len), at % len
  local hops = 1 + (cycle + k) % 2
  local dy, sx, sy = 0, 1, 1
  local step = c.hopTicks + c.hopGap
  local h, v = math.floor(u / step), u % step
  if h < hops then
    if v < c.hopTicks then
      dy = -c.height * math.sin(math.pi * v / c.hopTicks)
    elseif v - c.hopTicks < c.landTicks then
      sx, sy = 1 + c.squash, 1 - c.squash -- (landed)
    end
  end
  local bark = u - c.barkAt
  if bark < 0 or bark >= c.barkTicks then bark = nil end
  return dy, sx, sy, bark
end

--- The bark's sound waves at age `age` (0..barkTicks-1): a list of { dx, dy, angle, alpha }
--- from its mouth (px, facing right toward the leader), three lines fanning out as Growl's
--- do, moving away and fading. Pure.
function WildHerd.barkWaves(age)
  local c = WildHerd.CHEER
  local k = math.max(0, math.min(1, (tonumber(age) or 0) / c.barkTicks))
  local out = {}
  for i, ang in ipairs({ -0.5, 0, 0.5 }) do
    local d = 4 + 14 * k
    local a = (1 - k) * (i == 2 and 1 or 0.85)
    out[i] = { d * math.cos(ang), d * math.sin(ang), ang, a }
  end
  return out
end

-- ------- kinds: where they stand, how they move ---------------------------------------

-- Pokemon that float without being Flying types or in the levitating sprite pack (national
-- dex): Magnemite, Magneton, Carbink, Flittle
WildHerd.HOVER = { [81] = true, [82] = true, [703] = true, [955] = true }

local function natOf(dex)
  local n = tonumber(dex)
  if n then return n end
  return tonumber(tostring(dex or ""):match("^(%d+)"))
end

--- The kind of group `e` (the leader entity: dex, terrain, isFlyer, floater) leads:
--- "bird" (a real bird: `birds` = Config.FLYERS.realBirds, by national dex), "swim" (on the
--- water: a school, a pod, Surskit), "float" (a Flying type, a levitating sprite, HOVER),
--- else "land". Pure.
function WildHerd.kindOf(e, birds)
  if type(e) ~= "table" then return "land" end
  local nat = natOf(e.dex)
  if nat and type(birds) == "table" and birds[nat] then return "bird" end
  if e.terrain == "water" then return "swim" end
  if e.isFlyer or e.floater or (nat and WildHerd.HOVER[nat]) then return "float" end
  return "land"
end

-- each kind's places ({ dx, dy } from the leader's sprite centre on its feet line, by group
-- size, the farthest back -- highest -- first: the order they are drawn in), size, shade,
-- see-through, and whether they face right (mirrored; front pics face the player, left).
-- "land" stands in the open space LEFT of the leader (WildHerd.SLOTS); the rest stand BEHIND
-- it (drawn before it, so it covers them), higher up and smaller: in the background.
WildHerd.KINDS = {
  land = { slots = WildHerd.SLOTS, scale = WildHerd.SCALE, shade = WildHerd.SHADE, alpha = WildHerd.ALPHA,
           flip = WildHerd.FLIP },
  float = { scale = 0.6, shade = 0.8, alpha = 0.8, flip = false, slots = {
    { { -24, -18 } },
    { { 24, -22 }, { -26, -14 } },
    { { 2, -28 }, { -30, -14 }, { 32, -14 } },
    { { -14, -28 }, { 18, -27 }, { -36, -12 }, { 38, -10 } },
  } },
  bird = { scale = 0.6, shade = 0.8, alpha = 0.85, flip = false, slots = {
    { { -20, -10 } },
    { { 22, -12 }, { -24, -8 } },
    { { 0, -16 }, { 30, -9 }, { -30, -8 } },
    { { 14, -17 }, { -12, -16 }, { 30, -8 }, { -32, -7 } },
  } },
  swim = { scale = 0.6, shade = 0.75, alpha = 0.8, flip = false, slots = {
    { { -28, -8 } },
    { { 28, -10 }, { -30, -6 } },
    { { 0, -14 }, { 34, -7 }, { -34, -6 } },
    { { 16, -15 }, { -16, -14 }, { 40, -6 }, { -38, -5 } },
  } },
}

--- The look of `kind` (WildHerd.KINDS, unknown -> land). Pure.
function WildHerd.styleOf(kind)
  return WildHerd.KINDS[kind] or WildHerd.KINDS.land
end

-- hovering: up and down `amp` px over `every` ticks (its own length by its place), drifting
-- `drift` px side to side three times slower, tilting a little
WildHerd.HOVER_MOVE = { amp = 3, every = { 80, 120 }, drift = 3, tilt = 0.04 }
-- bobbing in the water: `amp` px over `every` ticks, rocking `tilt` rad
WildHerd.BOB = { amp = 1.5, every = { 60, 90 }, tilt = 0.05 }
-- a bird hopping about: pauses of `pause` ticks (turning round now and then: `turnChance` %),
-- then hops of `hopTicks` ticks, `hopGap` apart, `height` px up, at most `hopDist` px each, to
-- a spot within `range` px of its place (at least `minMove` from where it is)
WildHerd.WANDER = { pause = { 30, 100 }, turnChance = 35, hopTicks = 10, hopGap = 2, height = 3, hopDist = 7,
                    range = 12, minMove = 6 }

local function lcg(s)
  s.seed = (s.seed * 16807) % 2147483647
  return s.seed
end

local function roll(s, lo, hi) return lo + lcg(s) % (hi - lo + 1) end

--- One tick of a bird's hopping about (state `s`, set up on its first call; `k` = its place).
--- Leaves s.x (px from its place), s.dy, s.flip (facing right). Pure (its own generator).
function WildHerd.wanderStep(s, k)
  local c = WildHerd.WANDER
  if not s.seed then
    s.seed = 1 + (k * 7919) % 2147483646
    s.x, s.dy, s.flip, s.mode = 0, 0, (k % 2 == 0), "pause"
    s.timer = roll(s, 1, c.pause[2])
  end
  s.dy = 0
  if s.mode == "pause" then
    s.timer = s.timer - 1
    if s.timer == math.floor(c.pause[1] / 2) and roll(s, 1, 100) <= c.turnChance then s.flip = not s.flip end
    if s.timer <= 0 then
      local tx = s.x
      for _ = 1, 4 do
        tx = roll(s, -c.range, c.range)
        if math.abs(tx - s.x) >= c.minMove then break end
      end
      s.tx, s.mode, s.hop, s.from = tx, "hop", 0, s.x
      s.to = s.x + math.max(-c.hopDist, math.min(c.hopDist, tx - s.x))
      if tx ~= s.x then s.flip = tx > s.x end
    end
  else
    s.hop = s.hop + 1
    if s.hop <= c.hopTicks then
      local u = s.hop / c.hopTicks
      s.x = s.from + (s.to - s.from) * u
      s.dy = -c.height * math.sin(math.pi * u)
    elseif s.hop >= c.hopTicks + c.hopGap then
      s.x = s.to
      if s.x == s.tx then
        s.mode, s.timer = "pause", roll(s, c.pause[1], c.pause[2])
      else
        s.hop, s.from = 0, s.x
        s.to = s.x + math.max(-c.hopDist, math.min(c.hopDist, s.tx - s.x))
      end
    end
  end
end

--- Member `k`'s pose at cheer tick `t` (`s` = its own state table, kept by the caller),
--- filled into `out` (reused): dx, dy (px), sx, sy (squash about its feet), rot, flip (facing
--- right), bark (land's bark age, or nil). Pure.
function WildHerd.pose(kind, k, t, s, out)
  out = out or {}
  local style = WildHerd.styleOf(kind)
  out.dx, out.dy, out.sx, out.sy, out.rot, out.flip, out.bark = 0, 0, 1, 1, 0, style.flip, nil
  t = math.max(0, tonumber(t) or 0)
  if kind == "float" then
    local c = WildHerd.HOVER_MOVE
    local per = c.every[1] + (k * 29) % (c.every[2] - c.every[1] + 1)
    local a = 2 * math.pi * (t + k * 31) / per
    out.dy = -c.amp * (0.5 + 0.5 * math.sin(a))
    out.dx = c.drift * math.sin(a / 3)
    out.rot = c.tilt * math.sin(a / 3 + 1)
  elseif kind == "swim" then
    local c = WildHerd.BOB
    local per = c.every[1] + (k * 23) % (c.every[2] - c.every[1] + 1)
    local a = 2 * math.pi * (t + k * 17) / per
    out.dy = c.amp * math.sin(a)
    out.rot = c.tilt * math.sin(a + math.pi / 2)
    out.flip = k % 2 == 0
  elseif kind == "bird" then
    s = s or {}
    if s.t ~= t then
      s.t = t
      WildHerd.wanderStep(s, k)
    end
    out.dx, out.dy, out.flip = s.x or 0, s.dy or 0, s.flip and true or false
  else
    out.dy, out.sx, out.sy, out.bark = WildHerd.cheer(t, k)
  end
  return out
end

-- the leader caught: each runs off the battle screen `lag` ticks after the one before (plus
-- a little of its own): land runs off to the left (turned away), hopping; float drifts up
-- and away; a bird crouches, then flies up and off; swim dives. `ticks` = how long each takes.
WildHerd.FLEE = { lag = 6, ticks = { land = 60, float = 45, bird = 46, swim = 32 } }

--- Member `k` fleeing `age` ticks after the catch (`side` -1 / 1: the side of the leader it
--- stands on), laid over `out` (a WildHerd.pose): moves it, sets out.alpha (0..1) and
--- out.gone (off the screen: not drawn), no bark. Pure.
function WildHerd.flee(kind, k, age, side, out)
  out = out or { dx = 0, dy = 0, sx = 1, sy = 1, rot = 0 }
  out.bark, out.alpha, out.gone = nil, 1, false
  local c = WildHerd.FLEE
  local a = (tonumber(age) or 0) - ((k - 1) * c.lag + (k * 13) % 5)
  if a < 0 then return out end
  side = (side or 1) < 0 and -1 or 1
  local len = c.ticks[kind] or c.ticks.land
  if a >= len then out.gone = true return out end
  if kind == "float" then
    out.dx, out.dy = out.dx + side * 0.8 * a, out.dy - 1.6 * a
    out.alpha = 1 - a / len
  elseif kind == "bird" then
    if a < 6 then
      out.sx, out.sy = 1.1, 0.9
    else
      local f = a - 6
      out.dx, out.dy, out.flip = out.dx + side * 1.8 * f, out.dy - 2.6 * f, side > 0
      out.alpha = 1 - f / (len - 6)
    end
  elseif kind == "swim" then
    out.dy = out.dy + 0.5 * a
    out.alpha = 1 - a / len
  else
    out.dx, out.flip, out.rot = out.dx - 3.2 * a, false, 0
    out.dy, out.sx, out.sy = -3 * math.abs(math.sin(math.pi * a / 8)), 1, 1
    out.alpha = a > len - 12 and (len - a) / 12 or 1
  end
  return out
end

--- Swaps the wild intro's "Wild X appeared!" for `text` in the intro's steps (IntroSeq._steps,
--- in place): the message step whose text is `old`. Returns true when one was found.
function WildHerd.patchIntroText(steps, old, text)
  if type(old) ~= "string" or type(text) ~= "string" then return false end
  for _, step in ipairs(steps or {}) do
    local d = step.data
    if step.kind == "msg" and type(d) == "table" and d.text == old then
      d.text = text
      return true
    end
  end
  return false
end

return WildHerd
