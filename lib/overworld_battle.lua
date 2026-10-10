-- The Battler role: the companion fights wild overworld Pokemon near the player.
--
--   idle     standing with the player; when everything is still and a wild
--            Pokemon is within `radius` cells of the PLAYER (and reachable), ->
--   chase    charges it quickly, cell by cell, to the cell beside it ->
--   fight    short turns (lib/ow_combat.lua: real moves, damage, PP); each turn
--            the attacker leans in, the blow lands with a hit flash + impact,
--            the target plays its hurt animation, the health bars drop ->
--   win      the wild Pokemon cries and sinks into the ground and is gone; the
--            Battler earns a share of the EXP ->  return -> idle
--   (exhausted) the Battler is at 1 HP / out of attacks: the wild Pokemon is
--            let go, the Battler runs back to the player, cries and shrinks
--            into them (retreat -> cry -> recall -> rest); it stays inside until
--            it is healed (rest -> emerge -> idle).
--
-- All motion is cosmetic and draw-time, like lib/follower_actions.lua and
-- lib/forager.lua: the engine owns the follower's real position. This module
-- keeps the Battler's WORLD pixel position (`wx`, `wy`) and reports it back as
-- an offset from the follower's own tile, in the same state shape:
--   { dx, dy, facing, moving, walkMul, anim, animSpeed, flash, away, popup }
-- Wild Pokemon are the SpawnManager's entities; the ones in a skirmish are
-- flagged `engaged` (so they stand still) and animated here.
local V = ...
local Config = V.require("config")
local CellPath = V.require("cell_path")
local OwCombat = V.require("ow_combat")
local ActorRenderer = V.require("actor_renderer")
local HealthBar = V.require("health_bar")
local HitEffect = V.require("hit_effect")
local PopupText = V.require("popup_text")

local OverworldBattle = {}
OverworldBattle.__index = OverworldBattle

local CELL = 16

--- deps = {
---   combat = { battlerOf, moveRow, moveDamage, moveNumber, expGain, expApply, buildWild, rng }
---   targets() -> entities       wild Pokemon that may be fought (SpawnManager:fightTargets)
---   cellFree(x, y) -> bool      a creature can stand there
---   swimFree(x, y) -> bool      optional: a water cell it can swim through
---   occupied(x, y) -> bool      optional: a wild Pokemon is there
---   defeat(id)                  remove a defeated wild Pokemon
---   playCry(species)            the engine cry
---   rng() -> [0,1)              optional
---   cfg                         optional (Config.OW_BATTLE)
--- }
function OverworldBattle.new(deps)
  local self = setmetatable({ deps = deps }, OverworldBattle)
  self.cfg = deps.cfg or Config.OW_BATTLE
  self.combatDeps = deps.combat
  self:reset()
  return self
end

function OverworldBattle:reset()
  self:_release()
  self.mode, self.t = "idle", 0
  self.wx, self.wy, self.dx, self.dy = nil, nil, 0, 0
  self.cooldown, self.scan = 0, 0
  self.facing = nil
  self.fight, self.turn, self.wild, self.target = nil, nil, nil, nil
  self.popup, self.popupAge = nil, 0
  self.hits = {}
  self.flash = 0
  self.away = false
  self.path, self.pathIdx = nil, 0
end

-- Frees the wild Pokemon this Battler had engaged (it goes back to wandering).
function OverworldBattle:_release()
  local e = self.target
  if e then
    e.engaged, e.owPose = false, nil
    if e.renderer then e.renderer.act = nil end
  end
  self.target = nil
end

--- Away from its place (the follower menu must not open on it)?
function OverworldBattle:isBusy()
  return self.mode ~= "idle" or self.away or (self.dx or 0) ~= 0 or (self.dy or 0) ~= 0
end

-- ---------------------------------------------------------------- helpers

local function cheb(ax, ay, bx, by)
  return math.max(math.abs(ax - bx), math.abs(ay - by))
end

local DIRS = { right = { 1, 0 }, left = { -1, 0 }, down = { 0, 1 }, up = { 0, -1 } }
local function dirFacing(fromX, fromY, toX, toY)
  local dx, dy = toX - fromX, toY - fromY
  if math.abs(dx) >= math.abs(dy) then return dx >= 0 and "right" or "left" end
  return dy >= 0 and "down" or "up"
end

-- Moves (wx, wy) toward (tx, ty) by at most `speed` px, one axis at a time.
-- Returns true on arrival.
function OverworldBattle:_moveTo(tx, ty, speed)
  local ddx, ddy = tx - self.wx, ty - self.wy
  if ddx == 0 and ddy == 0 then return true end
  if ddx ~= 0 then
    self.wx = self.wx + math.max(-speed, math.min(speed, ddx))
    self.facing = ddx > 0 and "right" or "left"
  else
    self.wy = self.wy + math.max(-speed, math.min(speed, ddy))
    self.facing = ddy > 0 and "down" or "up"
  end
  return self.wx == tx and self.wy == ty
end

local function exhaustedNow(mon, deps)
  if (tonumber(mon.hp) or 0) <= 1 then return true end
  return #OwCombat.usableMoves(mon, deps) == 0
end

-- ---------------------------------------------------------------- targets

--- Where a wild Pokemon will be standing: the cell it is stepping into while it moves
--- (an engaged one finishes its step, lib/spawn_manager.lua), else its own.
local function restingCell(e)
  if e.moving and e.targetX then return e.targetX, e.targetY end
  return e.cellX, e.cellY
end
OverworldBattle._restingCell = restingCell

function OverworldBattle:_findTarget(env)
  local cfg, deps = self.cfg, self.deps
  -- land, and water too (`swimFree`): it swims out to a water spawn, and fights while
  -- the player surfs
  local res = CellPath.search(env.fx, env.fy, {
    maxDepth = cfg.maxWalk,
    free = function(x, y)
      if deps.occupied and deps.occupied(x, y) then return false end
      return deps.cellFree(x, y) or (deps.swimFree ~= nil and deps.swimFree(x, y)) or false
    end,
  })
  local best, bestPath
  for _, e in ipairs(deps.targets()) do
    local ex, ey = restingCell(e)
    if cheb(ex, ey, env.px, env.py) <= cfg.radius then
      -- the cell beside it that is nearest to walk to
      for _, s in ipairs(CellPath.STEPS) do
        local cx, cy = ex - s[1], ey - s[2] -- standing here, facing s
        local path = not (cx == env.px and cy == env.py) -- never on top of the player
          and CellPath.pathTo(res, cx, cy) or nil
        if path and (not bestPath or #path < #bestPath) then
          best, bestPath = e, path
          best._standX, best._standY = cx, cy
        end
      end
    end
  end
  return best, bestPath
end

function OverworldBattle:_engage(env, e, path)
  local c = self.combatDeps
  local wild = c.buildWild(e.species, e.level, e.personality)
  if not wild then
    e.noFight = true -- never try this one again
    return false
  end
  e.engaged = true
  self.target, self.wild = e, wild
  self.fight = OwCombat.new(env.mon, wild, c)
  self.shownAlly, self.shownWild = env.mon.hp, wild.hp
  self.path, self.pathIdx = path, 1
  self.baseX, self.baseY = env.fx * CELL, env.fy * CELL
  self.mode, self.t = "chase", 0
  return true
end

-- ---------------------------------------------------------------- visuals

-- Animates the wild Pokemon of a skirmish (a PMD sheet, or the HGSS flap).
function OverworldBattle:_wildVisual(anim, speed, dx, dy, flash, sink)
  local e = self.target
  if not (e and e.renderer) then return end
  local r = e.renderer
  r.act = { dx = dx or 0, dy = dy or 0, flash = flash, sink = sink }
  if r.isPmd then
    r:advanceAs(anim or "idle", speed or 1)
    e.owPose = nil
  else
    self.wildClock = (self.wildClock or 0) + 1
    e.owPose = anim and ActorRenderer.idleFlapPose(self.wildClock, 4) or ActorRenderer.POSE_STAND
  end
end

local function leanOffset(dir, amount)
  local d = DIRS[dir] or DIRS.down
  return d[1] * amount, d[2] * amount
end

-- ---------------------------------------------------------------- the tick

local function state(self, env, t)
  t.dx, t.dy = self.wx - env.fpx, self.wy - env.fpy
  t.facing = t.facing or self.facing
  t.away = self.away
  if self.popup then t.popup = { text = self.popup, age = self.popupAge } end
  if self.flash > 0 then t.flash = self.flash / self.cfg.flashTicks end
  return t
end

--- One field tick. `env` = { still, fx, fy (follower cell), fpx, fpy (follower
--- tile px), px, py (player cell), mon (the Battler's party Pokemon),
--- renderer (the follower's, for sprite height) }.
--- Returns the state to draw, or nil while it just stands with the player.
function OverworldBattle:step(env)
  local cfg = self.cfg
  env = env or {}
  if not (env.mon and env.fpx) then
    if self.mode ~= "idle" then self:reset() end
    return nil
  end
  self.env = env
  if not self.wx then self.wx, self.wy = env.fpx, env.fpy end
  self.t = self.t + 1
  if self.flash > 0 then self.flash = self.flash - 1 end
  if self.popup then
    self.popupAge = self.popupAge + 1
    if self.popupAge >= cfg.popupTicks then self.popup = nil end
  end
  for i = #self.hits, 1, -1 do
    self.hits[i].age = self.hits[i].age + 1
    if self.hits[i].age >= HitEffect.LIFE then table.remove(self.hits, i) end
  end
  self.dx, self.dy = self.wx - env.fpx, self.wy - env.fpy

  -- a skirmish whose wild Pokemon vanished (the player started their own battle
  -- with it, it was despawned ...) is dropped
  local gone = self.target and (self.target.state ~= Config.STATE.AVAILABLE
    or (self.deps.alive and not self.deps.alive(self.target)))
  if gone then
    if self.mode == "chase" or self.mode == "fight" or self.mode == "win" then
      self:_release()
      self.fight, self.wild = nil, nil
      self.mode = "return"
    end
  end

  local handler = self["_mode_" .. self.mode]
  return handler and handler(self, env) or nil
end

-- idle: tracks the follower exactly; looks for a fight when everything is still
function OverworldBattle:_mode_idle(env)
  local cfg = self.cfg
  self.wx, self.wy = env.fpx, env.fpy
  self.dx, self.dy = 0, 0
  self.facing = nil
  if self.cooldown > 0 then self.cooldown = self.cooldown - 1 end
  self.scan = self.scan + 1
  local looking = self.scan >= cfg.scanEvery
  if looking and exhaustedNow(env.mon, self.combatDeps) then
    -- carried over a save / map change: it cannot fight, so it stays inside
    self.mode, self.t, self.away = "rest", 0, true
    return state(self, env, { moving = false })
  end
  if not env.still or self.cooldown > 0 then
    if looking then self.scan = 0 end
    if self.popup then return state(self, env, { moving = false }) end
    return nil
  end
  if looking then
    self.scan = 0
    if OwCombat.canFight(env.mon, self.combatDeps, cfg) then
      local e, path = self:_findTarget(env)
      if e and path then
        if self:_engage(env, e, path) then return self:_mode_chase(env) end
      end
    end
  end
  if self.popup then return state(self, env, { moving = false }) end
  return nil
end

function OverworldBattle:_mode_chase(env)
  local cfg = self.cfg
  local path = self.path
  if not path or #path == 0 then
    self.mode, self.t = "fight", 0
    return self:_mode_fight(env)
  end
  local c = path[self.pathIdx]
  if self:_moveTo(c[1] * CELL, c[2] * CELL, cfg.chaseSpeed) then
    if self.pathIdx >= #path then
      self.baseX, self.baseY = self.wx, self.wy
      self.mode, self.t, self.turn = "fight", 0, nil
      self.facing = dirFacing(self.wx, self.wy, self.target.px, self.target.py)
      return state(self, env, { moving = false })
    end
    self.pathIdx = self.pathIdx + 1
  end
  return state(self, env, { moving = true, walkMul = cfg.walkMul })
end

function OverworldBattle:_mode_fight(env)
  local cfg = self.cfg
  local e = self.target
  if not self.turn then
    local ev = self.fight:turn()
    if not ev then
      return self:_finishFight(env)
    end
    self.turn = { ev = ev, t = 0 }
  end
  local turn = self.turn
  turn.t = turn.t + 1
  local ev = turn.ev
  local attackerIsAlly = ev.actor == "ally"

  -- directions: from each side to the other
  local toWild = dirFacing(self.baseX, self.baseY, e.px, e.py)
  local toAlly = dirFacing(e.px, e.py, self.baseX, self.baseY)
  e.facing = toAlly
  self.facing = toWild

  -- the lean: out during the wind-up, back during the recovery
  local lean
  if turn.t <= cfg.windup then
    lean = cfg.lunge * (turn.t / cfg.windup)
  else
    lean = cfg.lunge * math.max(0, 1 - (turn.t - cfg.windup) / (cfg.turnTicks - cfg.windup))
  end

  -- the blow lands
  if turn.t == cfg.windup and not ev.skipped then
    if ev.hit then
      local defenderIsWild = attackerIsAlly
      local hx, hy = self.baseX, self.baseY
      if defenderIsWild then hx, hy = e.px, e.py end
      self.hits[#self.hits + 1] = { x = hx, y = hy, age = 0,
        heavy = (ev.effectiveness or 1) > 1 or ev.critical or false }
      if defenderIsWild then
        self.wildFlash = cfg.flashTicks
      else
        self.flash = cfg.flashTicks
      end
    end
    self.shownAlly, self.shownWild = ev.allyHp, ev.wildHp
  end
  if self.wildFlash and self.wildFlash > 0 then self.wildFlash = self.wildFlash - 1 end

  -- positions this tick
  local allyLeanX, allyLeanY, wildLeanX, wildLeanY = 0, 0, 0, 0
  if attackerIsAlly then allyLeanX, allyLeanY = leanOffset(toWild, lean)
  else wildLeanX, wildLeanY = leanOffset(toAlly, lean) end
  self.wx, self.wy = self.baseX + allyLeanX, self.baseY + allyLeanY

  local allyAnim, wildAnim
  if attackerIsAlly then allyAnim = "attack" elseif self.flash > 0 then allyAnim = "hurt" end
  if not attackerIsAlly then wildAnim = "attack" elseif (self.wildFlash or 0) > 0 then wildAnim = "hurt" end
  local flashRatio = (self.wildFlash or 0) / cfg.flashTicks
  self:_wildVisual(wildAnim, cfg.attackSpeed, wildLeanX, wildLeanY, flashRatio, nil)

  if turn.t >= cfg.turnTicks then self.turn = nil end
  return state(self, env, { moving = false, anim = allyAnim or "idle", animSpeed = cfg.attackSpeed,
    bounce = allyAnim ~= nil, flapTicks = 4 })
end

function OverworldBattle:_finishFight(env)
  local result = self.fight and self.fight:outcome()
  if result == "win" then
    self.mode, self.t, self.cried = "win", 0, false
    return self:_mode_win(env)
  end
  -- exhausted (or any other end): let the wild Pokemon go, run home
  self:_release()
  self.fight, self.wild = nil, nil
  self.mode, self.t = "retreat", 0
  return self:_mode_retreat(env)
end

function OverworldBattle:_mode_win(env)
  local cfg = self.cfg
  local e = self.target
  if not e then
    self.mode = "return"
    return self:_mode_return(env)
  end
  if not self.cried then
    self.cried = true
    if self.deps.playCry then self.deps.playCry(e.species) end
  end
  self.wx, self.wy = self.baseX, self.baseY
  local sink = 0
  if self.t > cfg.winPause then sink = math.min(1, (self.t - cfg.winPause) / cfg.sinkTicks) end
  self:_wildVisual("idle", 1, 0, 0, nil, sink)
  if sink >= 1 then
    -- gone; the EXP
    local amount = OwCombat.expReward(self.wild, self.combatDeps, cfg.expShare)
    -- EXP is held while it waits for the player to learn a move or evolve
    -- (lib/level_ready.lua): another level on top could skip one of those
    if amount > 0 and self.deps.expFrozen and self.deps.expFrozen(env.mon) then amount = 0 end
    local text
    if amount > 0 then
      local result = self.combatDeps.expApply(env.mon, amount)
      text = "+" .. amount .. " EXP"
      if result and result.toLevel and result.fromLevel and result.toLevel > result.fromLevel then
        text = "Lv." .. result.toLevel .. "!"
        -- it cannot learn or evolve mid-walk: tell the owner, which asks the player
        if self.deps.levelUp then pcall(self.deps.levelUp, env.mon, result.fromLevel, result.toLevel) end
      end
    end
    local id = e.id
    self:_release()
    if self.deps.defeat then self.deps.defeat(id) end
    self.fight, self.wild = nil, nil
    self.popup, self.popupAge = text, 0
    self.mode, self.t = "return", 0
    return self:_mode_return(env)
  end
  return state(self, env, { moving = false, bounce = false })
end

-- run back to the follower's own tile
function OverworldBattle:_mode_return(env)
  local cfg = self.cfg
  if self:_moveTo(env.fpx, env.fpy, cfg.chaseSpeed) then
    self.mode, self.t, self.cooldown = "idle", 0, cfg.cooldown
    self.dx, self.dy, self.facing = 0, 0, nil
    return state(self, env, { moving = false })
  end
  return state(self, env, { moving = true, walkMul = cfg.walkMul })
end

function OverworldBattle:_mode_retreat(env)
  local cfg = self.cfg
  if self:_moveTo(env.fpx, env.fpy, cfg.chaseSpeed) then
    self.mode, self.t, self.cried = "cry", 0, false
    return self:_mode_cry(env)
  end
  return state(self, env, { moving = true, walkMul = cfg.walkMul })
end

function OverworldBattle:_mode_cry(env)
  local cfg = self.cfg
  self.wx, self.wy = env.fpx, env.fpy
  if not self.cried then
    self.cried = true
    if self.deps.playCry then self.deps.playCry(env.mon.species) end
  end
  if self.t >= cfg.cryPause then
    self.mode, self.t, self.away = "rest", 0, true -- the adapter shrinks it into the player
  end
  return state(self, env, { moving = false })
end

-- inside the player until healed
function OverworldBattle:_mode_rest(env)
  local cfg = self.cfg
  self.wx, self.wy = env.fpx, env.fpy
  self.away = true
  if self.t % cfg.restCheck == 0 and OwCombat.canFight(env.mon, self.combatDeps, cfg) then
    self.mode, self.t, self.away = "emerge", 0, false
  end
  return state(self, env, { moving = false })
end

function OverworldBattle:_mode_emerge(env)
  local cfg = self.cfg
  self.wx, self.wy = env.fpx, env.fpy
  if self.t >= cfg.recallTicks then
    self.mode, self.t, self.cooldown = "idle", 0, cfg.cooldown
  end
  return state(self, env, { moving = false })
end

-- ---------------------------------------------------------------- overlays

--- Health bars, hit effects and the "+EXP" label as field actors.
function OverworldBattle:collectActors(actors)
  local env = self.env
  if not env or not self.wx then return end
  local fighting = self.fight ~= nil and (self.mode == "fight" or self.mode == "chase")
  if fighting and self.target then
    local e = self.target
    local lift = 20
    local r = env.renderer
    if r and r.visualHeight then lift = math.max(14, math.min(48, (r:visualHeight() or 20))) end
    actors[#actors + 1] = HealthBar.actor(self.wx, self.wy, self.shownAlly, env.mon.maxHp, lift + 4, 3, 1)
    local wlift = 20
    if e.renderer and e.renderer.visualHeight then wlift = math.max(14, math.min(48, e.renderer:visualHeight() or 20)) end
    actors[#actors + 1] = HealthBar.actor(e.px, e.py, self.shownWild, self.wild.maxHp, wlift + 4, 3, 2)
  end
  for i, h in ipairs(self.hits) do
    local a = HitEffect.actor(h.x, h.y, h.age, h.heavy, 3, i)
    if a then actors[#actors + 1] = a end
  end
end

return OverworldBattle
