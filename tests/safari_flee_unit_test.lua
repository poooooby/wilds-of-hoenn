-- Run: lua tests/safari_flee_unit_test.lua
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

local modules = {}
local V = { path = "." }
function V.require(name)
  if modules[name] ~= nil then return modules[name] end
  local value = assert(loadfile("lib/" .. name .. ".lua"))(V)
  modules[name] = value
  return value
end
local SF = V.require("safari_flee")

-- the bands reproduce FireRed's own Safari table (catch rate -> flee rate)
local REAL = {
  { "Nidoran F", 235, 50 }, { "Nidorina", 120, 75 }, { "Paras", 190, 50 }, { "Parasect", 75, 75 },
  { "Venonat", 190, 50 }, { "Psyduck", 190, 50 }, { "Poliwag", 255, 50 }, { "Slowpoke", 190, 50 },
  { "Doduo", 190, 50 }, { "Exeggcute", 90, 75 }, { "Rhyhorn", 120, 75 }, { "Chansey", 30, 125 },
  { "Kangaskhan", 45, 125 }, { "Goldeen", 225, 50 }, { "Seaking", 60, 75 }, { "Scyther", 45, 125 },
  { "Pinsir", 45, 125 }, { "Tauros", 45, 125 }, { "Dragonair", 45, 125 },
}
for _, r in ipairs(REAL) do eq(SF.rateFor(r[2]), r[3], r[1] .. ": the game's own rate from its catch rate") end

-- a species with its own rate keeps it; one without gets its band's
local rate, fitted = SF.fitted(100, 45)
check(rate == 100 and not fitted, "Dratini keeps its own 100")
rate, fitted = SF.fitted(0, 190)
check(rate == 50 and fitted, "Pikachu (catch 190, no Safari rate): 50")
rate, fitted = SF.fitted(nil, 45)
check(rate == 125 and fitted, "a National Dex species with no entry (catch 45): 125")
rate = SF.fitted(nil, nil)
eq(rate, 125, "nothing known: the rare band")

-- the engine's escape factor from it (battle/rules.lua)
eq(SF.escapeFactor(125), 9, "flee 125 -> escape factor 9")
eq(SF.escapeFactor(50), 3, "flee 50 -> 3")
eq(SF.escapeFactor(0), 2, "flee 0 -> the minimum 2 (why a stray species barely ran)")

if failures > 0 then
  io.stderr:write(failures .. " failure(s)\n")
  os.exit(1)
end
print("safari_flee_unit_test: all passed")
