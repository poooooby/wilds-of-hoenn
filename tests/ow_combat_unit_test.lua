-- Run: lua tests/ow_combat_unit_test.lua
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

local OwCombat = assert(loadfile("lib/ow_combat.lua"))()

-- a tiny move table: id -> { power, accuracy }
local MOVES = {
  [1] = { power = 40, accuracy = 100 }, -- Tackle
  [2] = { power = 90, accuracy = 100 }, -- the strong one
  [3] = { power = 0, accuracy = 100 },  -- a status move
  [4] = { power = 60, accuracy = 50 },  -- a shaky one
}
local rngValue = 0.99
local function newDeps(extra)
  local d = {
    rng = function() return rngValue end,
    battlerOf = function(mon) return { mon = mon } end,
    moveRow = function(id) return MOVES[id] end,
    moveNumber = function(m) return type(m) == "table" and m.id or m end,
    -- damage = power / 4 (the formula's own details are the engine's, not under test)
    moveDamage = function(_att, _def, id, _rng, _noCrit)
      return math.floor(MOVES[id].power / 4), { effectiveness = 1, critical = false }
    end,
    expGain = function(_species, level) return level * 10 end,
  }
  for k, v in pairs(extra or {}) do d[k] = v end
  return d
end
local function mon(t)
  local m = { species = 1, level = 10, hp = 50, maxHp = 50, speed = 30,
              moves = { 1, 2, 3 }, pp = { 5, 5, 5 } }
  for k, v in pairs(t or {}) do m[k] = v end
  return m
end

-- ------- usable moves: PP left and damage to deal
do
  local deps = newDeps()
  local usable = OwCombat.usableMoves(mon({ pp = { 5, 0, 5 } }), deps)
  eq(#usable, 1, "a move with no PP is not usable, nor a status move")
  eq(usable[1].id, 1, "...leaving the damaging move with PP")
  eq(#OwCombat.usableMoves(mon({ moves = { 3 }, pp = { 5 } }), deps), 0, "only status moves: nothing to attack with")
  eq(#OwCombat.usableMoves(mon({ moves = { { id = 2 } } , pp = { 5 } }), deps), 1, "moves may be tables")
end

-- ------- can it fight at all
do
  local deps = newDeps()
  check(OwCombat.canFight(mon(), deps, { resumeFrac = 0.25 }), "a healthy Pokemon can fight")
  check(not OwCombat.canFight(mon({ hp = 1 }), deps, { resumeFrac = 0.25 }), "at 1 HP it cannot")
  check(not OwCombat.canFight(mon({ hp = 12 }), deps, { resumeFrac = 0.25 }), "...nor below a quarter health")
  check(OwCombat.canFight(mon({ hp = 14 }), deps, { resumeFrac = 0.25 }), "...but can again once healed past it")
  check(not OwCombat.canFight(mon({ pp = { 0, 0, 0 } }), deps, {}), "with no PP it cannot")
  check(not OwCombat.canFight(nil, deps, {}), "no Pokemon cannot")
end

-- ------- who goes first
do
  local deps = newDeps()
  eq(OwCombat.new(mon({ speed = 50 }), mon({ speed = 10 }), deps).first, "ally", "the faster Battler goes first")
  eq(OwCombat.new(mon({ speed = 10 }), mon({ speed = 50 }), deps).first, "wild", "the faster wild Pokemon goes first")
  rngValue = 0.1
  eq(OwCombat.new(mon({ speed = 10 }), mon({ speed = 10 }), newDeps()).first, "ally", "a tie is a coin flip (low)")
  rngValue = 0.9
  eq(OwCombat.new(mon({ speed = 10 }), mon({ speed = 10 }), newDeps()).first, "wild", "...(high)")
  rngValue = 0.99
end

-- ------- a straight win: the Battler hits hardest, spends real PP, the wild mon falls
do
  local ally = mon({ speed = 50, hp = 200, maxHp = 200 })
  local wild = mon({ speed = 10, hp = 30, maxHp = 30, moves = { 1 }, pp = { 5 } })
  local f = OwCombat.new(ally, wild, newDeps())
  local e = f:turn()
  eq(e.actor, "ally", "the Battler moves first")
  eq(e.moveId, 2, "...with its strongest damaging move")
  check(e.hit, "it hits")
  eq(e.damage, 22, "damage is the engine's (90 / 4)")
  eq(wild.hp, 8, "the wild Pokemon lost that much")
  eq(ally.pp[2], 4, "one PP is spent on the REAL Pokemon")
  eq(ally.pp[1], 5, "...only on the move used")
  local e2 = f:turn()
  eq(e2.actor, "wild", "then the wild Pokemon acts")
  eq(e2.damage, 10, "...hurting the Battler (40 / 4)")
  eq(ally.hp, 190, "...whose real HP drops")
  local e3 = f:turn()
  eq(e3.result, "win", "the third action finishes it")
  eq(wild.hp, 0, "...at 0 HP")
  eq(f:outcome(), "win", "outcome says win")
  eq(f:turn(), nil, "no more turns once it is over")
end

-- ------- the Battler is never knocked out: it keeps 1 HP and is exhausted
do
  local ally = mon({ speed = 1, hp = 15, maxHp = 100 })
  local wild = mon({ speed = 99, hp = 500, maxHp = 500, moves = { 2 }, pp = { 9 } })
  local f = OwCombat.new(ally, wild, newDeps())
  local e = f:turn() -- the wild Pokemon hits for 22
  eq(e.actor, "wild", "the wild Pokemon opens")
  eq(ally.hp, 1, "the Battler is clamped at 1 HP, not 0")
  eq(e.damage, 14, "the damage reported is what it really lost")
  eq(e.result, "exhausted", "it is exhausted")
  eq(f:turn(), nil, "and the fight is over")
end

-- ------- a miss costs PP but not HP
do
  rngValue = 0.9 -- 90 >= 50 accuracy
  local ally = mon({ speed = 50, moves = { 4 }, pp = { 5 } })
  local wild = mon({ speed = 10, hp = 40, maxHp = 40, moves = { 1 }, pp = { 5 } })
  local f = OwCombat.new(ally, wild, newDeps())
  local e = f:turn()
  check(e.hit == false and e.damage == 0, "a 50% move misses on a high roll")
  eq(wild.hp, 40, "the target is untouched")
  eq(ally.pp[1], 4, "but the PP is spent")
  rngValue = 0.99
end

-- ------- running out of PP ends it
do
  local ally = mon({ speed = 50, moves = { 1 }, pp = { 1 } })
  local wild = mon({ speed = 10, hp = 500, maxHp = 500, moves = { 1 }, pp = { 99 } })
  local f = OwCombat.new(ally, wild, newDeps())
  f:turn() -- the last PP
  eq(ally.pp[1], 0, "its last PP is spent")
  local e = f:turn()
  eq(e.actor, "wild", "the wild Pokemon replies")
  eq(e.result, "exhausted", "...and with no PP left the Battler is exhausted")
end

-- ------- a wild Pokemon with nothing to attack with just stands there
do
  local ally = mon({ speed = 10, hp = 500, maxHp = 500 })
  local wild = mon({ speed = 50, hp = 10, maxHp = 10, moves = { 3 }, pp = { 5 } })
  local f = OwCombat.new(ally, wild, newDeps())
  local e = f:turn()
  check(e.skipped and e.actor == "wild", "no damaging move: the wild Pokemon's turn is skipped")
  eq(e.result, nil, "...and that does not end the fight")
  eq(f:turn().result, "win", "the Battler finishes it")
end

-- ------- EXP
do
  eq(OwCombat.expReward({ species = 5, level = 10 }, newDeps(), 0.5), 50, "half the engine's EXP value")
  eq(OwCombat.expReward({ species = 5, level = 1 }, newDeps(), 0.01), 1, "never less than 1 for a real value")
  eq(OwCombat.expReward({ species = 5, level = 10 }, newDeps({ expGain = function() return 0 end }), 0.5), 0, "nothing when the engine gives none")
end

if failures > 0 then
  io.stderr:write(failures .. " failure(s)\n")
  os.exit(1)
end
print("ow_combat_unit_test: all passed")
