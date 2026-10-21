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
    and not e.fx and not e.roamer and (e.reactUntil or 0) <= (now or 0)
end

--- Starts `e` reacting to the player at (px, py), `dist` tiles away: picks the reaction
--- from its strength. A stronger one only gets angry much closer (`aggroAt` tiles); a
--- skittish one reacts from farther. Returns the class, or nil when it does not react.
--- `ctx` = { now, rng, lead = {level, bst}, bst(species), canFly(e) }.
function WildReactions.start(e, px, py, ctx, dist, aggroAt)
  local cfg, rng = Config.REACT, ctx.rng or math.random
  local cls, ratio = WildReactions.classify(e.level, ctx.bst and ctx.bst(e.species), ctx.lead and ctx.lead.level,
    ctx.lead and ctx.lead.bst, cfg)
  if cls == "neutral" then return nil end -- an even match is not bothered
  if cls == "strong" and dist and dist > (aggroAt or cfg.aggroRadius) then return nil end -- not close enough yet
  -- the closer the match, the likelier it shrugs the player off; one roll, then a rest
  if rng(1, 100) > WildReactions.chance(cls, ratio, cfg) then
    e.reactUntil = (ctx.now or 0) + (cfg.missCooldown or cfg.cooldown)
    return nil
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

--- One tick of `e`'s reaction. `ctx` = { now, rng, game, player = playerCell(),
--- occupied(x, y, self), onContact(e), takeoff(e) }.
function WildReactions.tick(e, ctx)
  local cfg, rng = Config.REACT, ctx.rng or math.random
  local r = e.react
  if not r then return end
  r.t = r.t + 1
  r.emoteAge = (r.emoteAge or 0) + 1
  if r.emoteAge > cfg.emoteTicks then r.emote = nil end
  local p = ctx.player
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
      r.mode, r.steps, r.blocked = "flee", rngRange(rng, cfg.flee.steps), 0
    elseif r.next == "chase" then
      local leash = rngRange(rng, cfg.chase.leash)
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

--- Once a tick: is the player running / biking close to anyone who can react? Starts the
--- reactions. `ctx` as for start(), plus `entities` (an iterator list) and `player`.
function WildReactions.scan(entities, ctx)
  local p = ctx.player
  if not (p and p.moving) then return end
  local biking = EnginePatch.playerBiking and EnginePatch.playerBiking() or false
  local running = biking or (EnginePatch.playerIsRunning and EnginePatch.playerIsRunning()) or false
  if not running then return end
  local cfg = Config.REACT
  local radius = biking and cfg.bikeRadius or cfg.radius
  local aggroAt = biking and cfg.bikeAggroRadius or cfg.aggroRadius
  local started = 0
  for _, e in ipairs(entities) do
    local d = WildReactions.eligible(e, ctx.now) and manhattan(e.cellX, e.cellY, p.x, p.y)
    if d and d <= radius and WildReactions.start(e, p.x, p.y, ctx, d, aggroAt) then started = started + 1 end
  end
  return started
end

return WildReactions
