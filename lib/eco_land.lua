-- Wild Ecology on land (lib/eco.lua activities for visible LAND spawns, by lib/eco_profile.lua
-- `social` / `diet`): a pack trots about in short bursts and now and then rears up and howls,
-- a herd drifts slowly and stops to graze, a swarm buzzes about, a huddle sits together and
-- naps, and a lone grazer stops to eat now and then. A special spawn's riders (lib/
-- spawn_manager.lua _tickRider) show what their leader does: the activity's `groupAnim`.
--
-- Animations are the PMDCollab poses baked for Wild Ecology (Eat, EventSleep "nap", Wake,
-- RearUp: tools/generate_pmd_sprites.py ECO_ANIMS) where the species has them; without one a
-- grazer just stands, a napper rests on Idle's first frame, and nobody rears up. HGSS art
-- has no such poses: it stands for all of them.
local V = ...
local Config = V.require("config")
local EnginePatch = V.require("engine_patch")
local Eco = V.require("eco")
local Behavior = V.require("behavior")
local PmdRenderer = V.require("pmd_renderer")
local WildReactions = V.require("wild_reactions")

local EcoLand = {}

local function between(rng, r) return rng(r[1], r[2]) end

-- does `e`'s PMD art have animation `anim`?
local function hasAnim(e, anim)
  local r = e.renderer
  return r and r.isPmd and r.info and r.info[anim] ~= nil or false
end
EcoLand._hasAnim = hasAnim

-- how far the player is (Chebyshev tiles), and whether they are running / biking
local function playerNear(e, ctx)
  local p = ctx and ctx.player
  if not p then return math.huge, false end
  local d = math.max(math.abs(p.x - e.cellX), math.abs(p.y - e.cellY))
  local running = (EnginePatch.playerIsRunning and EnginePatch.playerIsRunning()) or false
  return d, running and p.moving
end
EcoLand._playerNear = playerNear

-- ------- a burst of steps (pack trot, herd drift, swarm buzz)

--- State for `n` steps at `frames` a step, heading `dir` (kept while it can, else a turn).
function EcoLand.burstState(e, n, frames, rng)
  rng = rng or math.random
  local dirs = { "up", "down", "left", "right" }
  return { n = n, frames = frames, dir = dirs[rng(1, 4)], blocked = 0 }
end

Eco.register("burst", {
  step = function(e, ctx, _sm, s)
    if e.moving then
      Behavior._advanceMove(e)
      if e.renderer and e.renderer.advance then e.renderer:advance(true) end
      return false
    end
    if e.renderer and e.renderer.advance then e.renderer:advance(false) end
    if s.n <= 0 or s.blocked > 6 then return true end
    local game = ctx and ctx.game
    if Behavior.tryStep(e, game, s.dir, s.frames) then
      s.n = s.n - 1
      if e.renderer and e.renderer.advance then e.renderer:advance(true) end
      return false
    end
    -- the way is shut: another heading (not back the way it came, unless it must)
    s.blocked = s.blocked + 1
    local turns = { up = { "left", "right", "down" }, down = { "right", "left", "up" },
                    left = { "down", "up", "right" }, right = { "up", "down", "left" } }
    local opts = turns[s.dir] or { "up" }
    s.dir = opts[((ctx and ctx.rng or math.random)(1, 2))] or opts[1]
    return false
  end,
})

-- ------- a pose held a while (graze, howl, nap + wake)

--- State for holding `anim` (when the art has it) for `n` ticks; `wake`: a nap ends with the
--- Wake animation, and the player coming close wakes it early. `rouse`: the player coming
--- within that many tiles (one more running) ends it early too. A pose played once (Sit,
--- LookUp: PmdRenderer.ONCE) is played back to its first frame at the end (getting up,
--- looking back down), and a back-view pose turns the Pokemon away first (`face`).
function EcoLand.poseState(e, anim, n, opts)
  opts = opts or {}
  local have = hasAnim(e, anim)
  local info = have and e.renderer.info or nil
  return { n = n, anim = have and anim or nil, groupAnim = have and anim or nil,
           wake = opts.wake and hasAnim(e, "wake"), cry = opts.cry, napping = anim == "nap",
           rouse = opts.rouse, face = info and PmdRenderer.facingOf(info, anim) or nil,
           unwind = have and PmdRenderer.ONCE[anim] and PmdRenderer.animTicks(info, anim) or nil }
end

Eco.register("pose", {
  step = function(e, ctx, _sm, s)
    local r = e.renderer
    local cfg = Config.ECO.land
    if s.t == 1 and s.face then e.facing = s.face end
    if s.cry and s.t == 1 and EnginePatch.playCry then pcall(EnginePatch.playCry, e.species) end
    -- a napper wakes when the player comes right up to it (or runs close by); a sitter gets up
    if (s.napping or s.rouse) and not s.waking and not s.unwinding then
      local d, running = playerNear(e, ctx)
      local radius = s.rouse or cfg.nap.wakeRadius
      if d <= radius or (running and d <= radius + 1) then
        s.n = s.t -- it wakes now
      end
    end
    if s.t >= s.n and not s.waking and not s.unwinding then
      if s.wake then
        s.waking, s.anim, s.groupAnim, s.wakeT = true, "wake", "wake", 0
      elseif s.unwind and s.unwind > 0 then
        s.unwinding, s.wakeT = true, 0 -- played back: up again / looking back down
      else
        return true
      end
    end
    if s.waking then
      s.wakeT = s.wakeT + 1
      if s.wakeT > cfg.nap.wakeTicks then return true end
    end
    if s.unwinding then
      s.wakeT = s.wakeT + 1
      if s.wakeT > s.unwind then return true end
    end
    if r and r.isPmd and s.anim and r.advanceAs then
      r:advanceAs(s.anim, s.unwinding and -1 or s.waking and 1 or (s.speed or 1), "idle")
    elseif r and r.isPmd and s.napping and r.holdIdle then
      r:holdIdle() -- no sleeping art: it rests still
    elseif r and r.advance then
      r:advance(false)
    end
    return false
  end,
  abort = function(e)
    local r = e.renderer
    if r and r.isPmd and r.advance then r:advance(false) end
  end,
})

-- ------- what a land Pokemon does next (an Eco chooser)

local function due(e, key, range, rng, now)
  e.ecoDue = e.ecoDue or {}
  local at = e.ecoDue[key]
  if not at then
    e.ecoDue[key] = now + between(rng, range)
    return false
  end
  if now < at then return false end
  e.ecoDue[key] = now + between(rng, range)
  return true
end

local function grazer(prof)
  return prof.diet ~= "predator"
end

function EcoLand.choose(e, ctx, sm)
  if e.terrain ~= "land" or e.roamer or e.lured or e.react or e.engaged or e.fx or e.moving then return nil end
  if e.isFlyer and not (e.group and e.group.social == "swarm") then return nil end
  local prof = e.profile
  if not prof then return nil end
  local cfg = Config.ECO.land
  local rng, now = ctx.rng or math.random, ctx.now or 0
  local d = playerNear(e, ctx)
  if d <= cfg.clearRadius then return nil end
  local social = e.group and e.group.social or "solo"
  if social == "pack" then
    if hasAnim(e, "rearup") and due(e, "howl", cfg.howl.every, rng, now) then
      return "pose", EcoLand.poseState(e, "rearup", cfg.howl.ticks, { cry = d <= cfg.howl.cryRadius })
    end
    if due(e, "trot", cfg.trot.every, rng, now) then
      return "burst", EcoLand.burstState(e, between(rng, cfg.trot.steps), cfg.trot.frames, rng)
    end
  elseif social == "herd" then
    if due(e, "graze", cfg.graze.every, rng, now) then
      return "pose", EcoLand.poseState(e, "eat", between(rng, cfg.graze.ticks))
    end
    if due(e, "drift", cfg.drift.every, rng, now) then
      return "burst", EcoLand.burstState(e, between(rng, cfg.drift.steps), cfg.drift.frames, rng)
    end
  elseif social == "swarm" then
    if due(e, "buzz", cfg.buzz.every, rng, now) then
      return "burst", EcoLand.burstState(e, between(rng, cfg.buzz.steps), cfg.buzz.frames, rng)
    end
  elseif social == "huddle" then
    if hasAnim(e, "nap") and due(e, "nap", cfg.nap.every, rng, now) then
      return "pose", EcoLand.poseState(e, "nap", between(rng, cfg.nap.ticks), { wake = true })
    end
  elseif grazer(prof) and hasAnim(e, "eat") and due(e, "graze", cfg.soloGraze.every, rng, now) then
    -- a lone Pokemon with something to nibble: now and then it stops to eat
    return "pose", EcoLand.poseState(e, "eat", between(rng, cfg.graze.ticks))
  end
  -- anyone but a swarm: now and then it sits down a while (Sit art only)
  if social ~= "swarm" and hasAnim(e, "sit") and due(e, "sit", cfg.sit.every, rng, now) then
    return "pose", EcoLand.poseState(e, "sit", between(rng, cfg.sit.ticks), { rouse = cfg.sit.rouseRadius })
  end
  return nil
end
Eco.addChooser(EcoLand.choose)

-- ------- a Pokemon pretending to be something it is not (profile `mimic`: Sudowoodo, Bonsly
-- pass for a tree): it stands stock-still -- no wandering, no idle motion, nothing Wild Reacts
-- would make of it -- until the player comes too close; then it jumps ("!") and bolts.

Eco.register("mimic", {
  step = function(e, ctx, _sm, s)
    local cfg = Config.ECO.mimic
    local r = e.renderer
    if r and r.isPmd and r.holdIdle then r:holdIdle() elseif r and r.advance then r:advance(false) end
    e.facing = s.facing or e.facing
    local d, running = playerNear(e, ctx)
    if d <= cfg.radius or (running and d <= cfg.runRadius) then
      local p = ctx.player
      -- found out: it bolts (not a "!"-then-maybe: it always does)
      e.eco = nil
      if WildReactions.begin(e, "flee", p.x, p.y, ctx) == "weak" and e.react then
        e.react.fleeSteps = between(ctx.rng or math.random, cfg.bolt)
      end
      return false
    end
    return false
  end,
})

--- A mimic at rest goes back to standing stock-still (asked first: before anything else).
function EcoLand.chooseMimic(e, ctx)
  local prof = e.profile
  if not (prof and prof.mimic) or e.terrain ~= "land" then return nil end
  if e.roamer or e.lured or e.react or e.engaged or e.fx or e.moving then return nil end
  return "mimic", { facing = "down" }
end

--- A bird flying over (lib/sky_flyers.lua `passerOver`): a land Pokemon with LookUp art that
--- has not looked at this one yet may stop and look up at it. Asked first (before what it
--- would do otherwise), on each Pokemon's own choosing timer, so they notice one by one.
function EcoLand.chooseLookUp(e, ctx, sm)
  if e.terrain ~= "land" or e.roamer or e.lured or e.react or e.engaged or e.fx or e.moving then return nil end
  if e.isFlyer or not hasAnim(e, "lookup") then return nil end
  local bird = sm and sm.sky and sm.sky.passerOver and sm.sky:passerOver()
  if not bird or e.lookedAt == bird.id then return nil end
  e.lookedAt = bird.id
  local cfg = Config.ECO.land
  local rng = ctx.rng or math.random
  if playerNear(e, ctx) <= cfg.clearRadius or rng(1, 100) > cfg.lookUp.chance then return nil end
  return "pose", EcoLand.poseState(e, "lookup", between(rng, cfg.lookUp.ticks))
end
Eco.addChooser(EcoLand.chooseLookUp, true)
Eco.addChooser(EcoLand.chooseMimic, true)

return EcoLand
