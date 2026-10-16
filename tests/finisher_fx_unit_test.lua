-- Run: lua tests/finisher_fx_unit_test.lua
-- lib/finisher_fx.lua: the Battler's knockout effects, one per type (Fairy included).
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

-- the Gen 3 type ids (battle/types.lua) + National Dex's Fairy (18)
local NAMES = { [0] = "NORMAL", "FIGHTING", "FLYING", "POISON", "GROUND", "ROCK", "BUG", "GHOST", "STEEL",
  "MYSTERY", "FIRE", "WATER", "GRASS", "ELECTRIC", "PSYCHIC", "ICE", "DRAGON", "DARK", "FAIRY" }
local sheetAsks = {}
local E = {
  typeName = function(t)
    if type(t) == "string" then return t:upper() end
    local n = NAMES[t]
    return (n and n ~= "MYSTERY") and n or "NORMAL"
  end,
  fieldEffectSheet = function(name) sheetAsks[#sheetAsks + 1] = name return nil end,
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
local FinisherFx = V.require("finisher_fx")
local PixelShapes = V.require("pixel_shapes")

-- every type has its own recipe
for id = 0, 18 do
  local name = NAMES[id]
  if name ~= "MYSTERY" then
    eq(FinisherFx.kindFor(id), name, "type " .. id .. " -> its own " .. name .. " finisher")
  end
end
eq(FinisherFx.kindFor(9), "NORMAL", "the ??? type (MYSTERY) reads as NORMAL")
eq(FinisherFx.kindFor("water"), "WATER", "a type NAME (the Game Boy games) works too")
eq(FinisherFx.kindFor("SOUND"), "NORMAL", "an unknown type -> NORMAL")
eq(FinisherFx.kindFor(nil), "NORMAL", "no type at all -> NORMAL")

-- the particles: pure, finite, only known shapes, over by TICKS
local everyKindDraws = true
for kind in pairs(FinisherFx.RECIPES) do
  local drew = false
  for age = 0, FinisherFx.TICKS - 1 do
    for _, p in ipairs(FinisherFx.particles(kind, age)) do
      drew = true
      if p[1] == "shape" then
        if not PixelShapes.get(p[2]) then
          check(false, kind .. " uses an unknown shape " .. tostring(p[2]))
        end
        for i = 3, 5 do
          if type(p[i]) ~= "number" or p[i] ~= p[i] or math.abs(p[i]) > 200 then
            check(false, kind .. " has a bad number at age " .. age)
          end
        end
      end
    end
  end
  if not drew then everyKindDraws = false check(false, kind .. " draws nothing without a sheet") end
end
check(everyKindDraws, "every finisher draws its code-drawn part with no engine sheet (the Game Boy games)")
-- nothing falls away from the Pokemon: every part stays within ~a tile below it (a strong
-- gravity once dropped Rock's rocks 50 px down, off the bottom of the view)
for kind in pairs(FinisherFx.RECIPES) do
  local low = -math.huge
  for age = 0, FinisherFx.TICKS - 1 do
    for _, p in ipairs(FinisherFx.particles(kind, age)) do
      if p[1] == "shape" and p[4] > low then low = p[4] end
    end
  end
  check(low <= 20, kind .. ": no part falls more than 20 px below the Pokemon (" .. math.floor(low) .. ")")
end
eq(#FinisherFx.particles("WATER", FinisherFx.TICKS), 0, "after TICKS: nothing")
local a1 = FinisherFx.particles("FIRE", 10)
local a2 = FinisherFx.particles("FIRE", 10)
check(#a1 == #a2 and a1[1][3] == a2[1][3], "particles are pure (same age, same parts)")

-- the engine sheets: frames advance, then end
eq(FinisherFx.sheetFrame("WATER", 0), 0, "the water splash starts on its first frame")
eq(FinisherFx.sheetFrame("WATER", 7), 1, "...and moves on")
eq(FinisherFx.sheetFrame("WATER", 200), nil, "...and ends")
eq(FinisherFx.sheetFrame("PSYCHIC", 0), nil, "a recipe without engine art has no sheet frame")

-- every finisher has its battle move sound
local soundsOk = true
for kind, r in pairs(FinisherFx.RECIPES) do
  if type(r.se) ~= "string" or not r.se:find("^SE_M_") then soundsOk = false check(false, kind .. " has no move sound") end
end
check(soundsOk, "every finisher has an engine move sound (SE_M_*)")
eq(FinisherFx.soundFor("WATER"), "SE_M_WATERFALL", "Water sounds like Waterfall")
eq(FinisherFx.soundFor("FAIRY"), "SE_M_CHARM", "Fairy sounds like Charm")
eq(FinisherFx.soundFor("SOUND"), FinisherFx.soundFor("NORMAL"), "an unknown kind sounds like NORMAL")

-- the look of a few
check(FinisherFx.recipe("GHOST").fade == true, "a Ghost knockout fades the Pokemon away")
check(FinisherFx.recipe("ICE").shade ~= nil, "an Ice knockout tints it icy")
check(FinisherFx.recipe("FAIRY").sheet ~= nil, "Fairy uses the engine's sparkle art where it has it")

-- the actor: built, drawn headless without trouble, gone after TICKS
local a = FinisherFx.actor("WATER", 5, 32, 48, 3, 0)
check(a and a.kind == "ow_finisher_fx" and a.oamPriority == 1, "the actor is a plain field actor over the map")
eq(FinisherFx.actor("WATER", FinisherFx.TICKS, 0, 0), nil, "no actor once it is over")
local calls = 0
love = { graphics = setmetatable({ getColor = function() return 1, 1, 1, 1 end }, {
  __index = function() return function() calls = calls + 1 end end }) }
for kind in pairs(FinisherFx.RECIPES) do
  local ok, err = pcall(function() FinisherFx.actor(kind, 6, 32, 48).draw(nil, 0, 0) end)
  if not ok then check(false, kind .. " draw errors: " .. tostring(err)) end
end
check(calls > 0, "every finisher draws (pixel by pixel without image support)")
check(#sheetAsks > 0, "...asking the engine for its art")
love = nil

print("")
if failures > 0 then
  io.stderr:write(failures .. " failure(s)\n")
  os.exit(1)
end
print("finisher_fx_unit_test: all passed")
