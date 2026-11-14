-- Wild Ecology: predators and prey (Stage 3). Now and then a hunter (lib/eco_profile.lua
-- diet "predator") on screen picks a smaller, weaker Pokemon nearby that it hunts (its
-- profile's `prey` types, or any prey-sized one) and gives chase -- the anger mark, then a
-- run after it while the prey jumps ("!") and flees (lib/wild_reactions.lua startAt). Caught,
-- they fight: a short skirmish with real moves, stats and types (lib/ow_combat.lua, both
-- built as wild fighters; the hunter is the "ally" side, so it is never knocked out -- worn
-- down to 1 HP it gives up and flees). The prey may break away when hurt and run off, or
-- faint: the knockout, then it sinks away (normal refill replaces it). Rivals (`rival`:
-- Zangoose and Seviper, Heracross and Pinsir) fight on sight, whatever their size.
--
-- Damage carries: both keep their fighter on the entity (`owWild`), so the player walking
-- into either afterwards battles it at the HP the skirmish left (lib/battle_trigger.lua).
-- Touching one mid-skirmish ends the skirmish first (Eco.abort) and starts that battle.
--
-- One hunt at a time per map, never right beside the player, with a cooldown between hunts.
-- No EXP, no drops: the player's party has no part in it.
local V = ...
local Config = V.require("config")
local EnginePatch = V.require("engine_patch")
local Eco = V.require("eco")
local OwCombat = V.require("ow_combat")
local WildReactions = V.require("wild_reactions")
local HealthBar = V.require("health_bar")
local HitEffect = V.require("hit_effect")

local EcoHunt = {}

local function cheb(a, b) return math.max(math.abs(a.cellX - b.cellX), math.abs(a.cellY - b.cellY)) end
local function between(rng, r) return rng(r[1], r[2]) end

-- the type names of engine species `species` (cached)
local typeCache = {}
local function typesOf(species)
  local hit = typeCache[species]
  if hit then return hit end
  local out = {}
  if EnginePatch.speciesTypes and EnginePatch.typeName then
    local t1, t2 = EnginePatch.speciesTypes(species)
    -- (type 0 is NORMAL, not "none": a pure Normal-type reads 0, 0)
    out[1] = EnginePatch.typeName(t1 or 0)
    if t2 and t2 ~= t1 then out[2] = EnginePatch.typeName(t2) end
  end
  typeCache[species] = out
  return out
end
EcoHunt._typesOf = typesOf

-- a Pokemon's strength for the size rule: level x base stat total (else level)
local function strength(e)
  local bst = EnginePatch.baseStatTotal and EnginePatch.baseStatTotal(e.species) or nil
  return (tonumber(e.level) or 5) * (bst or 300)
end
EcoHunt._strength = strength

--- Can `e` take part in a hunt right now (free, standing, not a rider, not the roamer)?
function EcoHunt.free(e)
  return e.state == Config.STATE.AVAILABLE and not e.eco and not e.react and not e.engaged
    and not e.fx and not e.lured and not e.rider and not e.roamer and not e.runAway
    and not e.defeated and not e.moving and not e.charging
end

--- Does `pred` hunt `prey`? A rival always; else a hunter whose prey types (or any, when it
--- lists none) match, that is clearly stronger (`Config.ECO.hunt.sizeRatio`). Pure but for
--- the engine's species reads. Returns "rival" | "hunt" | nil.
function EcoHunt.relation(pred, prey)
  local pp, qp = pred.profile, prey.profile
  if not (pp and qp) or pred == prey or pred.species == prey.species then return nil end
  if pp.rival and qp.dex and pp.rival[qp.dex] then return "rival" end
  if pp.diet ~= "predator" or qp.diet == "predator" then return nil end
  if pred.terrain ~= prey.terrain then return nil end
  if pp.prey then
    local ok = false
    for _, t in ipairs(typesOf(prey.species)) do
      for _, want in ipairs(pp.prey) do if t == want then ok = true end end
    end
    if not ok then return nil end
  elseif qp.diet ~= "prey" then
    return nil
  end
  if strength(pred) < strength(prey) * Config.ECO.hunt.sizeRatio then return nil end
  return "hunt"
end

--- Once in a while (every `scanEvery` ticks, no hunt on, the cooldown over): a hunter on
--- screen -- at least `minPlayerDist` tiles from the player and inside the view -- with prey
--- within `radius` tiles starts a hunt (`chance` %, a rivalry `rivalChance` %). `state` is
--- the map's hunt bookkeeping (lib/spawn_manager.lua keeps it). Returns true when one began.
function EcoHunt.scan(list, ctx, state)
  local cfg = Config.ECO.hunt
  local now = ctx.now or 0
  if state.active or now < (state.next or 0) then return false end
  if now - (state.lastScan or -math.huge) < cfg.scanEvery then return false end
  state.lastScan = now
  local p = ctx.player
  if not p then return false end
  local rng = ctx.rng or math.random
  -- both on screen (the view is centred on the player; a tile's margin kept): 6 x 4 tiles
  -- each way on the GBA's 240 x 160
  local vw, vh = 240, 160
  if EnginePatch.viewSize then vw, vh = EnginePatch.viewSize() end
  local hx = math.min(cfg.maxPlayerDist, math.floor(vw / 32) - 1)
  local hy = math.min(cfg.maxPlayerDist, math.floor(vh / 32) - 1)
  local function seen(e)
    local dx, dy = math.abs(e.cellX - p.x), math.abs(e.cellY - p.y)
    return dx <= hx and dy <= hy and math.max(dx, dy) >= cfg.minPlayerDist
  end
  for _, pred in ipairs(list) do
    if EcoHunt.free(pred) and pred.profile and (pred.profile.diet == "predator" or pred.profile.rival)
      and seen(pred) then
      for _, prey in ipairs(list) do
        if prey ~= pred and EcoHunt.free(prey) and seen(prey) and cheb(pred, prey) <= cfg.radius then
          local rel = EcoHunt.relation(pred, prey)
          if rel and rng(1, 100) <= (rel == "rival" and cfg.rivalChance or cfg.chance) then
            return EcoHunt.start(pred, prey, rel, ctx, state)
          end
        end
      end
    end
  end
  state.next = now + cfg.missCooldown
  return false
end

--- The hunt begins: the hunter's anger mark and chase; the prey jumps and runs (a rival
--- turns to fight instead).
function EcoHunt.start(pred, prey, rel, ctx, state)
  local cfg = Config.ECO.hunt
  local rng = ctx.rng or math.random
  if not WildReactions.startAt(pred, prey, "hunt", ctx, cfg.leash) then return false end
  if rel == "rival" then
    WildReactions.startAt(prey, pred, "hunt", ctx, cfg.leash)
  else
    WildReactions.startAt(prey, pred, "flee", ctx, between(rng, cfg.preyFlee))
  end
  pred.huntRole, prey.huntRole = "hunter", "hunted"
  state.active = { pred = pred, prey = prey, rel = rel, started = ctx.now or 0 }
  return true
end

--- The hunt is over (a skirmish ended, the chase gave up, one of them left): the next one
--- may come after the cooldown.
function EcoHunt.finish(state, ctx)
  local a = state.active
  if a then
    a.pred.huntRole, a.prey.huntRole = nil, nil
  end
  state.active = nil
  local rng = ctx and ctx.rng or math.random
  state.next = (ctx and ctx.now or 0) + between(rng, Config.ECO.hunt.cooldown)
end

--- Keeps the map's hunt honest each tick: a chase that ended without a catch (it gave up,
--- the prey got away, one of them was met by the player) frees the slot.
function EcoHunt.tick(state, ctx)
  local a = state.active
  if not a or a.sk then return end
  local pred, prey = a.pred, a.prey
  local chasing = pred.react and pred.react.target == prey
  if not chasing or pred.state ~= Config.STATE.AVAILABLE or prey.state ~= Config.STATE.AVAILABLE then
    EcoHunt.finish(state, ctx)
  end
end

-- ------- the skirmish ---------------------------------------------------------------

local DIRS = { right = { 1, 0 }, left = { -1, 0 }, down = { 0, 1 }, up = { 0, -1 } }
local function faceToward(a, b)
  local dx, dy = b.cellX - a.cellX, b.cellY - a.cellY
  if math.abs(dx) >= math.abs(dy) then return dx >= 0 and "right" or "left" end
  return dy >= 0 and "down" or "up"
end

local function combatDeps()
  return {
    battlerOf = EnginePatch.battlerOf, moveRow = EnginePatch.moveRow, moveDamage = EnginePatch.moveDamage,
    moveNumber = EnginePatch.moveNumber or function(m)
      return tonumber(type(m) == "table" and (m.id or m.move) or m) or 0
    end,
    rng = math.random,
  }
end

local function fighterOf(e)
  if e.owWild then return e.owWild end
  local f = EnginePatch.buildWildFighter and EnginePatch.buildWildFighter(e.species, e.level, e.personality, e.ivs)
  e.owWild = f
  return f
end

--- The hunter caught its prey (ctx.onCatch): the skirmish. `sm` = the spawn manager (for the
--- knockout's despawn), `state` = the map's hunt. Returns the skirmish, or nil.
function EcoHunt.catch(pred, prey, ctx, sm, state)
  local a = state and state.active
  if prey.state ~= Config.STATE.AVAILABLE or pred.state ~= Config.STATE.AVAILABLE then
    if state then EcoHunt.finish(state, ctx) end
    return nil
  end
  local fp, fq = fighterOf(pred), fighterOf(prey)
  if not (fp and fq) then
    if state then EcoHunt.finish(state, ctx) end
    return nil
  end
  -- the prey stops running: it has been caught
  if prey.react then WildReactions.finish(prey, ctx.now, 0) end
  if prey.moving then
    prey.moving = false
    prey.cellX, prey.cellY = prey.targetX or prey.cellX, prey.targetY or prey.cellY
    prey.px, prey.py = prey.cellX * 16, prey.cellY * 16
  end
  local sk = { pred = pred, prey = prey, fight = OwCombat.new(fp, fq, combatDeps()), phase = "face", t = 0,
               turns = 0, hits = {}, flash = { [pred] = 0, [prey] = 0 }, shown = { [pred] = fp.hp, [prey] = fq.hp },
               maxHp = { [pred] = fp.maxHp or fp.hp, [prey] = fq.maxHp or fq.hp }, state = state, sm = sm,
               rel = a and a.rel or "hunt" }
  if a then a.sk = sk end
  Eco.start(pred, "skirmish", { sk = sk, role = "pred" })
  Eco.start(prey, "skirmish", { sk = sk, role = "prey" })
  pred.facing, prey.facing = faceToward(pred, prey), faceToward(prey, pred)
  if EnginePatch.playCry then pcall(EnginePatch.playCry, pred.species) end
  return sk
end

-- a fighter's look this tick: its lean toward the other, its animation, the red flash
local function pose(e, other, lean, anim, flash)
  local r = e.renderer
  if not r then return end
  local d = DIRS[faceToward(e, other)]
  r.act = { dx = d[1] * lean, dy = d[2] * lean, flash = flash, ecoSkirmish = true }
  if r.isPmd and r.advanceAs then
    r:advanceAs(anim or "idle", anim and Config.ECO.hunt.attackSpeed or 1, anim == "bite" and "attack" or nil)
  end
end

local function clearPose(e)
  local r = e.renderer
  if r and r.act and r.act.ecoSkirmish then r.act = nil end
end

-- the skirmish is over: both freed; `loser` (if any) runs from the winner
local function release(sk, ctx, loser, winner)
  if sk.over then return end
  sk.over = true
  for _, e in ipairs({ sk.pred, sk.prey }) do
    clearPose(e)
    if e.eco and e.eco.sk == sk then e.eco = nil end
  end
  if loser and winner and loser.state == Config.STATE.AVAILABLE then
    WildReactions.startAt(loser, winner, "flee", ctx, between(ctx.rng or math.random, Config.ECO.hunt.preyFlee))
  end
  if sk.state then EcoHunt.finish(sk.state, ctx) end
end
EcoHunt._release = release

local function step(sk, ctx)
  local cfg, ob = Config.ECO.hunt, Config.OW_BATTLE
  local pred, prey = sk.pred, sk.prey
  sk.t = sk.t + 1
  for _, h in ipairs(sk.hits) do h.age = h.age + 1 end
  while sk.hits[1] and sk.hits[1].age > HitEffect.LIFE do table.remove(sk.hits, 1) end
  for e, f in pairs(sk.flash) do if f > 0 then sk.flash[e] = f - 1 end end

  if sk.phase == "face" then
    pose(pred, prey, 0, nil, 0)
    pose(prey, pred, 0, nil, 0)
    if sk.t >= cfg.faceTicks then sk.phase, sk.t = "fight", 0 end
    return
  end

  if sk.phase == "ko" then
    -- the prey faints: its cry, then it sinks away; the hunter stands over it
    local sink = sk.t > cfg.winPause and math.min(1, (sk.t - cfg.winPause) / cfg.sinkTicks) or 0
    if prey.renderer then prey.renderer.act = { sink = sink, ecoSkirmish = true } end
    pose(pred, prey, 0, nil, 0)
    if sink >= 1 then
      clearPose(pred)
      if pred.eco and pred.eco.sk == sk then pred.eco = nil end
      sk.over = true
      if sk.state then EcoHunt.finish(sk.state, ctx) end
      if sk.sm then sk.sm:despawn(prey.id) end
    end
    return
  end

  -- "fight": turns like the Battler's skirmish (Config.OW_BATTLE windup / turnTicks / lunge)
  if not sk.turn then
    local ev = sk.fight:turn()
    sk.turns = sk.turns + 1
    if not ev then return release(sk, ctx, pred, prey) end
    sk.turn = { ev = ev, t = 0 }
  end
  local turn = sk.turn
  turn.t = turn.t + 1
  local ev = turn.ev
  local attacker = ev.actor == "ally" and pred or prey
  local defender = attacker == pred and prey or pred
  local lean
  if turn.t <= ob.windup then lean = ob.lunge * (turn.t / ob.windup)
  else lean = ob.lunge * math.max(0, 1 - (turn.t - ob.windup) / (ob.turnTicks - ob.windup)) end
  if turn.t == ob.windup and not ev.skipped then
    if ev.hit then
      sk.hits[#sk.hits + 1] = { x = defender.px, y = defender.py, age = 0, heavy = (ev.effectiveness or 1) > 1 or ev.critical }
      sk.flash[defender] = ob.flashTicks
      if ev.result == "win" and EnginePatch.playCry then pcall(EnginePatch.playCry, prey.species) end
    end
    sk.shown[pred], sk.shown[prey] = ev.allyHp, ev.wildHp
  end
  local biteAnim = (attacker.renderer and attacker.renderer.info and attacker.renderer.info.bite) and "bite" or "attack"
  pose(attacker, defender, lean, biteAnim, 0)
  local df = sk.flash[defender] / ob.flashTicks
  pose(defender, attacker, 0, df > 0 and "hurt" or nil, df)
  if turn.t < ob.turnTicks then return end
  sk.turn = nil
  local result = ev.result
  if result == "win" then
    prey.defeated = true
    sk.phase, sk.t = "ko", 0
    return
  end
  if result == "exhausted" then return release(sk, ctx, pred, prey) end -- the hunter gives up
  -- a hurt prey breaks away now and then; a long fight ends with it getting away
  local fq = prey.owWild
  local frac = fq and fq.maxHp and fq.maxHp > 0 and (fq.hp / fq.maxHp) or 1
  local rng = ctx.rng or math.random
  if sk.rel ~= "rival" and ev.actor == "wild" and frac <= cfg.escapeFrac and rng(1, 100) <= cfg.escapeChance then
    return release(sk, ctx, prey, pred)
  end
  if sk.turns >= cfg.maxTurns then return release(sk, ctx, prey, pred) end
end
EcoHunt._step = step

Eco.register("skirmish", {
  step = function(e, ctx, _sm, s)
    local sk = s.sk
    if not sk or sk.over then return true end
    -- the hunter's tick drives the skirmish; the prey's just holds it in place
    if s.role == "pred" then step(sk, ctx) end
    if e.moving then e.moving = false end
    return sk.over and e.eco == s
  end,
  abort = function(e, _sm, s)
    local sk = s and s.sk
    clearPose(e)
    if sk and not sk.over then
      -- met by the player (or something else took one of them): the other one is let go
      local other = e == sk.pred and sk.prey or sk.pred
      release(sk, { now = 0, rng = math.random }, nil, nil)
      if other.state == Config.STATE.AVAILABLE then clearPose(other) end
    end
  end,
})

--- The skirmish's overlays: health bars over both fighters, hit bursts.
function EcoHunt.collectActors(state, actors)
  local a = state and state.active
  local sk = a and a.sk
  if not sk or sk.over then return end
  for _, e in ipairs({ sk.pred, sk.prey }) do
    local r = e.renderer
    local lift = r and ((r.headLift and r:headLift()) or 20) or 20
    lift = math.max(10, math.min(96, lift)) + 2
    actors[#actors + 1] = HealthBar.actor(e.px, e.py, sk.shown[e] or 1, sk.maxHp[e] or 1, lift, e.elevation, e.id)
  end
  for i, h in ipairs(sk.hits) do
    local act = HitEffect.actor(h.x, h.y, h.age, h.heavy, sk.prey.elevation, 70000 + i)
    if act then actors[#actors + 1] = act end
  end
end

return EcoHunt
