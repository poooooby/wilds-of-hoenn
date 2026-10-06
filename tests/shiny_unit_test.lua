-- Run: lua tests/shiny_unit_test.lua
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

local engineIsShiny -- real bxor-based reference check, mirrors pokemon.lua:1397
local function realIsShiny(personality, otId, otSecretId)
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
  local hi = math.floor(personality / 65536) % 65536
  local lo = personality % 65536
  local value = xor16(xor16(otId, otSecretId), xor16(hi, lo))
  return value < 8
end
engineIsShiny = realIsShiny

local fakeEngine = {}
local modules = {}
local V = { path = "." }
function V.require(name)
  if modules[name] ~= nil then return modules[name] end
  if name == "engine_patch" then
    modules[name] = fakeEngine
    return fakeEngine
  end
  local chunk = assert(loadfile("lib/" .. name .. ".lua"))
  local value = chunk(V)
  modules[name] = value
  return value
end

fakeEngine.trainerIds = function() return { otId = 1000, otSecretId = 2000 } end
fakeEngine.isShiny = function(p, otId, otSecretId) return realIsShiny(p, otId, otSecretId) end
fakeEngine.genderOf = function(_species, _p) return 0 end

local Shiny = V.require("shiny")

-- ------- xor16 correctness against known values
eq(Shiny._xor16(0, 0), 0, "xor16(0,0)")
eq(Shiny._xor16(0xFFFF, 0xFFFF), 0, "xor16(ffff,ffff)")
eq(Shiny._xor16(0xFF00, 0x00FF), 0xFFFF, "xor16(ff00,00ff)")
eq(Shiny._xor16(0x1234, 0x5678), 0x444C, "xor16(1234,5678) matches a known value")

-- ------- boostedPersonality always returns a personality that is
-- genuinely shiny for the given trainer, and keeps nature + gender
math.randomseed(1)
for trial = 1, 20 do
  local otId, otSecretId = 1000 * trial, 2000 + trial
  local base = math.floor(math.random() * 4294967296)
  local wantGender = trial % 3 -- fake gender tag, just needs to round-trip
  local genderFn = function(p)
    -- deterministic pure function of p for this test -- real callers pass
    -- EnginePatch.genderOf(species, p)
    return (p + trial) % 3
  end
  -- Make `base` actually have gender wantGender for a fair nature/gender test.
  while genderFn(base) ~= wantGender do base = base + 1 end
  local p = Shiny.boostedPersonality(base, otId, otSecretId, genderFn, 256)
  check(p ~= nil, "boostedPersonality finds a match (trial " .. trial .. ")")
  if p then
    check(realIsShiny(p, otId, otSecretId), "result is genuinely shiny (trial " .. trial .. ")")
    eq(p % 25, base % 25, "nature preserved (trial " .. trial .. ")")
    eq(genderFn(p), wantGender, "gender preserved (trial " .. trial .. ")")
  end
end

-- ------- boostedPersonality with no genderFn only has to keep nature
math.randomseed(2)
local baseNoGender = math.floor(math.random() * 4294967296)
local p2 = Shiny.boostedPersonality(baseNoGender, 42, 99, nil, 256)
check(p2 ~= nil, "boostedPersonality works without a genderFn")
if p2 then
  check(realIsShiny(p2, 42, 99), "no-gender result is genuinely shiny")
  eq(p2 % 25, baseNoGender % 25, "no-gender result preserves nature")
end

-- ------- rollForEncounter: rate "off" never marks shiny
local Config = V.require("config")
local mod = { options = { get = function(_, k) if k == "shiny_rate" then return "off" end end } }
local enc = { species = 25, level = 10, personality = 1 }
Shiny.rollForEncounter(mod, enc)
eq(enc.shiny, false, "shiny_rate off never marks shiny")

-- ------- rollForEncounter: vanilla keeps whatever the engine's own check says
mod = { options = { get = function(_, k) if k == "shiny_rate" then return "vanilla" end end } }
fakeEngine.isShiny = function(_p, _otId, _otSecretId) return true end
enc = { species = 25, level = 10, personality = 1 }
Shiny.rollForEncounter(mod, enc)
eq(enc.shiny, true, "vanilla rate surfaces a genuinely-shiny roll")
eq(enc.personality, 1, "vanilla rate never changes personality")

-- ------- rollForEncounter: boosted turns a non-shiny roll into a shiny one
mod = { options = { get = function(_, k) if k == "shiny_rate" then return "boosted" end end } }
fakeEngine.isShiny = function(p, otId, otSecretId) return realIsShiny(p, otId, otSecretId) end
fakeEngine.trainerIds = function() return { otId = 7, otSecretId = 11 } end
math.randomseed(3)
enc = { species = 25, level = 10, personality = math.floor(math.random() * 4294967296) }
local originalNature = enc.personality % 25
Shiny.rollForEncounter(mod, enc)
eq(enc.shiny, true, "boosted rate turns a non-shiny roll shiny")
eq(enc.personality % 25, originalNature, "boosted rate preserves nature")
check(realIsShiny(enc.personality, 7, 11), "boosted result is genuinely shiny for the trainer")

print("")
if failures > 0 then
  io.stderr:write(failures .. " failure(s)\n")
  os.exit(1)
end
print("shiny_unit_test: all passed")
