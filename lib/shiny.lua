-- Gen 3 shiny for visible wild spawns: SHINY RATE option.
--
-- The real check stays the engine's own (pokemon.lua:1397, exposed via
-- EnginePatch.isShiny): shinyValue = (otId ^ otSecretId) ^ (pHi ^ pLo) < 8,
-- against the LIVE SAVE's trainer id -- a wild Pokemon's shininess depends
-- on who would catch it, same as real hardware. Vanilla rate is whatever
-- rollSweetScent already drew (no reroll). Boosted does a constructive
-- search for a personality that both passes that same check AND keeps the
-- original nature and gender, rather than rerolling blind (which would
-- need ~8192 average tries against a 1/8192 chance).
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

--- Applies the SHINY RATE option to an already-generated encounter
--- (species, level, personality, ivs, roamer -- from
--- Encounters.rules().rollSweetScent). Mutates and returns `enc`. `enc.shiny`
--- is always set to true/false so callers never have to re-derive it.
function Shiny.rollForEncounter(mod, enc)
  if type(enc) ~= "table" or enc.personality == nil then return enc end
  local Config = V.require("config")
  local EnginePatch = V.require("engine_patch")
  local rate = Config.shinyRate(mod)
  if rate == "off" then
    enc.shiny = false
    return enc
  end
  local ids = EnginePatch.trainerIds() or { otId = 0, otSecretId = 0 }
  if EnginePatch.isShiny(enc.personality, ids.otId, ids.otSecretId) then
    enc.shiny = true
    return enc
  end
  if rate == "boosted" then
    local genderFn = function(p) return EnginePatch.genderOf(enc.species, p) end
    local p = Shiny.boostedPersonality(enc.personality, ids.otId, ids.otSecretId, genderFn)
    if p then
      enc.personality = p
      enc.shiny = true
      return enc
    end
  end
  enc.shiny = false
  return enc
end

return Shiny
