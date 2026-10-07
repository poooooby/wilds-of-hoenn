-- The rules of an overworld skirmish (lib/overworld_battle.lua is its stage).
--
-- A short, simple fight between a party Pokemon (the Battler) and a wild
-- overworld Pokemon, using the REAL moves, stats, types, damage formula and PP:
--   * each round both sides act once, the faster first (a tie is a coin flip);
--   * the Battler picks the move that hurts most (PP > 0, damaging moves only);
--     the wild Pokemon picks any usable damaging move at random;
--   * a move can miss (its accuracy); damage comes from the engine's formula;
--   * every use costs 1 PP, on the REAL party Pokemon's PP -- it stays spent;
--   * the Battler is never knocked out: damage is clamped so it keeps 1 HP, and
--     at 1 HP (or with no usable attack left) it is "exhausted" and the fight
--     ends; the wild Pokemon loses real HP and is defeated at 0.
-- Pure: every engine fact comes through `deps` (lib/engine_patch.lua supplies
-- them): battlerOf(mon), moveRow(id), moveDamage(att, def, id, rng, noCrit),
-- moveNumber(m), rng() -> [0,1).
local OwCombat = {}
OwCombat.__index = OwCombat

local function moveIds(mon, deps)
  local ids = {}
  for i, m in ipairs(mon.moves or {}) do
    ids[i] = deps.moveNumber(m)
  end
  return ids
end

--- The moves a mon can use right now: { index, id, row } with PP left and
--- damage to deal.
function OwCombat.usableMoves(mon, deps)
  local out = {}
  local ids = moveIds(mon, deps)
  for i, id in ipairs(ids) do
    local pp = tonumber(mon.pp and mon.pp[i])
    if id and id > 0 and (pp == nil or pp > 0) then
      local row = deps.moveRow(id)
      if row and row.power > 0 then
        out[#out + 1] = { index = i, id = id, row = row }
      end
    end
  end
  return out
end

--- Can this Pokemon take part in a skirmish: healthy enough and able to attack.
function OwCombat.canFight(mon, deps, cfg)
  if type(mon) ~= "table" then return false end
  local hp, maxHp = tonumber(mon.hp) or 0, tonumber(mon.maxHp) or 1
  if hp <= math.max(1, math.floor(maxHp * ((cfg and cfg.resumeFrac) or 0.25))) then return false end
  return #OwCombat.usableMoves(mon, deps) > 0
end

--- EXP the Battler earns for defeating `wild`: the engine's value x `share`.
function OwCombat.expReward(wild, deps, share)
  local base = deps.expGain and deps.expGain(wild.species, wild.level) or 0
  if base <= 0 then return 0 end
  return math.max(1, math.floor(base * (share or 0.5)))
end

function OwCombat.new(ally, wild, deps)
  local self = setmetatable({ ally = ally, wild = wild, deps = deps, result = nil, round = 0 }, OwCombat)
  self.allyB = deps.battlerOf(ally)
  self.wildB = deps.battlerOf(wild)
  local sa, sw = tonumber(ally.speed or ally.spe) or 0, tonumber(wild.speed or wild.spe) or 0
  if sa == sw then
    self.first = deps.rng() < 0.5 and "ally" or "wild"
  else
    self.first = sa > sw and "ally" or "wild"
  end
  self.nextActor = self.first
  return self
end

local function rolls(deps)
  return function(lo, hi)
    return lo + math.floor(deps.rng() * (hi - lo + 1))
  end
end

local function midRolls(lo, hi) return math.floor((lo + hi) / 2) end

-- the move the Battler / the wild Pokemon chooses (or nil)
function OwCombat:_choose(side)
  local deps = self.deps
  local mon = side == "ally" and self.ally or self.wild
  local usable = OwCombat.usableMoves(mon, deps)
  if #usable == 0 then return nil end
  if side == "wild" then
    return usable[math.floor(deps.rng() * #usable) + 1] or usable[1]
  end
  local best, bestDmg = usable[1], -1
  local att, def = self.allyB, self.wildB
  for _, m in ipairs(usable) do
    local dmg = deps.moveDamage(att, def, m.id, midRolls, true) or 0
    if dmg > bestDmg then best, bestDmg = m, dmg end
  end
  return best
end

--- Is the skirmish over: nil, "win" (the wild Pokemon fell) or "exhausted".
function OwCombat:outcome()
  return self.result
end

--- One side acts. Returns an event:
---   { actor = "ally"|"wild", moveId, moveIndex, hit, damage, critical,
---     effectiveness, allyHp, wildHp, result }
--- `skipped = true` when the side had nothing to attack with.
function OwCombat:turn()
  if self.result then return nil end
  local deps = self.deps
  local side = self.nextActor
  self.nextActor = side == "ally" and "wild" or "ally"
  if side == self.first then self.round = self.round + 1 end

  local attackerMon = side == "ally" and self.ally or self.wild
  local defenderMon = side == "ally" and self.wild or self.ally
  local att = side == "ally" and self.allyB or self.wildB
  local def = side == "ally" and self.wildB or self.allyB
  local event = { actor = side }

  local move = self:_choose(side)
  if not move then
    event.skipped = true
    if side == "ally" then self.result = "exhausted" end
  else
    event.moveId, event.moveIndex = move.id, move.index
    -- PP is spent whether or not the move lands
    if attackerMon.pp and attackerMon.pp[move.index] then
      attackerMon.pp[move.index] = math.max(0, attackerMon.pp[move.index] - 1)
    end
    local acc = move.row.accuracy
    local hit = acc <= 0 or deps.rng() * 100 < acc
    event.hit = hit
    if hit then
      local dmg, info = deps.moveDamage(att, def, move.id, rolls(deps), false)
      dmg = math.max(1, math.floor(tonumber(dmg) or 1))
      event.critical = info and info.critical or false
      event.effectiveness = info and info.effectiveness or 1
      if side == "ally" then
        defenderMon.hp = math.max(0, (tonumber(defenderMon.hp) or 0) - dmg)
        event.damage = dmg
      else
        -- the Battler is never knocked out: it keeps 1 HP
        local before = tonumber(defenderMon.hp) or 1
        defenderMon.hp = math.max(1, before - dmg)
        event.damage = before - defenderMon.hp
      end
    else
      event.damage = 0
    end
  end

  event.allyHp, event.wildHp = self.ally.hp, self.wild.hp
  if (tonumber(self.wild.hp) or 0) <= 0 then
    self.result = "win"
  elseif (tonumber(self.ally.hp) or 0) <= 1 then
    self.result = "exhausted"
  elseif side == "wild" and #OwCombat.usableMoves(self.ally, deps) == 0 then
    self.result = "exhausted"
  end
  event.result = self.result
  return event
end

return OwCombat
