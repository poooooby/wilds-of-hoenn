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
  local b = newBattler()
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

if failures > 0 then
  io.stderr:write(failures .. " failure(s)\n")
  os.exit(1)
end
print("overworld_battle_unit_test: all passed")
