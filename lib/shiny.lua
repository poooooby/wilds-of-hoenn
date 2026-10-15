-- Gen 3 shiny for wild encounters, and the shiny chain's bonus.
--
-- The real check stays the engine's own (pokemon.lua:1397, exposed via
-- EnginePatch.isShiny): shinyValue = (otId ^ otSecretId) ^ (pHi ^ pLo) < 8,
-- against the LIVE SAVE's trainer id -- a wild Pokemon's shininess depends
-- on who would catch it, same as real hardware. An encounter the engine
-- already made shiny always stays shiny.
--
-- On top of that comes the shiny chain (Modern Spawns counts it, src/chain.lua
-- there; the idea is TTiN's and Untamed Tohjo's): an encounter of the chained
-- species gets `bonus.shiny` -- a chance that it is made shiny -- and
-- `bonus.perfectIvs` stats at 31. Making it shiny is a constructive search for
-- a personality that passes the engine's real check AND keeps the original
-- nature and gender (boostedPersonality), not a blind reroll against the
-- engine's 1/8192. Without Modern Spawns there is no bonus: native odds only.
local V = ...

local Shiny = {}

-- 16-bit xor without the `bit` library (LuaJIT-only): standalone tests run
-- under plain Lua 5.1, so this stays pure arithmetic. Inputs are masked to
-- 16 bits first so callers don't need to pre-clamp.
local function xor16(a, b)
  a, b = a % 65536, b % 65536
  local result, bitval = 0, 1
  for _ = 1, 16 do
    local abit, bbit = a % 2, b % 2
    if abit ~= bbit then result = result + bitval end
    a, b = (a - abit) / 2, (b - bbit) / 2
    bitval = bitval * 2
  end
  return result
end
Shiny._xor16 = xor16 -- exposed for the unit test

--- Constructs a personality value that is shiny for (otId, otSecretId) and
--- keeps `basePersonality`'s nature (p % 25) and, when `genderFn` is given,
--- its gender. `genderFn(personality)` should call the engine's
--- Pokemon.gender(species, personality) -- passed in rather than called
--- here so this function stays a pure, directly testable search.
---
--- For each of the 8 personality values that satisfy the shiny equation
--- (pHi ^ pLo == otId ^ otSecretId ^ shinyValue, shinyValue in 0..7), a
--- random low half is drawn and the high half solved for; at most
--- `maxAttempts` draws per shiny value before giving up. Returns nil only
--- if no match is found in the budget (astronomically unlikely with the
--- default budget: ~1/50 draws match nature+gender, so a few dozen easily
--- succeed).
function Shiny.boostedPersonality(basePersonality, otId, otSecretId, genderFn, maxAttempts)
  maxAttempts = maxAttempts or 64
  local nature = basePersonality % 25
  local wantGender = genderFn and genderFn(basePersonality) or nil
  local xorTarget = xor16(otId or 0, otSecretId or 0)
  for _ = 1, maxAttempts do
    for shinyValue = 0, 7 do
      local lo = math.random(0, 65535)
      local hi = xor16(lo, xor16(xorTarget, shinyValue))
      local p = hi * 65536 + lo
      if p % 25 == nature and (wantGender == nil or not genderFn or genderFn(p) == wantGender) then
        return p
      end
    end
  end
  return nil
end

Shiny.STATS = { "hp", "atk", "def", "spe", "spa", "spd" }

--- IVs rolled the way the engine's battle builder rolls a wild Pokemon's
--- (src/core/game3/battle/init.lua:205): two 15-bit draws, three stats each.
function Shiny.rollIvs(rng)
  rng = rng or math.random
  local a, b = rng(0, 32767), rng(0, 32767)
  return {
    hp = a % 32, atk = math.floor(a / 32) % 32, def = math.floor(a / 1024) % 32,
    spe = b % 32, spa = math.floor(b / 32) % 32, spd = math.floor(b / 1024) % 32,
  }
end

--- Gives `enc` `k` perfect stats (31) on random stats, the rest as they were
--- (or rolled now when the encounter carries none -- Emerald and FireRed
--- encounters do not; the battle builder uses the ones given). Pure but for
--- `rng` (math.random's shape). Returns `enc`.
function Shiny.ivFloor(enc, k, rng)
  k = math.min(#Shiny.STATS, math.floor(tonumber(k) or 0))
  if type(enc) ~= "table" or k <= 0 then return enc end
  rng = rng or math.random
  local ivs = {}
  for key, v in pairs(type(enc.ivs) == "table" and enc.ivs or Shiny.rollIvs(rng)) do ivs[key] = v end
  local order = {}
  for i, key in ipairs(Shiny.STATS) do order[i] = key end
  for i = #order, 2, -1 do
    local j = rng(1, i)
    order[i], order[j] = order[j], order[i]
  end
  for i = 1, k do ivs[order[i]] = 31 end
  enc.ivs = ivs
  return enc
end

--- Settles whether `enc` (species, level, personality ...) is shiny: the
--- engine's own answer, else the chain's chance (`bonus` from Modern Spawns'
--- chainBonus, nil = none), and applies the chain's perfect stats. Mutates and
--- returns `enc`; `enc.shiny` is always set to true / false.
function Shiny.rollForEncounter(enc, bonus, rng)
  if type(enc) ~= "table" then return enc end
  local EnginePatch = V.require("engine_patch")
  -- Gen 2: shininess is in the DVs the encounter rolled (lib/engine_gb.lua); no chain there
  if type(enc.dvs) == "table" and EnginePatch.shinyDvs then
    enc.shiny = EnginePatch.shinyDvs(enc.dvs) == true
    return enc
  end
  if enc.personality == nil then return enc end
  rng = rng or math.random
  local ids = EnginePatch.trainerIds() or { otId = 0, otSecretId = 0 }
  enc.shiny = EnginePatch.isShiny(enc.personality, ids.otId, ids.otSecretId) == true
  if type(bonus) ~= "table" then return enc end
  local chance = tonumber(bonus.shiny) or 0
  if not enc.shiny and chance > 0 and rng() < chance then
    local p = Shiny.boostedPersonality(enc.personality, ids.otId, ids.otSecretId,
      function(x) return EnginePatch.genderOf(enc.species, x) end)
    if p then enc.personality, enc.shiny = p, true end
  end
  return Shiny.ivFloor(enc, bonus.perfectIvs, rng)
end

return Shiny
