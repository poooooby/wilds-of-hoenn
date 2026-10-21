-- The Battler role: the companion fights wild overworld Pokemon near the player.
--
--   idle     standing with the player; when everything is still and a wild
--            Pokemon is within `radius` cells of the PLAYER (and reachable), ->
--   chase    charges it quickly, cell by cell, to the cell beside it ->
--   fight    short turns (lib/ow_combat.lua: real moves, damage, PP); each turn
--            the attacker leans in, the blow lands with a hit flash + impact,
--            the target plays its hurt animation, the health bars drop ->
--   win      the knockout blow shows an effect of the finishing move's TYPE (a water
--            splash, flames, leaves, Fairy sparkles ... lib/finisher_fx.lua); the wild
--            Pokemon cries and sinks into the ground (a Ghost blow: fades) and is gone;
--            the Battler earns a share of the EXP ->  return -> idle
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
local ForageSparkle = V.require("forage_sparkle")
local PartnerFx = V.require("partner_fx")
local FinisherFx = V.require("finisher_fx")

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
---   chainRecord(species, result) optional: count a win toward a shiny chain
---   playCry(species)            the engine cry
---   playSe(name)                optional: an engine sound effect by SE_* name (the
---                               knockout's move sound; the game's SFX volume applies)
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
  -- one it knocked out (0 HP, sinking) never goes back to wandering: it is gone
  local ko = self.target
  if ko and ko.defeated and self.deps and self.deps.defeat then pcall(self.deps.defeat, ko.id) end
  self:_release()
  self.mode, self.t = "idle", 0
  self.wx, self.wy, self.dx, self.dy = nil, nil, 0, 0
  self.cooldown, self.scan = 0, 0
  self.facing = nil
  self.fight, self.turn, self.wild, self.target = nil, nil, nil, nil
  self.popup, self.popupAge = nil, 0
  self.popupNext = nil
  self.drop = nil
  self.levelAge = nil
  self.hits = {}
  self.finisher = nil
  self.barRaise = 0
  self.marks = {}
  self.flash = 0
  self.away = false
  self.path, self.pathIdx = nil, 0
  -- the first idle tick checks at once whether it is still too tired to come out (a map
  -- change or save load resets this Battler): otherwise it popped out of the player and
  -- went straight back in
  self.checkRest = true
end

-- Frees the wild Pokemon this Battler had engaged (it goes back to wandering).
function OverworldBattle:_release()
  local e = self.target
  if e then
    e.engaged, e.owPose = false, nil
    if e.renderer then
      e.renderer.act = nil
      -- a knockout's tint / fade (lib/finisher_fx.lua) never outlives the fight
      if self.shadedBy == e then e.renderer.shade, e.renderer.alpha = nil, nil end
    end
  end
  self.shadedBy, self.koFades = nil, nil
  self:_clearAura()
  self.target = nil
end

--- Its job was taken away mid-skirmish (the Battler hotkey, the party menu): like running
--- from a battle. A wild Pokemon it was fighting runs off and disappears (`deps.runAway`;
--- no EXP), one it had already knocked out is simply gone (`deps.defeat`); one it was only
--- charging at is let go. Then everything resets.
function OverworldBattle:abandon()
  local e = self.target
  if e and (self.mode == "fight" or self.mode == "win") then
    local defeated = e.defeated or self.mode == "win"
    self.drop = nil -- nothing is bagged
    self:_release()
    if defeated then
      if self.deps.defeat then pcall(self.deps.defeat, e.id) end
    elseif self.deps.runAway then
      pcall(self.deps.runAway, e)
    end
  end
  self:reset()
end

--- Where it is drawn now, as an offset from its place behind the player (px), for the
--- run home when its job is taken away; nil while it is in its ball or already there.
function OverworldBattle:homeOffset()
  if self.away then return nil end
  local dx, dy = self.dx or 0, self.dy or 0
  if dx == 0 and dy == 0 then return nil end
  return dx, dy
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
  -- one fighter per wild Pokemon, kept on it (`owWild`): a second skirmish picks up its HP
  -- where the last left it, and walking into it starts the real battle with that HP and
  -- those IVs (lib/battle_trigger.lua onPlayerBumped)
  local wild = e.owWild or c.buildWild(e.species, e.level, e.personality, e.ivs)
  if not wild then
    e.noFight = true -- never try this one again
    return false
  end
  e.owWild = wild
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
    if self.popupAge >= cfg.popupTicks then
      self.popup = nil
      -- a second label waiting (a held item found after the EXP)
      local nxt = self.popupNext
      if nxt then
        self.popupNext = nil
        self.popup, self.popupAge = nxt.text, 0
        if nxt.sound and self.deps.playFound then pcall(self.deps.playFound) end
      end
    end
  end
  for i = #self.hits, 1, -1 do
    self.hits[i].age = self.hits[i].age + 1
    if self.hits[i].age >= math.max(HitEffect.LIFE, FinisherFx.HIT_TICKS) then table.remove(self.hits, i) end
  end
  for i = #self.marks, 1, -1 do
    local m = self.marks[i]
    m.age = m.age + 1
    if m.age >= FinisherFx.MARK_TICKS then table.remove(self.marks, i) end
  end
  if self.drop then self.drop.age = self.drop.age + 1 end
  if self.levelAge then
    self.levelAge = self.levelAge + 1
    if self.levelAge >= PartnerFx.LEVEL_TICKS then self.levelAge = nil end
  end
  local fin = self.finisher
  if fin then
    fin.age = fin.age + 1
    if fin.age >= FinisherFx.TICKS then self.finisher = nil end
  end
  self.dx, self.dy = self.wx - env.fpx, self.wy - env.fpy
  self:_tickBarRaise(env)

  -- a skirmish whose wild Pokemon vanished (the player started their own battle
  -- with it, it was despawned ...) is dropped
  local gone = self.target and (self.target.state ~= Config.STATE.AVAILABLE
    or (self.deps.alive and not self.deps.alive(self.target)))
  if gone then
    if self.mode == "chase" or self.mode == "fight" or self.mode == "win" then
      self.drop = nil -- nothing is bagged until it is picked up
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
  local checkRest = self.checkRest
  self.checkRest = false
  if (looking or checkRest) and exhaustedNow(env.mon, self.combatDeps) then
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
    -- the move's look while it is used (lib/finisher_fx.lua moveParticles): its type, and
    -- whether it makes contact (a lunge with a trail) or not (a projectile)
    local c = self.combatDeps
    local row = c.moveRow and ev.moveId and c.moveRow(ev.moveId)
    if row and not ev.skipped then
      self.turn.kind, self.turn.contact = FinisherFx.kindFor(row.type), row.contact ~= false
    end
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
    if ev.hit and attackerIsAlly and ev.result == "win" then
      -- the knockout: the finishing move's type effect instead of the plain impact; at 0 HP
      -- it can no longer be met (SpawnManager:entityAt skips it) while it sinks away
      e.defeated = true
      self:_startFinisher(ev, e)
      self.wildFlash = cfg.flashTicks
    elseif ev.hit then
      local defenderIsWild = attackerIsAlly
      local hx, hy = self.baseX, self.baseY
      if defenderIsWild then hx, hy = e.px, e.py end
      -- the plain impact, plus a small spark of the move's type sized by how well it
      -- landed, and the real battle's hit sound for it (lib/finisher_fx.lua)
      local c = self.combatDeps
      local row = c.moveRow and ev.moveId and c.moveRow(ev.moveId)
      local power = FinisherFx.powerFor(ev.effectiveness)
      self.hits[#self.hits + 1] = { x = hx, y = hy, age = 0,
        heavy = (ev.effectiveness or 1) > 1 or ev.critical or false,
        kind = FinisherFx.kindFor(row and row.type), power = power, crit = ev.critical == true }
      local se = FinisherFx.hitSound(ev.effectiveness)
      if se and self.deps.playSe then pcall(self.deps.playSe, se) end
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

  -- the attacker glows its move's colour over the wind-up
  local attackerR = attackerIsAlly and env.renderer or e.renderer
  local aura = turn.kind and FinisherFx.auraShade(turn.kind, turn.t, cfg.windup)
  if aura and attackerR and self.shadedBy ~= e then
    attackerR.shade, self.auraOn = aura, attackerR
  else
    self:_clearAura()
  end

  if turn.t >= cfg.turnTicks then self.turn = nil end
  return state(self, env, { moving = false, anim = allyAnim or "idle", animSpeed = cfg.attackSpeed,
    bounce = allyAnim ~= nil, flapTicks = 4 })
end

--- The knockout blow's effect: the finishing move's type (lib/finisher_fx.lua), on the
--- defeated Pokemon's tile; its tint goes on the Pokemon while it goes down.
function OverworldBattle:_startFinisher(ev, e)
  local c = self.combatDeps
  local row = c.moveRow and ev.moveId and c.moveRow(ev.moveId)
  local kind = FinisherFx.kindFor(row and row.type)
  self.finisher = { kind = kind, age = 0, x = e.px, y = e.py }
  self:_rollDrop(e)
  -- a mark left on the ground (never on water; one per tile, the newest)
  if FinisherFx.leavesMark(kind) and e.terrain ~= "water" then
    for i = #self.marks, 1, -1 do
      if self.marks[i].x == e.px and self.marks[i].y == e.py then table.remove(self.marks, i) end
    end
    self.marks[#self.marks + 1] = { kind = kind, age = 0, x = e.px, y = e.py, elevation = e.elevation }
  end
  local recipe = FinisherFx.recipe(kind)
  self.koFades = recipe.fade == true -- outlives the drawn effect: the whole win
  if recipe.se and self.deps.playSe then pcall(self.deps.playSe, recipe.se) end
  if e.renderer and recipe.shade then
    e.renderer.shade = recipe.shade
    self.shadedBy = e
  end
end

-- The knockout may shake loose the wild Pokemon's held item: `dropChance` % of knockouts,
-- then the game's own held-item roll for its species (most hold nothing). Only an item
-- that fits in the bag drops; it is bagged when the Battler picks it up (end of the win).
function OverworldBattle:_rollDrop(e)
  self.drop = nil
  local d = self.deps
  if not (d.heldItem and d.bagAdd) then return end
  local rng = d.rng or math.random
  if rng(1, 100) > (self.cfg.dropChance or 0) then return end
  local ok, item = pcall(d.heldItem, e.species)
  if not (ok and item) then return end
  if d.bagCanAdd and not d.bagCanAdd(item) then return end
  -- it lands a little toward the Battler, in front of the fallen Pokemon (on its own tile
  -- the sprite would hide the glint)
  local function toward(a, b) return (b > a and 1) or (b < a and -1) or 0 end
  local bx, by = self.baseX or e.px, self.baseY or e.py
  self.drop = { item = item, age = 0, elevation = e.elevation, sortY = e.py + 1,
    x = e.px + toward(e.px, bx) * 6, y = e.py + toward(e.py, by) * 6 + 3 }
end

-- Picks the dropped item up: into the bag, "Found X!" after the EXP label.
function OverworldBattle:_pickUpDrop()
  local drop = self.drop
  self.drop = nil
  if not drop then return end
  local ok, added = pcall(self.deps.bagAdd, drop.item, 1)
  if not (ok and added) then return end
  local name = self.deps.itemName and self.deps.itemName(drop.item) or "an item"
  self.popupNext = { text = "Found " .. tostring(name) .. "!", sound = true }
end

-- Takes the wind-up glow off whoever had it.
function OverworldBattle:_clearAura()
  local r = self.auraOn
  if r then
    if r ~= (self.shadedBy and self.shadedBy.renderer) then r.shade = nil end
    self.auraOn = nil
  end
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
  -- a Ghost-type knockout: it fades away where it stood instead of sinking
  if self.koFades and e.renderer then
    e.renderer.alpha = 1 - sink
    self.shadedBy = e
    self:_wildVisual("idle", 1, 0, 0, nil, nil)
  else
    self:_wildVisual("idle", 1, 0, 0, nil, sink)
  end
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
        self.levelAge = 0 -- a gold ring and sparkles round it (lib/partner_fx.lua)
        -- it cannot learn or evolve mid-walk: tell the owner, which asks the player
        if self.deps.levelUp then pcall(self.deps.levelUp, env.mon, result.fromLevel, result.toLevel) end
      end
    end
    local id = e.id
    self:_release()
    -- an overworld win counts toward a shiny chain like a battle won
    if self.deps.chainRecord then pcall(self.deps.chainRecord, e.species, "win") end
    if self.deps.defeat then self.deps.defeat(id) end
    self.fight, self.wild = nil, nil
    self.popup, self.popupAge = text, 0
    self:_pickUpDrop()
    if not self.popup and self.popupNext then
      -- no EXP label: the find shows at once
      self.popup, self.popupAge, self.popupNext = self.popupNext.text, 0, nil
      if self.deps.playFound then pcall(self.deps.playFound) end
    end
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

--- How high a health bar floats: just over the top of the art as drawn (`headLift`, the
--- highest point any Walk / Idle frame reaches, Species Sizes included -- what the emotes
--- and shiny sparkle use), `HEAD_GAP` px of air between. Pure; for testing.
local HEAD_GAP = 2
function OverworldBattle.barLift(r)
  local h = r and ((r.headLift and r:headLift()) or (r.visualHeight and r:visualHeight()))
  h = tonumber(h) or 20
  return math.max(10, math.min(96, h)) + HEAD_GAP
end

--- How many px the Battler's own health bar has to rise to clear the wild one's: two
--- fighters side by side at about the same height would draw their bars over each other,
--- so the Battler's goes on top, a row of air between. 0 when they do not touch.
--- (ax, ay) / (wx, wy) = the fighters' tiles (world px), lifts from `barLift`. Pure.
local BAR_W, BAR_H = HealthBar.WIDTH + 2, 5
function OverworldBattle.barRaise(ax, ay, aLift, wx, wy, wLift)
  if not (ax and ay and wx and wy) then return 0 end
  local aTop, wTop = ay - aLift, wy - wLift
  if math.abs(ax - wx) >= BAR_W or math.abs(aTop - wTop) > BAR_H then return 0 end
  return math.max(0, aTop - (wTop - BAR_H - 1))
end

-- Eases `barRaise` toward where the Battler's bar has to sit: quickly, but never a jump.
function OverworldBattle:_tickBarRaise(env)
  local e = self.target
  local goal = 0
  if self.fight and e and (self.mode == "fight" or self.mode == "chase") then
    goal = OverworldBattle.barRaise(self.wx, self.wy, OverworldBattle.barLift(env.renderer),
      e.px, e.py, OverworldBattle.barLift(e.renderer))
  end
  local cur = self.barRaise or 0
  local diff = goal - cur
  if math.abs(diff) <= 0.5 then
    self.barRaise = goal
  else
    self.barRaise = cur + diff * (self.cfg.barEase or 0.3)
  end
end

--- Health bars, hit effects and the "+EXP" label as field actors.
function OverworldBattle:collectActors(actors)
  local env = self.env
  if not env or not self.wx then return end
  local fighting = self.fight ~= nil and (self.mode == "fight" or self.mode == "chase")
  if fighting and self.target then
    local e = self.target
    actors[#actors + 1] = HealthBar.actor(self.wx, self.wy, self.shownAlly, env.mon.maxHp,
      OverworldBattle.barLift(env.renderer) + math.floor((self.barRaise or 0) + 0.5), 3, 1)
    actors[#actors + 1] = HealthBar.actor(e.px, e.py, self.shownWild, self.wild.maxHp,
      OverworldBattle.barLift(e.renderer), 3, 2)
  end
  if self.levelAge then
    local a = PartnerFx.actor(PartnerFx.levelUpParts(self.levelAge), self.wx, self.wy,
      OverworldBattle.barLift(env.renderer) - 2, 3, 1)
    if a then actors[#actors + 1] = a end
  end
  local drop = self.drop
  if drop and drop.age >= (self.cfg.dropShowAt or 0) then
    local a = ForageSparkle.actor(drop.x, drop.y, drop.age - (self.cfg.dropShowAt or 0), drop.elevation or 3, 7)
    a.sortY = math.max(a.sortY, drop.sortY or a.sortY) -- over the fallen Pokemon's feet
    actors[#actors + 1] = a
  end
  for i, m in ipairs(self.marks) do
    local a = FinisherFx.markActor(m.kind, m.age, m.x, m.y, m.elevation or 3, i)
    if a then actors[#actors + 1] = a end
  end
  local turn = self.turn
  if turn and turn.kind and self.target and self.mode == "fight" then
    local e = self.target
    local ax, ay, tx, ty = self.baseX, self.baseY, e.px, e.py
    if turn.ev.actor ~= "ally" then ax, ay, tx, ty = e.px, e.py, self.baseX, self.baseY end
    if ax and tx then
      local a = FinisherFx.moveActor(turn.kind, turn.contact, turn.t, self.cfg.windup, ax, ay,
        tx - ax, ty - ay, self.cfg.lunge, 3, 1)
      if a then actors[#actors + 1] = a end
    end
  end
  for i, h in ipairs(self.hits) do
    local a = HitEffect.actor(h.x, h.y, h.age, h.heavy, 3, i)
    if a then actors[#actors + 1] = a end
    local sp = h.kind and FinisherFx.hitActor(h.kind, h.age, h.x, h.y, h.power, h.crit, 3, i)
    if sp then actors[#actors + 1] = sp end
  end
  local fin = self.finisher
  if fin then
    local a = FinisherFx.actor(fin.kind, fin.age, fin.x, fin.y, 3, 0)
    if a then actors[#actors + 1] = a end
  end
end

return OverworldBattle
