-- Wild Pokemon reacting to a player who runs or bikes close by (the Wild Reacts option).
-- Walking past disturbs nobody.
--
-- Each one within reach (Config.REACT.radius steps, more on a bike) is judged against the
-- player's lead Pokemon by level x base-stat total:
--   weak    (ratio < weakRatio)   "!", a startled hop, then it runs off a few tiles at
--                                 running pace; a small bird takes off instead (the sky's
--                                 own take-off flight, lib/sky_flyers.lua);
--   neutral                       nothing: an even match carries on as normal;
--   strong  (ratio > strongRatio) turns, an anger mark, then CHASES the player a touch
--                                 faster than they can run. Reaching them (on or next to
--                                 their tile, while they stand) starts the normal wild
--                                 battle. A land chaser follows the player OFF its own
--                                 grass (chase.anyGround: any open ground the engine's
--                                 collision allows -- never water or a doorway). Every
--                                 chase rolls its own leash: it gives up past that many
--                                 tiles, after leash x secondsPerTile, or with no way
--                                 through for a moment, shows "?" and walks back: home
--                                 to its own terrain first (no way back -> it leaves
--                                 with the fade, ctx.strand), then a few steps more.
-- Whether it reacts at all is one roll as the player comes in range (chance()): a near
-- match only sometimes (Config.REACT.minChance), a lopsided one always (past weakSure /
-- strongSure); a miss leaves it be for missCooldown ticks.
-- A Pokemon then rests (cooldown) before it can react again. Nothing reacts while the
-- field is busy (a cutscene, a trainer, a message), in a battle, or in the Safari Zone,
-- and Sweet Scent's lured Pokemon, ones in a Battler skirmish, arriving / leaving ones and
-- the roaming legendary are left alone. Movement goes through Behavior.tryStep: the same
-- legality as wandering (its own encounter terrain, the engine's collision), widened to
-- open ground for a chase and the walk home (`anyGround`).
--
-- State lives on the entity as `e.react`; lib/spawn_manager.lua calls scan() once a tick
-- and tick(e) instead of Behavior.tick while `e.react` is set.
local V = ...
local Config = V.require("config")
local EnginePatch = V.require("engine_patch")
local Behavior = V.require("behavior")
local CellPath = V.require("cell_path")

local WildReactions = {}

local function cheb(ax, ay, bx, by) return math.max(math.abs(ax - bx), math.abs(ay - by)) end
local function manhattan(ax, ay, bx, by) return math.abs(ax - bx) + math.abs(ay - by) end

local function faceToward(x, y, tx, ty)
  local dx, dy = tx - x, ty - y
  if math.abs(dx) > math.abs(dy) then return dx < 0 and "left" or "right" end
  if dy == 0 then return nil end
  return dy < 0 and "up" or "down"
end
WildReactions.faceToward = faceToward

--- "weak" | "neutral" | "strong" for a wild Pokemon of `level` / base-stat total `bst`
--- against the lead's. A missing total counts as equal (level alone decides); no lead
--- -> "neutral". Pure (tested).
function WildReactions.classify(level, bst, leadLevel, leadBst, cfg)
  cfg = cfg or Config.REACT
  level, leadLevel = tonumber(level), tonumber(leadLevel)
  if not (level and leadLevel) or leadLevel <= 0 then return "neutral" end
  local a, b = tonumber(bst), tonumber(leadBst)
  if not (a and b and a > 0 and b > 0) then a, b = 1, 1 end
  local ratio = (level * a) / (leadLevel * b)
  if ratio < cfg.weakRatio then return "weak", ratio end
  if ratio > cfg.strongRatio then return "strong", ratio end
  return "neutral", ratio
end

--- The % chance a Pokemon of class `cls` at `ratio` reacts: `minChance` just past its
--- threshold, rising evenly to 100 at `weakSure` / `strongSure`. Neutral -> 0. Pure (tested).
function WildReactions.chance(cls, ratio, cfg)
  cfg = cfg or Config.REACT
  ratio = tonumber(ratio)
  if not ratio or cls == "neutral" then return 0 end
  local min = cfg.minChance or 100
  local t
  if cls == "weak" then
    t = (cfg.weakRatio - ratio) / math.max(1e-6, cfg.weakRatio - (cfg.weakSure or 0))
  else
    t = (ratio - cfg.strongRatio) / math.max(1e-6, (cfg.strongSure or cfg.strongRatio) - cfg.strongRatio)
  end
  t = math.max(0, math.min(1, t))
  local max = cfg.maxChance or 100
  return min + (max - min) * t
end

local ORDER = { "up", "down", "left", "right" }

local function sign(v) return v > 0 and 1 or v < 0 and -1 or 0 end

--- The direction from (x, y) that best gets away from (px, py) among those `ok(dir)`
--- allows: the largest new distance, ties broken toward moving straight away. nil when
--- every way is shut. Pure (tested).
function WildReactions.fleeDir(x, y, px, py, ok)
  local best, bestScore
  local ax, ay = sign(x - px), sign(y - py) -- straight away from the player
  for _, dir in ipairs(ORDER) do
    local d = Behavior.DELTA[dir]
    local nx, ny = x + d[1], y + d[2]
    local gain = manhattan(nx, ny, px, py) - manhattan(x, y, px, py)
    local score = manhattan(nx, ny, px, py) + gain * 2 + 0.5 * (d[1] * ax + d[2] * ay)
    if (not ok or ok(dir)) and gain >= 0 and (not bestScore or score > bestScore) then
      best, bestScore = dir, score
    end
  end
  return best
end

-- ------- the per-entity reaction -------------------------------------------------

local function rngRange(rng, r) return rng(r[1], r[2]) end

--- Can `e` react now? (Not lured, engaged, arriving / leaving, the roamer, on cooldown.)
function WildReactions.eligible(e, now)
  return e.state == Config.STATE.AVAILABLE and not e.react and not e.lured and not e.engaged
    and not e.fx and not e.roamer and not e.runAway and not e.defeated and not e.eco and not e.rider
    and (e.reactUntil or 0) <= (now or 0)
end

--- Starts `e` reacting to ANOTHER wild Pokemon `target` (lib/eco.lua): "hunt" = the anger
--- mark, then a chase that ends in `ctx.onCatch(e, target)` once beside it; "flee" = the "!"
--- and a run of `steps` away from it. True when it started.
--- (`steps`: a flight's length, or a hunt's leash in tiles.)
function WildReactions.startAt(e, target, kind, ctx, steps)
  if not (target and WildReactions.eligible(e, ctx and ctx.now)) then return false end
  local cfg = Config.REACT
  local r = { t = 0, emoteAge = 0, target = target, kind = kind == "hunt" and "strong" or "weak" }
  e.facing = faceToward(e.cellX, e.cellY, target.cellX, target.cellY) or e.facing
  if kind == "hunt" then
    r.mode, r.next, r.emote, r.n, r.huntLeash = "alert", "chase", "anger", cfg.angerTicks, steps
  else
    r.mode, r.next, r.emote, r.n, r.hop, r.fleeSteps = "alert", "flee", "!", cfg.alertTicks, true, steps
  end
  e.react = r
  return true
end

--- How far a Pokemon of temper `temper` notices a player moving by `how` ("walk" | "run" |
--- "bike"): (reach, aggroAt) in tiles, or nil when it pays no attention. "calm" / nil = the
--- old rules (running or biking only; a stronger one angry only right beside them). Pure.
function WildReactions.reach(temper, how, cfg)
  cfg = cfg or Config.REACT
  if temper == "placid" then return nil end
  local t = cfg.temper and cfg.temper[temper]
  if t and t[how] then return t[how], t[how] end
  if how == "walk" then return nil end
  if how == "bike" then return cfg.bikeRadius, cfg.bikeAggroRadius end
  return cfg.radius, cfg.aggroRadius
end

--- What a Pokemon of `temper` does about the player, by its strength class / ratio:
--- ("flee" | "chase", % chance), or nil. "calm" / nil = the old rules: the weaker flee, the
--- stronger chase, an even match shrugs. Pure (tested).
function WildReactions.decide(temper, cls, ratio, cfg)
  cfg = cfg or Config.REACT
  local t = cfg.temper and cfg.temper[temper]
  if temper == "placid" then return nil end
  if temper == "skittish" and t then
    -- it runs from anyone; from a weaker lead less often
    if cls == "weak" then return "flee", math.max(WildReactions.chance(cls, ratio, cfg), t.chance) end
    return "flee", cls == "strong" and t.chance / 2 or t.chance
  end
  if (temper == "territorial" or temper == "aggressive") and t then
    -- it stands its ground and charges -- unless the lead is far too strong for it
    if cls == "weak" and (tonumber(ratio) or 1) < t.fleeBelow then return "flee", WildReactions.chance(cls, ratio, cfg) end
    if cls == "strong" then return "chase", math.max(WildReactions.chance(cls, ratio, cfg), t.chance) end
    return "chase", t.chance
  end
  if cls == "neutral" then return nil end
  return cls == "weak" and "flee" or "chase", WildReactions.chance(cls, ratio, cfg)
end

--- Starts `e` reacting to the player at (px, py), `dist` tiles away: picks the reaction
--- from its temper (e.profile) and strength. A stronger one with no temper of note only gets
--- angry much closer (`aggroAt` tiles). Returns the class, or nil when it does not react.
--- `ctx` = { now, rng, lead = {level, bst}, bst(species), canFly(e) }.
function WildReactions.start(e, px, py, ctx, dist, aggroAt)
  local cfg, rng = Config.REACT, ctx.rng or math.random
  local cls, ratio = WildReactions.classify(e.level, ctx.bst and ctx.bst(e.species), ctx.lead and ctx.lead.level,
    ctx.lead and ctx.lead.bst, cfg)
  local what, pct = WildReactions.decide(e.profile and e.profile.temper, cls, ratio, cfg)
  if not what then return nil end -- an even match (or a placid one) is not bothered
  if what == "chase" and dist and dist > (aggroAt or cfg.aggroRadius) then return nil end -- not close enough yet
  -- the closer the match, the likelier it shrugs the player off; one roll, then a rest
  if rng(1, 100) > pct then
    e.reactUntil = (ctx.now or 0) + (cfg.missCooldown or cfg.cooldown)
    return nil
  end
  return WildReactions.begin(e, what, px, py, ctx)
end

--- Starts reaction `what` ("flee" | "chase") to the player at (px, py) at once, with no
--- roll (a sleeper woken by them: lib/eco_sleep.lua). A burrower ducks underground instead
--- of running (ctx.burrow). Returns the class ("weak" | "strong").
function WildReactions.begin(e, what, px, py, ctx)
  local cfg = Config.REACT
  local cls = what == "flee" and "weak" or "strong"
  if cls == "weak" and ctx.burrow and e.profile and e.profile.burrower and ctx.burrow(e, px, py) then
    e.reactUntil = (ctx.now or 0) + cfg.cooldown
    return cls
  end
  local r = { t = 0, emoteAge = 0 }
  if cls == "weak" then
    e.facing = faceToward(e.cellX, e.cellY, px, py) or e.facing
    local bird = e.terrain == "land" and ctx.canFly and ctx.canFly(e)
    r.mode, r.next, r.emote, r.n, r.hop = "alert", bird and "takeoff" or "flee", "!", cfg.alertTicks, true
  else
    -- a stronger one takes a moment: it stops, turns to the player, THEN the anger mark
    r.mode, r.n = "turn", cfg.turnTicks
  end
  r.kind = cls
  e.react = r
  return cls
end

-- done reacting: back to wandering, resting `cooldown` ticks before reacting again
local function finish(e, now, cooldown, rng)
  e.react = nil
  e.reactUntil = (now or 0) + (cooldown or Config.REACT.cooldown)
  e.ticksUntilAction = rng and rng(30, 90) or 60
  if e.renderer then
    if e.renderer.isPmd then e.renderer.walkMul = 1 end
    if e.renderer.act and e.renderer.act.reactHop then e.renderer.act = nil end
  end
end
WildReactions.finish = finish

-- Does this chase leave the spawn area? A land Pokemon's does (chase.anyGround); a
-- swimmer stays in its water.
local function anyGround(e)
  return Config.REACT.chase.anyGround ~= false and e.terrain ~= "water"
end
WildReactions.anyGround = anyGround

-- may a chase path cross (x, y)? Its own terrain, or (anyGround) any open dry ground
local function pathCell(e, x, y, wide)
  if EnginePatch.terrainAt(x, y) == e.terrain then return true end
  if not wide then return false end
  if not (EnginePatch.cellFree and EnginePatch.cellFree(x, y)) then return false end
  return Behavior._openGround(x, y)
end

-- the next step toward the player's (resting) cell along a path over this Pokemon's own
-- terrain -- or any open ground, for a land chaser -- past other wild Pokemon; nil when
-- there is no way
local function chaseDir(e, gx, gy, ctx, leash)
  local wide = anyGround(e)
  local res = CellPath.search(e.cellX, e.cellY, {
    free = function(x, y)
      if x == gx and y == gy then return true end
      if not pathCell(e, x, y, wide) then return false end
      return not (ctx.occupied and ctx.occupied(x, y, e))
    end,
    maxDepth = leash + 4,
  })
  local path = CellPath.pathTo(res, gx, gy)
  local first = path and path[1]
  if not first then return nil end
  return CellPath.facingOf(first[1] - e.cellX, first[2] - e.cellY)
end

local function giveUp(e, ctx)
  local cfg, rng = Config.REACT, ctx.rng or math.random
  local r = e.react
  e.react = { mode = "return", t = 0, emote = "?", emoteAge = 0, kind = r.kind,
              home = r.home or e.chaseHome, steps = rngRange(rng, cfg.chase.returnSteps), blocked = 0 }
end

--- A chaser left standing off its own terrain with no reaction running (its chase was
--- cut short: a busy field, a contact that could not start): walk it home, quietly (no
--- "?"). lib/spawn_manager.lua calls this.
function WildReactions.sendHome(e)
  e.react = { mode = "return", t = 20, emoteAge = 0, kind = "strong",
              home = e.chaseHome, steps = 0, blocked = 0 }
end

-- what a reaction is about: the player (ctx.player), or another wild Pokemon (`r.target`,
-- lib/eco.lua) read into the same shape -- nil once that one is gone
local function goalOf(r, ctx)
  local o = r.target
  if not o then return ctx.player end
  if o.state ~= Config.STATE.AVAILABLE or o.defeated or (o.fx and o.fx.under) then return nil end
  local g = r.goal or {}
  r.goal = g
  g.x, g.y, g.moving, g.targetX, g.targetY = o.cellX, o.cellY, o.moving, o.targetX, o.targetY
  return g
end
WildReactions._goalOf = goalOf

--- One tick of `e`'s reaction. `ctx` = { now, rng, game, player = playerCell(),
--- occupied(x, y, self), onContact(e), onCatch(e, target), takeoff(e) }.
--- Ticks a bound away takes when `e` can make one heading `dir` (PMD LeapForth art, on
--- land, its sheet showing that facing -- most are one back-view row: "up" only), else nil.
function WildReactions.leapTicks(e, dir)
  local r = e.renderer
  local entry = e.terrain == "land" and r and r.isPmd and r.info and r.info.leapforth
  if type(entry) ~= "table" or (entry.facing and entry.facing ~= dir) then return nil end
  local n = 0
  for _, d in ipairs(entry.durations or {}) do n = n + d end
  return n > 0 and n or nil
end

function WildReactions.tick(e, ctx)
  local cfg, rng = Config.REACT, ctx.rng or math.random
  local r = e.react
  if not r then return end
  r.t = r.t + 1
  r.emoteAge = (r.emoteAge or 0) + 1
  if r.emoteAge > cfg.emoteTicks then r.emote = nil end
  local p = goalOf(r, ctx)
  -- the Pokemon it was about is gone (caught, fainted, dived): it calms down
  if r.target and not p and r.mode ~= "return" then
    if e.moving then Behavior._advanceMove(e) return end
    return finish(e, ctx.now, cfg.cooldown, rng)
  end
  -- a step in progress finishes first
  if e.moving then
    Behavior._advanceMove(e)
    return
  end

  if r.mode == "turn" then
    -- halfway through the pause it turns to face the player; at the end it gets angry
    if p and r.t >= math.floor(r.n / 2) then e.facing = faceToward(e.cellX, e.cellY, p.x, p.y) or e.facing end
    if r.t >= r.n then
      r.mode, r.next, r.emote, r.emoteAge, r.n, r.t = "alert", "chase", "anger", 0, cfg.angerTicks, 0
    end
    return
  end

  if r.mode == "alert" then
    if p then e.facing = faceToward(e.cellX, e.cellY, p.x, p.y) or e.facing end
    if r.hop and e.renderer then
      local k = r.t / cfg.hopTicks
      if k < 1 then
        e.renderer.act = { dy = -math.sin(math.pi * k) * cfg.hopPx, reactHop = true }
      elseif e.renderer.act and e.renderer.act.reactHop then
        e.renderer.act = nil
      end
    end
    if r.t < r.n then return end
    if r.next == "takeoff" then
      finish(e, ctx.now, cfg.cooldown, rng)
      if ctx.takeoff then ctx.takeoff(e) end
    elseif r.next == "flee" then
      r.mode, r.steps, r.blocked = "flee", r.fleeSteps or rngRange(rng, cfg.flee.steps), 0
    elseif r.next == "chase" then
      local leash = r.huntLeash or rngRange(rng, cfg.chase.leash)
      r.mode, r.leash, r.limit = "chase", leash, math.floor(leash * cfg.chase.secondsPerTile * 60)
      r.home, r.noPath, r.t = { x = e.cellX, y = e.cellY }, 0, 0
      -- where to walk back to if it ends up off its grass (kept past the reaction)
      e.chaseHome = r.home
    else
      finish(e, ctx.now, cfg.cooldown, rng)
    end
    return
  end

  if r.mode == "flee" then
    if r.leap then
      -- mid-bound: the art leaps off (LeapForth climbs about a tile); it lands a tile on
      r.leap.t = r.leap.t + 1
      if r.leap.t < r.leap.n then return end
      local dir = r.leap.dir
      r.leap, r.anim = nil, nil
      if Behavior.tryStep(e, ctx.game, dir, 1) then r.steps = r.steps - 1 end
      return
    end
    if r.steps <= 0 or not p then
      finish(e, ctx.now, cfg.cooldown, rng)
      -- at the end of its run some of them disappear into the grass / the cave's dark
      if r.steps <= 0 and ctx.fleeVanish and rng(1, 100) <= cfg.flee.vanishChance then ctx.fleeVanish(e) end
      return
    end
    local dir = WildReactions.fleeDir(e.cellX, e.cellY, p.x, p.y, function(d)
      local dd = Behavior.DELTA[d]
      return not (ctx.occupied and ctx.occupied(e.cellX + dd[1], e.cellY + dd[2], e))
    end)
    -- its first step away, if the art can: a bound instead of a step
    local leap = dir and not r.leapt and WildReactions.leapTicks(e, dir)
    if leap then
      r.leapt = true
      local dd = Behavior.DELTA[dir]
      if Behavior._canStep(e, ctx.game, e.cellX + dd[1], e.cellY + dd[2]) then
        r.leap, r.anim, e.facing = { t = 0, n = leap, dir = dir }, "leapforth", dir
        return
      end
    end
    if dir and Behavior.tryStep(e, ctx.game, dir, cfg.flee.frames) then
      r.steps = r.steps - 1
    else
      r.blocked = r.blocked + 1
      if r.blocked > 20 then finish(e, ctx.now, cfg.cooldown, rng) end
    end
    return
  end

  if r.mode == "chase" then
    if not p then return giveUp(e, ctx) end
    local gx, gy = p.x, p.y
    if p.moving and p.targetX then gx, gy = p.targetX, p.targetY end
    if cheb(e.cellX, e.cellY, gx, gy) > r.leash or r.t > r.limit then return giveUp(e, ctx) end
    if r.target and (manhattan(e.cellX, e.cellY, p.x, p.y) <= 1 or manhattan(e.cellX, e.cellY, gx, gy) <= 1) then
      -- caught up with the Pokemon it hunted (lib/eco.lua takes it from here)
      local prey = r.target
      e.facing = faceToward(e.cellX, e.cellY, p.x, p.y) or e.facing
      finish(e, ctx.now, cfg.chaseCooldown, rng)
      if ctx.onCatch then ctx.onCatch(e, prey) end
      return
    end
    if manhattan(e.cellX, e.cellY, p.x, p.y) <= 1 and not p.moving then
      -- caught up with a standing player: the battle
      e.facing = faceToward(e.cellX, e.cellY, p.x, p.y) or e.facing
      finish(e, ctx.now, cfg.chaseCooldown, rng)
      -- still charging (its Attack animation) until the battle opens
      e.charging = cfg.chase.chargeTicks
      if ctx.onContact then ctx.onContact(e) end
      return
    end
    if manhattan(e.cellX, e.cellY, gx, gy) <= 1 then
      -- right behind a player still moving: keep facing them, wait for them to stop
      e.facing = faceToward(e.cellX, e.cellY, gx, gy) or e.facing
      return
    end
    local dir = chaseDir(e, gx, gy, ctx, r.leash)
    if dir and Behavior.tryStep(e, ctx.game, dir, cfg.chase.frames, { anyGround = anyGround(e) }) then
      r.noPath = 0
    else
      r.noPath = r.noPath + 1
      if r.noPath > cfg.chase.noPathTicks then giveUp(e, ctx) end
    end
    return
  end

  if r.mode == "return" then
    -- back toward where it set off from, at walking pace: all the way onto its own
    -- terrain first, then up to `steps` more
    if r.t < 20 then return end -- the "?" first
    local off = Behavior.offTerrain(e)
    local home = r.home
    local atHome = home and e.cellX == home.x and e.cellY == home.y
    if not off and (r.steps <= 0 or not home or atHome) then
      e.chaseHome = nil
      return finish(e, ctx.now, cfg.chaseCooldown, rng)
    end
    local dir = home and not atHome and chaseDir(e, home.x, home.y, ctx, cfg.chase.homeSearch or 24)
    if dir and Behavior.tryStep(e, ctx.game, dir, Behavior.STEP_FRAMES, { anyGround = anyGround(e) }) then
      if not off then r.steps = r.steps - 1 end
      r.blocked = 0
    elseif off then
      -- stuck out on open ground: wait a moment (someone in the way), then leave
      r.blocked = (r.blocked or 0) + 1
      if r.blocked > cfg.chase.noPathTicks then
        e.chaseHome = nil
        finish(e, ctx.now, cfg.chaseCooldown, rng)
        if ctx.strand then ctx.strand(e) end
      end
    else
      e.chaseHome = nil
      return finish(e, ctx.now, cfg.chaseCooldown, rng)
    end
  end
end

--- Once a tick: is the player moving close to anyone who can react? Starts the reactions:
--- walking past only a skittish / territorial / aggressive one notices, running or biking
--- everyone but the placid (WildReactions.reach). `ctx` as for start(), plus `player`.
--- How the player gets about right now: "bike" | "run" | "walk".
function WildReactions.playerHow()
  local biking = EnginePatch.playerBiking and EnginePatch.playerBiking() or false
  local running = biking or (EnginePatch.playerIsRunning and EnginePatch.playerIsRunning()) or false
  return biking and "bike" or running and "run" or "walk"
end

function WildReactions.scan(entities, ctx)
  local p = ctx.player
  if not (p and p.moving) then return end
  local how = WildReactions.playerHow()
  local cfg = Config.REACT
  local started = 0
  for _, e in ipairs(entities) do
    local d = WildReactions.eligible(e, ctx.now) and manhattan(e.cellX, e.cellY, p.x, p.y)
    if d then
      local reach, aggroAt = WildReactions.reach(e.profile and e.profile.temper, how, cfg)
      if reach and d <= reach and WildReactions.start(e, p.x, p.y, ctx, d, aggroAt) then started = started + 1 end
    end
  end
  return started
end

return WildReactions
