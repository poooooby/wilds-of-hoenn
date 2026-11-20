-- The herd battle: touching the leader of a wild group (lib/spawn_manager.lua _spawnGroup --
-- a pack, herd, swarm ... of one species) opens a battle with the whole group on screen:
-- "A wild ZIGZAGOON group appeared!", the others sliding in with the leader and standing
-- behind it, watching. The leader is the one fought (a plain wild single: moves, catching,
-- running as ever); once it is over the others scatter in the overworld (SpawnManager
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
--- leader's sprite centre), WildHerd.SLOTS[n] (`compact`: drawn in by WildHerd.COMPACT), the
--- farthest back first -- the order they are drawn in. Pure.
function WildHerd.slots(n, compact)
  n = math.max(0, math.min(#WildHerd.SLOTS, math.floor(tonumber(n) or 0)))
  local list = WildHerd.SLOTS[n] or {}
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
