-- Run: lua tests/overworld_battle_unit_test.lua
package.path = "./?.lua;./?/init.lua;" .. package.path

local failures = 0
local function check(cond, msg)
  if not cond then
    failures = failures + 1
    io.stderr:write("FAIL: " .. tostring(msg) .. "\n")
  else
    print("ok  " .. tostring(msg))
  end
end
local function eq(a, b, msg)
  check(a == b, string.format("%s (got %s expected %s)", msg, tostring(a), tostring(b)))
end

local E = {}
E.fieldEffectSheet = function() return nil end
E.measureText = function() return 0 end
E.drawText = function() return 0 end
local modules = {}
local V = { path = "." }
function V.require(name)
  if modules[name] ~= nil then return modules[name] end
  if name == "engine_patch" then modules[name] = E return E end
  local value = assert(loadfile("lib/" .. name .. ".lua"))(V)
  modules[name] = value
  return value
end
local Config = V.require("config")
local OverworldBattle = V.require("overworld_battle")

-- ------- a little world: an open field; wild Pokemon are entities
local MOVES = { [1] = { power = 40, accuracy = 0 }, [2] = { power = 80, accuracy = 0 } }
local entities, defeated, cries = {}, {}, {}
local buildWild
local function newBattler(extra)
  local deps = {
    combat = {
      battlerOf = function(mon) return { mon = mon } end,
      moveRow = function(id) return MOVES[id] end,
      moveNumber = function(m) return m end,
      moveDamage = function(_a, _d, id) return math.floor(MOVES[id].power / 4), { effectiveness = 1 } end,
      expGain = function(_s, level) return level * 20 end,
      expApply = function(mon, amount)
        mon.exp = (mon.exp or 0) + amount
        return { fromLevel = 10, toLevel = mon.exp >= 100 and 11 or 10 }
      end,
      buildWild = function(species, level, personality) return buildWild(species, level, personality) end,
      rng = function() return 0.5 end,
    },
    targets = function()
      local out = {}
      for _, e in ipairs(entities) do
        if e.state == "available" and not e.engaged and not e.noFight then out[#out + 1] = e end
      end
      return out
    end,
    alive = function(e)
      for _, x in ipairs(entities) do if x == e then return true end end
      return false
    end,
    cellFree = function(x, y)
      if x < 0 or x > 40 or y < 0 or y > 40 then return false end
      for _, e in ipairs(entities) do if e.cellX == x and e.cellY == y then return false end end
      return true
    end,
    occupied = function(x, y)
      for _, e in ipairs(entities) do if e.cellX == x and e.cellY == y then return true end end
      return false
    end,
    defeat = function(id)
      defeated[#defeated + 1] = id
      for i, e in ipairs(entities) do if e.id == id then table.remove(entities, i) break end end
    end,
    playCry = function(species) cries[#cries + 1] = species end,
    rng = function() return 0.5 end,
  }
  for k, v in pairs(extra or {}) do deps[k] = v end
  return OverworldBattle.new(deps)
end
local function wildEntity(id, cx, cy)
  local e = { id = id, cellX = cx, cellY = cy, px = cx * 16, py = cy * 16, species = 100 + id, level = 8,
              personality = 7, state = "available", facing = "down",
              renderer = { isPmd = true, anims = {}, advanceAs = function(r, a) r.anims[#r.anims + 1] = a end } }
  entities[#entities + 1] = e
  return e
end
local function newMon(t)
  local m = { species = 252, level = 10, hp = 60, maxHp = 60, speed = 40, moves = { 2 }, pp = { 10 } }
  for k, v in pairs(t or {}) do m[k] = v end
  return m
end
local function env(mon, t)
  local e = { still = true, fx = 10, fy = 10, fpx = 160, fpy = 160, px = 11, py = 10, mon = mon, renderer = nil }
  for k, v in pairs(t or {}) do e[k] = v end
  return e
end
local function reset()
  entities, defeated, cries = {}, {}, {}
  buildWild = function(species, level, personality)
    return { species = species, level = level, personality = personality, hp = 30, maxHp = 30, speed = 10,
             moves = { 1 }, pp = { 10 }, attack = 1 }
  end
end
local function run(b, mon, ticks, t)
  local last, states = nil, {}
  for _ = 1, ticks do
    last = b:step(env(mon, t))
    states[#states + 1] = last
    if b.mode == "idle" and not b.target and #states > 5 and b.cooldown > 0 then break end
  end
  return last, states
end

-- ------- nothing to fight: it just stands with the player
do
  reset()
  local b = newBattler()
  local mon = newMon()
  for _ = 1, 60 do eq(b:step(env(mon)), nil, "no wild Pokemon: nothing to show") end
  check(not b:isBusy(), "...and it is not busy")
  eq(b:step({}), nil, "no Pokemon at all is harmless")
end

-- ------- a wild Pokemon too far from the player is left alone
do
  reset()
  wildEntity(1, 20, 10) -- 9 cells from the player
  local b = newBattler()
  for _ = 1, 100 do b:step(env(newMon())) end
  eq(b.mode, "idle", "a wild Pokemon farther than 3 cells from the PLAYER is ignored")
  check(not entities[1].engaged, "...and not engaged")
end

-- ------- nothing starts while the player or follower is moving
do
  reset()
  wildEntity(1, 13, 10)
  local b = newBattler()
  for _ = 1, 100 do b:step(env(newMon(), { still = false })) end
  eq(b.mode, "idle", "no fights while anything is moving")
end

-- ------- a full win
do
  reset()
  local wild = wildEntity(1, 13, 10) -- 2 cells from the player
  local chained = {}
  local b = newBattler({ chainRecord = function(species, result) chained[#chained + 1] = { species, result } end })
  local mon = newMon()
  local sawChase, sawFight, sawAttack, sawBusy = false, false, false, false
  local maxOffset, hitSeen, barsSeen = 0, false, false
  for _ = 1, 2500 do
    local s = b:step(env(mon))
    if b.mode == "chase" then sawChase = true end
    if b.mode == "fight" then sawFight = true end
    if s then
      if s.anim == "attack" then sawAttack = true end
      maxOffset = math.max(maxOffset, math.abs(s.dx), math.abs(s.dy))
    end
    if b:isBusy() then sawBusy = true end
    local actors = {}
    b:collectActors(actors)
    for _, a in ipairs(actors) do
      if a.kind == "ow_health_bar" then barsSeen = true end
      if a.kind == "ow_hit_effect" then hitSeen = true end
    end
    if #defeated > 0 and b.mode == "idle" then break end
  end
  check(sawChase, "it charged the wild Pokemon")
  check(sawFight, "...and fought it")
  check(sawAttack, "it played its attack animation")
  check(maxOffset >= 16, "it moved away from the player's side (offset " .. maxOffset .. ")")
  check(barsSeen, "health bars were shown")
  check(hitSeen, "hit effects were shown")
  eq(#defeated, 1, "the defeated wild Pokemon was removed")
  eq(defeated[1], 1, "...the right one")
  check(#chained == 1 and chained[1][1] == wild.species and chained[1][2] == "win",
    "the win counts toward a shiny chain (Modern Spawns)")
  eq(cries[1], wild.species, "...after it cried")
  check(wild.renderer.act ~= nil or wild.engaged == false, "its skirmish state is cleaned up")
  check(mon.pp[1] < 10, "the Battler's PP was spent")
  check(mon.exp and mon.exp > 0, "the Battler earned EXP")
  check(b.popup == nil or b.popup:find("EXP") or b.popup:find("Lv"), "...announced in a label")
  eq(b.mode, "idle", "it ended back in idle")
  check(not b:isBusy() or b.cooldown > 0, "...beside the player")
  check(sawBusy, "it was busy while away")
end

-- ------- a level gained is reported (the owner asks the player to learn / evolve)
do
  reset()
  wildEntity(1, 13, 10)
  local reported = {}
  local b = newBattler({ levelUp = function(m, from, to) reported[#reported + 1] = { m, from, to } end })
  local mon = newMon({ exp = 99 })
  for _ = 1, 2500 do
    b:step(env(mon))
    if #defeated > 0 and b.mode == "idle" then break end
  end
  eq(#reported, 1, "a level-up is reported once")
  eq(reported[1] and reported[1][1], mon, "...for the Battler's own Pokemon")
  eq(reported[1] and reported[1][2], 10, "...from the level it was")
  eq(reported[1] and reported[1][3], 11, "...to the level it reached")
end

-- ------- EXP is held while a move / evolution waits for the player
do
  reset()
  wildEntity(1, 13, 10)
  local frozen = true
  local b = newBattler({ expFrozen = function() return frozen end })
  local mon = newMon()
  for _ = 1, 2500 do
    b:step(env(mon))
    if #defeated > 0 and b.mode == "idle" then break end
  end
  eq(#defeated, 1, "the fight still happens")
  eq(mon.exp, nil, "but no EXP is given while one is waiting")
  check(b.popup == nil, "...and no EXP label shows")
  reset()
  wildEntity(1, 13, 10)
  frozen = false
  b = newBattler({ expFrozen = function() return frozen end })
  mon = newMon()
  for _ = 1, 2500 do
    b:step(env(mon))
    if #defeated > 0 and b.mode == "idle" then break end
  end
  check(mon.exp and mon.exp > 0, "once nothing waits, EXP flows again")
end

-- ------- an unbuildable fighter is never retried
do
  reset()
  local wild = wildEntity(1, 13, 10)
  buildWild = function() return nil end
  local b = newBattler()
  for _ = 1, 100 do b:step(env(newMon())) end
  check(wild.noFight, "a Pokemon it cannot build a fighter for is marked")
  eq(b.mode, "idle", "...and the Battler carries on")
end

-- ------- exhausted: runs back, cries, shrinks into the player, rests until healed
do
  reset()
  local wild = wildEntity(1, 13, 10)
  buildWild = function(species, level, personality)
    return { species = species, level = level, personality = personality, hp = 5000, maxHp = 5000,
             speed = 99, moves = { 2 }, pp = { 99 }, attack = 1 }
  end
  local b = newBattler()
  local mon = newMon({ hp = 40, maxHp = 60 })
  local sawAway, sawRetreat = false, false
  for _ = 1, 3000 do
    local s = b:step(env(mon))
    if b.mode == "retreat" then sawRetreat = true end
    if s and s.away then sawAway = true end
    if b.mode == "rest" then break end
  end
  check(sawRetreat, "an exhausted Battler runs back")
  eq(mon.hp, 1, "...left at exactly 1 HP")
  check(not wild.engaged, "the wild Pokemon was let go")
  check(wild.hp == nil and #defeated == 0, "...and is still there")
  eq(cries[#cries], 252, "the Battler cried")
  eq(b.mode, "rest", "it rests")
  check(b.away, "...inside the player (the adapter shrinks it)")
  check(sawAway, "away was reported")
  for _ = 1, 200 do
    local s = b:step(env(mon))
    check(s ~= nil and s.away, "it stays inside while hurt") ; if not (s and s.away) then break end
  end
  mon.hp = mon.maxHp -- healed
  mon.pp = { 10 }
  local grew = false
  for _ = 1, 200 do
    b:step(env(mon))
    if b.mode == "emerge" then grew = true end
    if b.mode == "idle" then break end
  end
  check(grew, "healed, it grows back out")
  eq(b.mode, "idle", "...and is ready again")
  check(not b.away, "no longer inside")
end

-- ------- a tired Battler stays in through a map change: the reset that comes with it does
-- not let it pop out (it rests again on the very first tick)
do
  reset()
  local b = newBattler()
  local mon = newMon({ hp = 1, maxHp = 60 })
  for _ = 1, 100 do b:step(env(mon)) end
  eq(b.mode, "rest", "1 HP: resting inside the player")
  b:reset() -- what a map change / save load does (follower_adapter mapChanged / resetBehaviors)
  local s = b:step(env(mon))
  check(s ~= nil and s.away, "the first tick after the reset: still inside (no pop out)")
  eq(b.mode, "rest", "...resting again at once")
end

-- ------- a Pokemon that cannot fight (no PP) never starts one, and rests
do
  reset()
  wildEntity(1, 13, 10)
  local b = newBattler()
  local mon = newMon({ pp = { 0 } })
  for _ = 1, 100 do b:step(env(mon)) end
  eq(b.mode, "rest", "out of PP it stays inside")
  check(not entities[1].engaged, "and starts no fight")
end

-- ------- the wild Pokemon vanishing mid-fight drops the fight
do
  reset()
  local wild = wildEntity(1, 13, 10)
  local b = newBattler()
  local mon = newMon()
  for _ = 1, 300 do
    b:step(env(mon))
    if b.mode == "fight" then break end
  end
  eq(b.mode, "fight", "a fight began")
  wild.state = "encounter_starting" -- the player stepped onto it: a real battle
  for _ = 1, 400 do
    b:step(env(mon))
    if b.mode == "idle" then break end
  end
  eq(b.mode, "idle", "it returned to idle")
  check(not wild.engaged, "...having let go of it")
  eq(#defeated, 0, "...and nothing was defeated")
end

-- ------- reset puts everything back
do
  reset()
  local wild = wildEntity(1, 13, 10)
  local b = newBattler()
  local mon = newMon()
  for _ = 1, 300 do
    b:step(env(mon))
    if b.mode == "fight" then break end
  end
  b:reset()
  eq(b.mode, "idle", "reset returns to idle")
  check(not wild.engaged, "...releasing the wild Pokemon")
  check(not b:isBusy(), "...and it is not busy")
end

-- ------- the real defaults carry every knob it reads
for _, k in ipairs({ "radius", "maxWalk", "scanEvery", "cooldown", "chaseSpeed", "walkMul", "windup",
  "turnTicks", "lunge", "flashTicks", "attackSpeed", "winPause", "sinkTicks", "cryPause", "recallTicks",
  "restCheck", "popupTicks", "expShare", "resumeFrac" }) do
  check(Config.OW_BATTLE[k] ~= nil, "Config.OW_BATTLE." .. k)
end
eq(Config.OW_BATTLE.radius, 3, "it fights within 3 tiles of the player")

-- ------- water: it swims out to a water spawn, and fights while the player surfs
do
  -- a lake: every cell with x >= 13 is water (not cellFree)
  local function landOnly(x, y)
    if x >= 13 or x < 0 or y < 0 or y > 40 then return false end
    for _, e in ipairs(entities) do if e.cellX == x and e.cellY == y then return false end end
    return true
  end
  local function water(x, y) return x >= 13 and x <= 40 and y >= 0 and y <= 40 end

  reset()
  local w = wildEntity(1, 14, 10) -- one cell out from the shore (x = 13 is water)
  local b = newBattler({ cellFree = landOnly })
  local e, path = b:_findTarget(env(newMon()))
  check(e == nil, "without swimming it cannot reach a spawn with water all round its sides")
  b = newBattler({ cellFree = landOnly, swimFree = water })
  e, path = b:_findTarget(env(newMon()))
  check(e == w and path ~= nil, "with swimFree it swims out to it")
  local last = path and path[#path]
  check(last and math.abs(last[1] - 14) + math.abs(last[2] - 10) == 1, "...to the cell beside it")

  -- the player surfing: the follower itself is on the water
  reset()
  w = wildEntity(1, 18, 10)
  b = newBattler({ cellFree = landOnly, swimFree = water })
  e = b:_findTarget(env(newMon(), { fx = 16, fy = 10, fpx = 256, fpy = 160, px = 17, py = 10 }))
  check(e == w, "surfing: it fights a water spawn from the water")
  b = newBattler({ cellFree = landOnly })
  e = b:_findTarget(env(newMon(), { fx = 16, fy = 10, fpx = 256, fpy = 160, px = 17, py = 10 }))
  check(e == nil, "...which the old land-only search never could (the inconsistency)")
end

-- ------- a wild Pokemon caught mid-step is planned for the cell it lands on
do
  reset()
  local w = wildEntity(1, 12, 12)
  w.moving, w.targetX, w.targetY = true, 12, 11
  local b = newBattler()
  local e, path = b:_findTarget(env(newMon()))
  check(e == w, "a moving wild Pokemon can be picked")
  local last = path and path[#path]
  check(last and math.abs(last[1] - 12) + math.abs(last[2] - 11) == 1, "...standing beside where it will stop")
  eq(OverworldBattle._restingCell(w), 12, "its resting cell is its destination (x)")
end

-- ------- the knockout blow: the finishing move's TYPE effect (lib/finisher_fx.lua)
do
  local NAMES = { [0] = "NORMAL", [7] = "GHOST", [11] = "WATER", [18] = "FAIRY" }
  E.typeName = function(t) return NAMES[t] or "NORMAL" end
  local played = {}
  local allyR
  local function fight(moveType, terrain)
    reset()
    played = {}
    MOVES[2].type = moveType
    local wild = wildEntity(1, 13, 10)
    wild.terrain = terrain or "land"
    local b = newBattler({ playSe = function(name) played[#played + 1] = name end })
    local mon = newMon()
    local log = { kinds = {}, hitKinds = {}, hitsAtKo = nil, finisherActor = false, alphaSeen = false, sinkSeen = false }
    allyR = {}
    for _ = 1, 2500 do
      b:step(env(mon, { renderer = allyR }))
      if b.finisher then
        log.kinds[b.finisher.kind] = true
        if not log.hitsAtKo then log.hitsAtKo = #b.hits end
        log.shade = log.shade or (wild.renderer.shade and true)
      end
      if b.mode == "win" then
        if wild.renderer.alpha and wild.renderer.alpha < 1 then log.alphaSeen = true end
        if wild.renderer.act and (wild.renderer.act.sink or 0) > 0 then log.sinkSeen = true end
      end
      local actors = {}
      b:collectActors(actors)
      for _, a in ipairs(actors) do
        if a.kind == "ow_finisher_fx" then log.finisherActor = true end
        if a.kind == "ow_hit_spark" then log.hitSpark = true end
      end
      for _, h in ipairs(b.hits) do if h.kind then log.hitKinds[h.kind] = h.power end end
      for _, a in ipairs(actors) do
        if a.kind == "ow_move_fx" then log.moveFx = true end
        if a.kind == "ow_ko_mark" then log.mark = true end
      end
      if b.turn and b.turn.ev.actor == "ally" and b.turn.t >= 3 and b.turn.t <= 10 then
        if allyR.shade then log.allyGlow = true end
      end
      if b.mode == "idle" and allyR.shade then log.glowLeft = true end
      if #defeated > 0 and b.mode == "idle" and not b.finisher then break end
    end
    log.b, log.wild = b, wild
    return log
  end

  local w = fight(11)
  check(w.kinds.WATER, "a Water move's knockout plays the WATER finisher")
  local moveSounds, hitSounds = {}, 0
  for _, name in ipairs(played) do
    if name:find("^SE_M_") then moveSounds[#moveSounds + 1] = name
    elseif name == "SE_EFFECTIVE" then hitSounds = hitSounds + 1 end
  end
  eq(#moveSounds, 1, "...with one move sound, on the knockout only")
  eq(moveSounds[1], V.require("finisher_fx").soundFor("WATER"), "...Water's move sound")
  eq(played[#played], moveSounds[1], "...the last sound of the fight")
  check(hitSounds >= 1, "every ordinary hit plays the battle's own hit sound (" .. hitSounds .. ")")
  eq(hitSounds + 1, #played, "...and nothing else makes a sound")
  eq(w.hitKinds.WATER, "normal", "an ordinary Water hit shows a Water spark, landed normally")
  check(w.hitSpark, "...drawn as a field actor")
  check(w.moveFx, "each move shows its type's effect round the attacker while it is used")
  check(w.allyGlow, "...and the Battler glows its colour over the wind-up")
  check(not w.glowLeft, "...a glow that never outlasts the fight")
  check(w.mark, "a Water knockout leaves a puddle where the Pokemon stood")
  eq(#w.b.marks, 1, "...one mark, kept after the fight")
  for _ = 1, V.require("finisher_fx").MARK_TICKS do w.b:step(env(newMon())) end
  eq(#w.b.marks, 0, "...until it fades")
  check(w.finisherActor, "...drawn as a field actor")
  check(w.hitsAtKo == 0 or w.hitsAtKo == 1, "...in place of the plain impact (no extra hit effect for the KO)")
  eq(#defeated, 1, "...and the wild Pokemon is still defeated and removed")
  check(w.sinkSeen, "...sinking into the ground as before")
  eq(w.b.finisher, nil, "the effect ends on its own")

  local f = fight(18)
  check(f.kinds.FAIRY, "a Fairy move (type 18, National Dex) plays the FAIRY finisher")
  eq(played[#played], V.require("finisher_fx").soundFor("FAIRY"), "...with Fairy's sound")
  check(f.shade, "...tinting the defeated Pokemon")
  eq(f.wild.renderer.shade, nil, "...a tint cleared once it is gone")

  local ps = fight(14)
  check(not ps.mark, "a Psychic knockout leaves no mark")
  local wet = fight(11, "water")
  check(wet.kinds.WATER and not wet.mark, "nor does a knockout on the water (it still plays its finisher)")

  local g = fight(7)
  check(g.kinds.GHOST, "a Ghost move plays the GHOST finisher")
  check(g.alphaSeen, "...the defeated Pokemon fades")
  check(not g.sinkSeen, "...instead of sinking")

  local n = fight(nil)
  check(n.kinds.NORMAL, "a move with no type reads as NORMAL")

  MOVES[2].type = nil
  E.typeName = nil
end

-- ------- health bars sit just over the head
do
  local tall = { headLift = function() return 40 end, visualHeight = function() return 60 end }
  eq(OverworldBattle.barLift(tall), 42, "a bar floats 2 px over the art's real top (headLift)")
  eq(OverworldBattle.barLift({ visualHeight = function() return 30 end }), 32,
    "...the visible height when the renderer has no headLift")
  eq(OverworldBattle.barLift({}), 22, "...20 px when it can tell neither")
  eq(OverworldBattle.barLift({ headLift = function() return 300 end }), 98, "a giant is capped")
  eq(OverworldBattle.barLift(nil), 22, "no renderer at all")
end

-- ------- side by side, the Battler's bar goes over the wild one's
do
  local R = OverworldBattle.barRaise
  eq(R(0, 0, 22, 16, 0, 22), 6, "equal heights side by side: up a bar and a row of air")
  eq(R(0, 0, 22, 32, 0, 22), 0, "two tiles apart they do not touch")
  eq(R(0, 0, 22, 0, 16, 22), 0, "the wild one a tile below: already clear")
  eq(R(0, 0, 22, 16, 0, 25), 9, "a slightly taller wild one: higher still")
  eq(R(0, 0, 40, 16, 0, 22), 0, "a much taller Battler is already above it")
  eq(R(nil, 0, 22, 16, 0, 22), 0, "nothing to compare")
end
do
  reset()
  wildEntity(1, 13, 10)
  local b = newBattler()
  local mon = newMon()
  local top, jump, prev, fought = 0, 0, 0, false
  for _ = 1, 2500 do
    b:step(env(mon))
    local r = b.barRaise or 0
    if r > top then top = r end
    if math.abs(r - prev) > jump then jump = math.abs(r - prev) end
    prev = r
    if b.mode == "fight" then fought = true end
    if fought and b.mode == "idle" then break end
  end
  check(fought, "a real skirmish ran")
  eq(top, 6, "side by side in a fight, the Battler's bar rose over the wild one's")
  check(jump < 3, "...smoothly, a little each tick (largest step " .. jump .. ")")
  eq(b.barRaise, 0, "...and settled back once the fight was over")
end

-- ------- a level-up shows a gold ring and sparkles round the Battler
do
  reset()
  wildEntity(1, 13, 10)
  local b = newBattler()
  local mon = newMon({ exp = 90 })
  local sawLevel, sawFx = false, false
  for _ = 1, 2500 do
    b:step(env(mon))
    if b.popup and b.popup:find("^Lv") then sawLevel = true end
    local actors = {}
    b:collectActors(actors)
    for _, a in ipairs(actors) do if a.kind == "ow_partner_fx" then sawFx = true end end
    if #defeated > 0 and b.mode == "idle" and not b.popup then break end
  end
  check(sawLevel, "the win levelled it up")
  check(sawFx, "...with the level-up flourish round it")
  eq(b.levelAge, nil, "...which ends on its own")
end

-- ------- a knockout can shake loose the wild Pokemon's real held item
do
  local function koWith(opts)
    reset()
    local wild = wildEntity(1, 13, 10)
    local bagged, sounds = {}, 0
    local b = newBattler({
      heldItem = function(sp) return opts.item end,
      bagCanAdd = function() return opts.fits ~= false end,
      bagAdd = function(id, n) bagged[#bagged + 1] = id return true end,
      itemName = function(id) return id == 139 and "ORAN BERRY" or nil end,
      playFound = function() sounds = sounds + 1 end,
      rng = function() return opts.roll or 1 end,
    })
    local mon = newMon()
    local glint, labels, dropAtWin = false, {}, false
    for _ = 1, 2500 do
      b:step(env(mon))
      if b.mode == "win" and b.drop then dropAtWin = true end
      local actors = {}
      b:collectActors(actors)
      for _, a in ipairs(actors) do if a.kind == "ow_forage_sparkle" then glint = true end end
      if b.popup and labels[#labels] ~= b.popup then labels[#labels + 1] = b.popup end
      if #defeated > 0 and b.mode == "idle" and not b.popup then break end
    end
    return { bagged = bagged, sounds = sounds, glint = glint, labels = labels, drop = dropAtWin }
  end
  local r = koWith({ item = 139 })
  eq(#r.bagged, 1, "a knockout that rolls the drop bags the species' held item once")
  eq(r.bagged[1], 139, "...that item")
  check(r.drop, "...lying on the ground while the Pokemon goes down")
  check(r.glint, "...glinting there like a Forager find")
  eq(r.labels[#r.labels], "Found ORAN BERRY!", "...then \"Found ORAN BERRY!\" after the EXP")
  check(#r.labels >= 2, "...the EXP label first (" .. table.concat(r.labels, " / ") .. ")")
  eq(r.sounds, 1, "...with the found sound")
  eq(#koWith({ item = nil }).bagged, 0, "a Pokemon holding nothing drops nothing")
  eq(#koWith({ item = 139, fits = false }).bagged, 0, "an item that will not fit in the bag is not dropped")
  eq(#koWith({ item = 139, roll = 26 }).bagged, 0, "most knockouts drop nothing (dropChance %)")
end

-- ------- a knockout marks it defeated; the job taken away mid-way is running from battle
do
  local function untilMode(b, mon, want, cap)
    for _ = 1, cap or 2500 do
      b:step(env(mon))
      if b.mode == want then return true end
    end
    return false
  end
  -- knocked out: defeated at once (it can no longer be walked into while it sinks)
  reset()
  local wild = wildEntity(1, 13, 10)
  local b = newBattler()
  local mon = newMon()
  check(untilMode(b, mon, "win"), "staged: a knockout")
  eq(wild.defeated, true, "the knockout marks the wild Pokemon defeated (0 HP)")
  -- ...and abandoning now just removes it, no run, no EXP
  local ran = {}
  b.deps.runAway = function(e) ran[#ran + 1] = e return true end
  b:abandon()
  eq(#defeated, 1, "job taken away while it sinks: it is simply gone")
  eq(#ran, 0, "...it does not run")
  eq(mon.exp, nil, "...and no EXP is given")
  eq(b.mode, "idle", "...the Battler resets")

  -- mid-fight: the wild Pokemon runs off (deps.runAway), nothing is defeated or earned
  reset()
  wild = wildEntity(1, 13, 10)
  b = newBattler()
  mon = newMon()
  ran = {}
  b.deps.runAway = function(e) ran[#ran + 1] = e return true end
  check(untilMode(b, mon, "fight"), "staged: a fight under way")
  for _ = 1, 30 do b:step(env(mon)) end
  check(b.mode == "fight", "...still fighting")
  b:abandon()
  eq(#ran, 1, "job taken away mid-fight: the wild Pokemon runs away")
  check(ran[1] == wild, "...the one it was fighting")
  eq(#defeated, 0, "...it is not counted as defeated")
  eq(wild.engaged, false, "...and is let go")
  eq(mon.exp, nil, "no EXP for a fight broken off")
  eq(b.mode, "idle", "the Battler resets")

  -- only charging at it (no blow yet): simply let go
  reset()
  wild = wildEntity(1, 13, 10)
  b = newBattler()
  ran = {}
  b.deps.runAway = function(e) ran[#ran + 1] = e return true end
  check(untilMode(b, newMon(), "chase"), "staged: charging")
  b:abandon()
  eq(#ran, 0, "job taken away while charging: no run-away")
  eq(wild.engaged, false, "...the wild Pokemon is let go")

  -- a reset (save load, map change) while one sinks: it is gone, never back to wandering
  reset()
  wild = wildEntity(1, 13, 10)
  b = newBattler()
  check(untilMode(b, newMon(), "win"), "staged: another knockout")
  b:reset()
  eq(#defeated, 1, "reset during a knockout removes the defeated Pokemon")
end

-- ------- one fighter per wild Pokemon: kept on it, so its damage carries over
do
  reset()
  local wild = wildEntity(1, 13, 10)
  local b = newBattler()
  local mon = newMon()
  local fought = false
  for _ = 1, 2500 do
    b:step(env(mon))
    if b.mode == "fight" and b.wild and b.wild.hp < b.wild.maxHp then fought = true break end
  end
  check(fought, "staged: it has taken a hit")
  check(wild.owWild ~= nil and wild.owWild == b.wild, "its fighter is kept on the wild Pokemon (owWild)")
  local hpLeft = wild.owWild.hp
  b:reset() -- the fight is dropped (a map change ...): the damage stays with it
  check(wild.owWild and wild.owWild.hp == hpLeft and hpLeft < wild.owWild.maxHp, "...its HP stays down (" .. hpLeft .. ")")
  local seen
  for _ = 1, 2500 do
    b:step(env(mon))
    if b.wild then seen = b.wild break end
  end
  check(seen == wild.owWild, "a second skirmish picks the same fighter up again")
end

-- ------- where it is out in the field, for the run home when its job is taken away
do
  reset()
  local b = newBattler()
  eq(b:homeOffset(), nil, "standing with the player: nothing to run back")
  b.dx, b.dy = 24, -8
  local x, y = b:homeOffset()
  check(x == 24 and y == -8, "out in the field: its offset from its place")
  b.away = true
  eq(b:homeOffset(), nil, "in its ball (resting): no run")
end

if failures > 0 then
  io.stderr:write(failures .. " failure(s)\n")
  os.exit(1)
end
print("overworld_battle_unit_test: all passed")
