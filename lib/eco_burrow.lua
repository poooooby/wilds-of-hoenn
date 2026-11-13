-- Wild Ecology: burrowers (lib/eco.lua activity "burrow"). A Pokemon whose profile says
-- `burrower` (Diglett, Dugtrio, Sandshrew, Trapinch, Nincada, Onix, Larvitar ...: lib/
-- eco_species.lua) now and then sinks into the ground in a puff of dust, stays under a while
-- and pops up a few tiles away. Startled (Wild Reacts, lib/wild_reactions.lua begin), it
-- ducks underground instead of running and comes up away from the player.
--
-- Under the ground it is not met (`untouchable`) and already holds the cell it will come
-- up on; it never comes up under the player (it waits). Its group goes under with it:
-- lib/spawn_manager.lua _tickRider mirrors the leader's depth a few ticks late (sinkAt).
local V = ...
local Config = V.require("config")
local EnginePatch = V.require("engine_patch")
local Eco = V.require("eco")
local Behavior = V.require("behavior")
local EcoWater = V.require("eco_water")

local EcoBurrow = {}

local function between(rng, r) return rng(r[1], r[2]) end
local function ease(p)
  p = math.max(0, math.min(1, p))
  return p * p * (3 - 2 * p)
end

--- How far under burrow `s` is `t` ticks in: 0 on top .. 1 gone. Pure (riders read it a few
--- ticks late, so a group goes down and comes up one after another).
function EcoBurrow.sinkAt(s, t)
  local n = s.sinkTicks or 1
  if t <= 0 then return 0 end
  if t <= n then return ease(t / n) end
  if not s.riseAt or t < s.riseAt then return 1 end
  return 1 - ease((t - s.riseAt) / n)
end

local DUST_LIFE = 22

-- the k-th entry of buffer `out`, reused (lib/eco_water.lua draws parts from one scratch list)
local function slot(out, k)
  local p = out[k]
  if not p then p = {} out[k] = p end
  return p
end

--- Dust kicked up by a burrower `age` ticks after the puff: { {dx, dy, alpha, size}, ... }
--- from the point at its feet, and how many. Pure (tested). `out` (optional): a list to
--- fill instead of a new one (entries reused; only the first `n` count).
function EcoBurrow.dust(age, seed, out)
  out = out or {}
  local n = 0
  if age < 0 or age >= DUST_LIFE then return out, 0 end
  seed = math.floor(tonumber(seed) or 0)
  for i = 1, 9 do
    local side = ((seed * 7 + i * 5) % 13) - 6 -- -6 .. 6: thrown out to both sides
    local vx = side * 0.22
    local vy = -(0.7 + ((seed * 3 + i * 11) % 7) * 0.16)
    local dy = vy * age + 0.06 * age * age
    if dy <= 1 then
      n = n + 1
      local p = slot(out, n)
      p[1], p[2], p[3], p[4] = math.floor(vx * age + 0.5), math.floor(dy + 0.5), (1 - age / DUST_LIFE) * 0.95,
        i % 3 == 0 and 1 or 2
    end
  end
  return out, n
end

-- the mound of dug-up earth at the hole: rows of an oval, { half width, dy }
local MOUND = { { 3, -2 }, { 5, -1 }, { 6, 0 }, { 5, 1 } }
local MOUND_LIFE = 70

--- The mound of earth where a burrower goes down / comes up, `age` ticks in: the oval's
--- pixels { {dx, dy, alpha, 1}, ... } about the hole, fading in, then out, and how many.
--- Pure. `out` (optional): a list to fill (as EcoBurrow.dust).
function EcoBurrow.mound(age, _seed, out)
  out = out or {}
  local n = 0
  if age < 0 or age >= MOUND_LIFE then return out, 0 end
  local a = math.min(1, age / 6) * math.min(1, (MOUND_LIFE - age) / 30)
  for _, row in ipairs(MOUND) do
    for dx = -row[1], row[1] do
      n = n + 1
      local p = slot(out, n)
      p[1], p[2], p[3], p[4] = dx, row[2], a, 1
    end
  end
  return out, n
end

local DUST = { 0.87, 0.77, 0.56 }
local EARTH = { 0.47, 0.35, 0.21 }

local function addDust(e, t)
  EcoWater.addFx(e, { kind = "dust", life = DUST_LIFE, parts = EcoBurrow.dust, color = DUST,
    x = e.px + 8, y = e.py + 14, sortY = e.py + 2, age = 0, seed = (e.id or 1) * 5 + t })
end

local function addMound(e)
  EcoWater.addFx(e, { kind = "mound", life = MOUND_LIFE, parts = EcoBurrow.mound, color = EARTH,
    x = e.px + 8, y = e.py + 14, sortY = e.py + 1.5, age = 0, seed = 0 })
end

local function playerOn(x, y)
  local p = EnginePatch.playerCell and EnginePatch.playerCell()
  return p and ((p.x == x and p.y == y) or (p.moving and p.targetX == x and p.targetY == y)) or false
end

--- Where `e` comes up: a free cell of its own terrain `range` tiles off (Chebyshev), one the
--- player can reach, not a doorway, not by the player. With `away` = {x, y}: as far from that
--- point as it can. Returns x, y or nil.
function EcoBurrow.spot(e, sm, ctx, range, away, rng)
  rng = rng or math.random
  local p = ctx and ctx.player
  local lo, hi = range[1], range[2]
  local list, best = {}, -1
  for dy = -hi, hi do
    for dx = -hi, hi do
      local d = math.max(math.abs(dx), math.abs(dy))
      local x, y = e.cellX + dx, e.cellY + dy
      if d >= lo and d <= hi and EnginePatch.terrainAt(x, y) == e.terrain
        and not (sm and sm.source and sm.source.canStay and not sm.source:canStay(x, y, e.terrain))
        and not (sm and sm._cellFree and not sm:_cellFree(x, y))
        and not (EnginePatch.isWarpCell and EnginePatch.isWarpCell(x, y))
        and not (p and math.max(math.abs(p.x - x), math.abs(p.y - y)) <= 1) then
        local score = away and (math.abs(away.x - x) + math.abs(away.y - y)) or 0
        if score > best then list, best = {}, score end
        if score == best then list[#list + 1] = { x, y } end
      end
    end
  end
  if #list == 0 then return nil end
  local c = list[rng(1, #list)]
  return c[1], c[2]
end

--- The state a burrow starts with (`away`: ducking away from the player at that point), or
--- nil when there is nowhere to come up.
function EcoBurrow.state(e, sm, ctx, away, rng)
  rng = rng or math.random
  local cfg = Config.ECO.burrow
  local x, y = EcoBurrow.spot(e, sm, ctx, away and cfg.fleeHop or cfg.hop, away, rng)
  if not x then return nil end
  return { burrowing = true, sinkTicks = cfg.sinkTicks, under = between(rng, cfg.under),
           rx = x, ry = y, waits = 0 }
end

Eco.register("burrow", {
  step = function(e, ctx, sm, s)
    local cfg = Config.ECO.burrow
    local r = e.renderer
    -- a step it was on is finished first (startled mid-step)
    if s.t == 1 and e.moving then
      Behavior._advanceMove(e)
      s.t = 0
      return false
    end
    local n = s.sinkTicks
    local digging = s.t <= n or (s.riseAt and s.t - s.riseAt <= n)
    if digging and s.t % cfg.dustEvery == 1 then addDust(e, s.t) end
    if s.t == 1 or (s.riseAt and s.t == s.riseAt + 1) then addMound(e) end -- the hole it digs / comes out of
    if s.t == n then
      -- gone: under the ground it makes for the cell it comes up on
      s.untouchable = true
      e.cellX, e.cellY = s.rx, s.ry
      e.px, e.py = s.rx * 16, s.ry * 16
      e.facing = ({ "down", "left", "right", "up" })[(ctx.rng or math.random)(1, 4)]
    end
    if s.t > n and not s.riseAt and s.t >= n + s.under then
      if playerOn(e.cellX, e.cellY) or (sm and sm.occupiedBy and sm:occupiedBy(e.cellX, e.cellY, e)) then
        s.under = s.under + 30 -- someone is standing there: it waits ...
        s.waits = s.waits + 1
        if s.waits >= 4 then
          -- ... and at length tries somewhere else
          local x, y = EcoBurrow.spot(e, sm, ctx, cfg.hop, nil, ctx.rng)
          if x then e.cellX, e.cellY, e.px, e.py = x, y, x * 16, y * 16 end
          s.waits = 0
        end
      else
        s.riseAt, s.untouchable = s.t, nil
      end
    end
    if r then
      local act = r.act
      if not (act and act.ecoBurrow) then act = { ecoBurrow = true } r.act = act end
      act.sink = math.min(1, EcoBurrow.sinkAt(s, s.t))
      if r.advance then r:advance(false) end
    end
    if s.riseAt and s.t >= s.riseAt + n then
      if r and r.act and r.act.ecoBurrow then r.act = nil end
      return true
    end
    return false
  end,
  abort = function(e, _sm, s)
    local r = e.renderer
    if r and r.act and r.act.ecoBurrow then r.act = nil end
    if s and s.rx and s.t < (s.sinkTicks or 0) then e.px, e.py = e.cellX * 16, e.cellY * 16 end
  end,
})

--- May `e` go under right now?
function EcoBurrow.can(e)
  local prof = e.profile
  return prof and prof.burrower and e.terrain == "land" and not e.isFlyer and not e.roamer
    and not e.lured and not e.engaged and not e.fx and not e.rider and not e.runAway
    and not (e.group and e.group.social == "swarm") or false
end

--- Startled: `e` ducks underground away from the player at (px, py) (Wild Reacts' flee for a
--- burrower). True when it went under.
function EcoBurrow.duck(e, sm, ctx, px, py)
  if e.eco or not EcoBurrow.can(e) then return false end
  local st = EcoBurrow.state(e, sm, ctx, { x = px, y = py }, ctx and ctx.rng)
  if not st then return false end
  e.react = nil
  return Eco.start(e, "burrow", st)
end

function EcoBurrow.choose(e, ctx, sm)
  if not EcoBurrow.can(e) or e.react or e.moving then return nil end
  local cfg = Config.ECO.burrow
  local p = ctx.player
  if p and math.max(math.abs(p.x - e.cellX), math.abs(p.y - e.cellY)) <= cfg.clearRadius then return nil end
  if not EcoWater._due(e, "burrow", cfg.every, ctx.rng or math.random, ctx.now or 0) then return nil end
  local st = EcoBurrow.state(e, sm, ctx, nil, ctx.rng)
  if not st then return nil end
  return "burrow", st
end
Eco.addChooser(EcoBurrow.choose)

return EcoBurrow
