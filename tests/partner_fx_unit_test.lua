-- Run: lua tests/partner_fx_unit_test.lua
-- lib/partner_fx.lua: the level-up flourish, evolve sparkles and type puffs on the partner.
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

local NAMES = { [0] = "NORMAL", "FIGHTING", "FLYING", "POISON", "GROUND", "ROCK", "BUG", "GHOST", "STEEL",
  "MYSTERY", "FIRE", "WATER", "GRASS", "ELECTRIC", "PSYCHIC", "ICE", "DRAGON", "DARK", "FAIRY" }
local TYPES = { [4] = { 10, 10 }, [16] = { 0, 2 }, [19] = { 0, 0 }, [35] = { 18, 18 } }
local E = {
  typeName = function(t) local n = NAMES[t] return (n and n ~= "MYSTERY") and n or "NORMAL" end,
  fieldEffectSheet = function() return nil end,
  speciesTypes = function(sp) local t = TYPES[sp] or { 0, 0 } return t[1], t[2] end,
}
local modules = {}
local V = {}
function V.require(name)
  if modules[name] ~= nil then return modules[name] end
  if name == "engine_patch" then modules[name] = E return E end
  local value = assert(loadfile("lib/" .. name .. ".lua"))(V)
  modules[name] = value
  return value
end
local PartnerFx = V.require("partner_fx")
local PixelShapes = V.require("pixel_shapes")

-- its type
eq(PartnerFx.kindFor(4), "FIRE", "a Fire type (Charmander) puffs Fire")
eq(PartnerFx.kindFor(16), "FLYING", "Normal / Flying (Pidgey) reads as Flying, not Normal")
eq(PartnerFx.kindFor(19), "NORMAL", "a pure Normal type stays Normal")
eq(PartnerFx.kindFor(35), "FAIRY", "Fairy (National Dex) too")

local function allKnown(parts)
  for _, p in ipairs(parts) do
    if p[1] == "shape" and not PixelShapes.get(p[2]) then return false end
  end
  return true
end

-- the level-up flourish
local any = false
for age = 0, PartnerFx.LEVEL_TICKS - 1 do
  local parts = PartnerFx.levelUpParts(age)
  if #parts > 0 then any = true end
  if not allKnown(parts) then check(false, "level-up: an unknown shape") end
end
check(any, "a level-up shows a ring and sparkles")
eq(#PartnerFx.levelUpParts(PartnerFx.LEVEL_TICKS), 0, "...and is over after LEVEL_TICKS")
local top = 0
for age = 0, PartnerFx.LEVEL_TICKS - 1 do
  for _, p in ipairs(PartnerFx.levelUpParts(age)) do if p[1] == "shape" and p[4] < top then top = p[4] end end
end
check(top < -10, "...its sparkles rise up past the head")

-- evolve sparkles: they come back every period
check(#PartnerFx.evolveParts(5) > 0, "ready to evolve: sparkles drift up")
check(#PartnerFx.evolveParts(PartnerFx.EVOLVE_PERIOD + 5) > 0, "...again and again")
check(#PartnerFx.evolveParts(PartnerFx.EVOLVE_PERIOD - 5) == 0, "...with a rest in between")
check(allKnown(PartnerFx.evolveParts(20)), "...known shapes")

-- type puffs, every type
for kind in pairs(V.require("finisher_fx").SPARKS) do
  local drew = false
  for age = 0, 29 do
    local parts = PartnerFx.typePuffParts(kind, age)
    if #parts > 0 then drew = true end
    if not allKnown(parts) then check(false, kind .. " puff: unknown shape") end
  end
  check(drew, kind .. " has a puff")
end
check(#PartnerFx.typePuffParts("FIRE", 40, 45) == 0, "a puff, then a rest until the next")
local ember = PartnerFx.typePuffParts("FIRE", 10)[1]
eq(ember and ember[2], "ember", "a Fire partner puffs embers")

-- the actor
eq(PartnerFx.actor({}, 0, 0, 16), nil, "nothing to draw: no actor")
local a = PartnerFx.actor(PartnerFx.levelUpParts(10), 32, 48, 20, 3, 1)
check(a and a.kind == "ow_partner_fx" and a.oamPriority == 1, "a field actor over the map")
love = { graphics = setmetatable({ getColor = function() return 1, 1, 1, 1 end }, {
  __index = function() return function() end end }) }
check(pcall(a.draw, a, 0, 0), "...that draws")
love = nil

print("")
if failures > 0 then
  io.stderr:write(failures .. " failure(s)\n")
  os.exit(1)
end
print("partner_fx_unit_test: all passed")
