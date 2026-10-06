-- Run: lua tests/config_unit_test.lua
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
  local chunk = assert(loadfile("lib/" .. name .. ".lua"))
  local value = chunk(V)
  modules[name] = value
  return value
end

local Config = V.require("config")

local optionStore = {}
local definedSchema = nil
local mod = {
  id = "wilds_of_hoenn",
  path = ".",
  read = function(_, rel)
    local f = io.open(rel, "rb")
    if not f then return nil end
    local data = f:read("*a")
    f:close()
    return data
  end,
  options = {
    define = function(_, schema) definedSchema = schema end,
    get = function(_, k) return optionStore[k] end,
  },
}

-- ------- defaults with nothing saved
eq(Config.enabled(mod), true, "enabled defaults true")
eq(Config.classicEncEnabled(mod), true, "classic_enc defaults true")
eq(Config.silhouetteMode(mod), "off", "silhouette defaults off")
eq(Config.shinyRate(mod), "vanilla", "shiny_rate defaults vanilla")
eq(Config.followerEnabled(mod), true, "follower defaults true")

-- ------- saved values override defaults
optionStore.enabled = false
eq(Config.enabled(mod), false, "enabled reads saved false")
optionStore.classic_enc = false
eq(Config.classicEncEnabled(mod), false, "classic_enc reads saved false")
optionStore.wild_silhouettes = "all"
eq(Config.silhouetteMode(mod), "all", "silhouette reads saved all")
optionStore.shiny_rate = "boosted"
eq(Config.shinyRate(mod), "boosted", "shiny_rate reads saved boosted")
optionStore.follower = false
eq(Config.followerEnabled(mod), false, "follower reads saved false")

-- ------- invalid saved choice values fall back to default rather than
-- propagating garbage into renderer/spawn logic
optionStore.wild_silhouettes = "bogus"
eq(Config.silhouetteMode(mod), "off", "silhouette rejects invalid value")
optionStore.shiny_rate = "bogus"
eq(Config.shinyRate(mod), "vanilla", "shiny_rate rejects invalid value")

-- ------- options.lua loads and defines cleanly
optionStore = {}
Config.defineOptions(mod)
check(type(definedSchema) == "table", "defineOptions hands the Mod Manager a table")
local byKey = {}
for _, row in ipairs(definedSchema or {}) do
  byKey[row.key] = row
  check(#row.label <= 14, "label <=14: " .. tostring(row.label))
end
for _, key in ipairs({ "enabled", "classic_enc", "wild_silhouettes", "shiny_rate", "follower" }) do
  check(byKey[key] ~= nil, "schema has " .. key)
  eq(byKey[key].default, Config.DEFAULTS[key], "schema default matches Config.DEFAULTS for " .. key)
end

print("")
if failures > 0 then
  io.stderr:write(failures .. " failure(s)\n")
  os.exit(1)
end
print("config_unit_test: all passed")
