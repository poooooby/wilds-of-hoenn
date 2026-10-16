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

-- ------- every hit: a small spark of the move's type, sized by how well it landed
eq(FinisherFx.powerFor(2), "super", "2x: super effective")
eq(FinisherFx.powerFor(4), "super", "4x too")
eq(FinisherFx.powerFor(1), "normal", "1x: normal")
eq(FinisherFx.powerFor(0.5), "weak", "0.5x: not very effective")
eq(FinisherFx.powerFor(0), "immune", "0x: no effect")
eq(FinisherFx.powerFor(nil), "normal", "unknown: normal")
eq(FinisherFx.hitSound(2), "SE_SUPER_EFFECTIVE", "the real battle's sounds: super effective")
eq(FinisherFx.hitSound(1), "SE_EFFECTIVE", "...normal")
eq(FinisherFx.hitSound(0.25), "SE_NOT_EFFECTIVE", "...not very effective")
eq(FinisherFx.hitSound(0), nil, "...and none for no effect")
local function count(parts, what)
  local n = 0
  for _, p in ipairs(parts) do if p[1] == what then n = n + 1 end end
  return n
end
local sparksOk = true
for kind in pairs(FinisherFx.RECIPES) do
  check(FinisherFx.SPARKS[kind] ~= nil, kind .. " has its own hit spark")
  for _, power in ipairs({ "super", "normal", "weak", "immune" }) do
    local drew = false
    for age = 0, FinisherFx.HIT_TICKS - 1 do
      for _, p in ipairs(FinisherFx.hitParticles(kind, age, power, age % 2 == 0)) do
        drew = true
        if p[1] == "shape" then
          if not PixelShapes.get(p[2]) then sparksOk = false check(false, kind .. " spark: unknown shape " .. p[2]) end
          if math.abs(p[3]) > 40 or math.abs(p[4]) > 30 then sparksOk = false check(false, kind .. " spark flies too far") end
        end
      end
    end
    if not drew then sparksOk = false check(false, kind .. " " .. power .. " hit draws nothing") end
  end
end
check(sparksOk, "every type's spark draws at every power, small and near the Pokemon")
local function shapesAt(kind, power, crit)
  local n = 0
  for age = 0, FinisherFx.HIT_TICKS - 1 do n = n + count(FinisherFx.hitParticles(kind, age, power, crit), "shape") end
  return n
end
check(shapesAt("WATER", "super") > shapesAt("WATER", "normal"), "a super-effective hit throws more")
check(shapesAt("WATER", "normal") > shapesAt("WATER", "weak"), "...a not-very-effective one fewer")
local weakPart
for _, p in ipairs(FinisherFx.hitParticles("FIRE", 4, "weak")) do if p[1] == "shape" then weakPart = p end end
check(weakPart and weakPart[7] ~= nil, "...greyed out")
local immuneShapes = {}
for _, p in ipairs(FinisherFx.hitParticles("FIRE", 4, "immune")) do if p[1] == "shape" then immuneShapes[p[2]] = true end end
check(not immuneShapes.ember and immuneShapes.dust, "no effect: just a grey puff, none of the type")
local critStar = false
for _, p in ipairs(FinisherFx.hitParticles("WATER", 2, "normal", true)) do if p[2] == "star" then critStar = true end end
check(critStar, "a critical hit adds a star")
eq(#FinisherFx.hitParticles("WATER", FinisherFx.HIT_TICKS, "super"), 0, "a spark is over after HIT_TICKS")
check(FinisherFx.hitActor("WATER", 3, 0, 0, "super", true).kind == "ow_hit_spark", "the spark is a field actor")
eq(FinisherFx.hitActor("WATER", FinisherFx.HIT_TICKS, 0, 0, "super"), nil, "...gone when it is over")

-- ------- the attacker: gathering particles, a projectile or a lunge trail, a glow
do
  local W = 10
  local okMove = true
  for kind in pairs(FinisherFx.RECIPES) do
    for _, contact in ipairs({ true, false }) do
      for t = 0, W do
        for _, p in ipairs(FinisherFx.moveParticles(kind, contact, t, W, 16, 0, 7)) do
          if p[1] == "shape" and not PixelShapes.get(p[2]) then okMove = false check(false, kind .. ": unknown shape " .. p[2]) end
          for i = 3, 5 do
            if p[1] == "shape" and (type(p[i]) ~= "number" or p[i] ~= p[i]) then okMove = false check(false, kind .. ": bad number") end
          end
        end
      end
    end
  end
  check(okMove, "every type's move effect uses known shapes and finite numbers, contact or not")
  local function far(contact, t)
    local best = 0
    for _, p in ipairs(FinisherFx.moveParticles("WATER", contact, t, W, 16, 0, 7)) do
      if p[1] == "shape" and p[3] > best then best = p[3] end
    end
    return best
  end
  check(far(false, W) >= 15, "a ranged move's projectile reaches the target as the blow lands")
  check(far(false, 2) < 14, "...and starts back at the attacker")
  check(far(true, W) <= 8, "a contact move throws nothing across: only its trail, behind the lunge")
  eq(#FinisherFx.moveParticles("WATER", false, W + 1, W, 16, 0, 7), 0, "nothing after the blow")
  local ring = false
  for _, p in ipairs(FinisherFx.moveParticles("PSYCHIC", false, W, W, 16, 0, 7)) do
    if p[1] == "ring" and p[7] and p[7] > 10 then ring = true end
  end
  check(ring, "a Psychic projectile is a ring flying over")
  eq(FinisherFx.auraShade("FIRE", 0, W), nil, "no glow before the wind-up begins")
  local mid, peak = FinisherFx.auraShade("FIRE", 5, W), FinisherFx.auraShade("FIRE", W, W)
  check(mid and peak and peak[3] < mid[3] and mid[3] < 1, "the attacker glows warmer toward the blow (Fire)")
  eq(FinisherFx.auraShade("FIRE", W + 7, W), nil, "...and is back to normal just after it")
  check(FinisherFx.moveActor("WATER", false, 3, W, 0, 0, 16, 0, 7).kind == "ow_move_fx", "it is a field actor")
  eq(FinisherFx.moveActor("WATER", false, W + 1, W, 0, 0, 16, 0, 7), nil, "...gone after the blow")
end

-- the actor: built, drawn headless without trouble, gone after TICKS
local a = FinisherFx.actor("WATER", 5, 32, 48, 3, 0)
check(a and a.kind == "ow_finisher_fx" and a.oamPriority == 1, "the actor is a plain field actor over the map")
eq(FinisherFx.actor("WATER", FinisherFx.TICKS, 0, 0), nil, "no actor once it is over")
local calls = 0
love = { graphics = setmetatable({ getColor = function() return 1, 1, 1, 1 end }, {
  __index = function() return function() calls = calls + 1 end end }) }
for kind in pairs(FinisherFx.RECIPES) do
  local ok, err = pcall(function()
    FinisherFx.actor(kind, 6, 32, 48).draw(nil, 0, 0)
    FinisherFx.hitActor(kind, 4, 32, 48, "weak", true).draw(nil, 0, 0)
    FinisherFx.moveActor(kind, false, 6, 10, 32, 48, 16, 0, 7).draw(nil, 0, 0)
    FinisherFx.moveActor(kind, true, 6, 10, 32, 48, 16, 0, 7).draw(nil, 0, 0)
  end)
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
