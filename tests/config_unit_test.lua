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
-- hermetic: whether PMDCollab art is "installed" does not depend on a local bake
local function newMod(pmdInstalled)
  return {
  id = "wilds_of_hoenn",
  path = ".",
  read = function(_, rel)
    if rel == "assets/pmd/index.json" then return pmdInstalled and "{}" or nil end
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
end
local mod = newMod(true)
local modNoPmd = newMod(false)

-- ------- defaults with nothing saved
eq(Config.enabled(mod), true, "enabled defaults true")
eq(Config.spriteStyle(mod), "pmd", "sprite_style defaults to pmd when PMDCollab art is installed")
eq(Config.spriteStyle(modNoPmd), "pokemmo", "...and to HGSS / PokeMMO when it is not (the HGSS-only release)")
eq(Config.classicEncEnabled(mod), true, "classic_enc defaults true")
eq(Config.silhouetteMode(mod), "off", "silhouette defaults off")
eq(Config.followerEnabled(mod), true, "a companion is always allowed (no Follower option any more)")

-- ------- saved values override defaults
optionStore.enabled = false
eq(Config.enabled(mod), false, "enabled reads saved false")
optionStore.sprite_style = "pokemmo"
eq(Config.spriteStyle(mod), "pokemmo", "sprite_style reads saved pokemmo")
optionStore.sprite_style = "pmd"
eq(Config.spriteStyle(mod), "pmd", "sprite_style reads saved pmd (PMDCollab)")
optionStore.sprite_style = "pokemmo"
optionStore.classic_enc = false
eq(Config.classicEncEnabled(mod), false, "classic_enc reads saved false")
optionStore.wild_silhouettes = "all"
eq(Config.silhouetteMode(mod), "all", "silhouette reads saved all")
optionStore.follower = false -- a stale saved value from before the option was removed
eq(Config.followerEnabled(mod), true, "...is ignored")

-- ------- invalid saved choice values fall back to default rather than
-- propagating garbage into renderer/spawn logic
optionStore.wild_silhouettes = "bogus"
eq(Config.silhouetteMode(mod), "off", "silhouette rejects invalid value")
optionStore.sprite_style = "bogus"
eq(Config.spriteStyle(mod), "pmd", "sprite_style rejects invalid value")
optionStore.sprite_style = "followers"
eq(Config.spriteStyle(mod), "pmd", "a saved 'followers' (Kanto-only style, removed here) falls back to the default")

-- ------- PMDCollab is optional: the HGSS-only release ships no PMD art
check(Config.hasPmdArt(mod), "hasPmdArt true when assets/pmd/index.json is installed")
check(not Config.hasPmdArt(modNoPmd), "hasPmdArt false without it")
check(not Config.hasPmdArt(nil) and not Config.hasPmdArt({}), "hasPmdArt is false for a missing mod / no read")
optionStore = { sprite_style = "pmd" }
eq(Config.spriteStyle(modNoPmd), "pokemmo", "a saved 'pmd' in the HGSS-only release draws HGSS / PokeMMO")
eq(Config.spriteStyle(mod), "pmd", "...but stays pmd where the art exists")
optionStore = { sprite_style = "bogus" }
eq(Config.spriteStyle(modNoPmd), "pokemmo", "an invalid value falls back to the build's own default (HGSS-only)")
optionStore = {}
Config.defineOptions(modNoPmd)
local noPmdRow
for _, row in ipairs(definedSchema or {}) do if row.key == "sprite_style" then noPmdRow = row end end
check(noPmdRow ~= nil and #noPmdRow.choices == 1 and noPmdRow.choices[1][2] == "pokemmo",
  "the HGSS-only Sprite Style row offers only HGSS / PokeMMO")
eq(noPmdRow.default, "pokemmo", "...and defaults to it")
local noPmdPortraits = false
for _, row in ipairs(definedSchema or {}) do if row.key == "portraits" then noPmdPortraits = true end end
check(not noPmdPortraits, "the HGSS-only release has no Portraits option (no portrait art)")
check(not noPmdRow.description:find("PMDCollab", 1, true), "...and its description does not mention PMDCollab")
Config.defineOptions(mod)
local pmdRow
for _, row in ipairs(definedSchema or {}) do if row.key == "sprite_style" then pmdRow = row end end
check(pmdRow ~= nil and #pmdRow.choices == 2 and pmdRow.default == "pmd", "with PMD art the row offers both and defaults to pmd")
local portraitsRow
for _, row in ipairs(definedSchema or {}) do if row.key == "portraits" then portraitsRow = row end end
check(portraitsRow ~= nil and portraitsRow.type == "toggle" and portraitsRow.default == true, "with PMD art: a Portraits toggle, on by default")
check(Config.portraitsEnabled(mod), "Portraits: on when never set")
optionStore = { portraits = false }
check(not Config.portraitsEnabled(mod), "...off when switched off")
optionStore = {}

-- ------- options.lua loads and defines cleanly
optionStore = {}
Config.defineOptions(mod)
check(type(definedSchema) == "table", "defineOptions hands the Mod Manager a table")
local byKey = {}
for _, row in ipairs(definedSchema or {}) do
  byKey[row.key] = row
  check(#row.label <= 14, "label <=14: " .. tostring(row.label))
end
for _, key in ipairs({ "enabled", "sprite_style", "classic_enc", "wild_silhouettes" }) do
  check(byKey[key] ~= nil, "schema has " .. key)
  eq(byKey[key].default, Config.DEFAULTS[key], "schema default matches Config.DEFAULTS for " .. key)
end
check(byKey.follower == nil, "the old Follower key (removed in 1.2.0) stays out of the schema")
check(byKey.show_follower ~= nil and byKey.show_follower.default == true and Config.DEFAULTS.show_follower == true,
  "the Follower option has its own key, show_follower, on by default")
optionStore = { follower = false }
check(Config.followerOn(mod) == true, "an old saved follower = false does not hide the partner")
optionStore = { show_follower = false }
check(Config.followerOn(mod) == false, "show_follower = false keeps it in its ball")
optionStore = {}
-- the Battler hotkey (lib/role_hotkey.lua): a controller button and a keyboard key
check(byKey.role_pad ~= nil and byKey.role_pad.default == "off" and Config.DEFAULTS.role_pad == "off",
  "Battler: Pad -- off by default")
check(byKey.role_key ~= nil and byKey.role_key.default == "off" and Config.DEFAULTS.role_key == "off",
  "Battler: Key -- off by default")
local padValues, keyValues = {}, {}
for _, c in ipairs(byKey.role_pad.choices) do padValues[#padValues + 1] = c[2] end
for _, c in ipairs(byKey.role_key.choices) do keyValues[#keyValues + 1] = c[2] end
eq(table.concat(padValues, ","), "r,l,off", "...the pad offers R, L, OFF")
eq(table.concat(keyValues, ","), "e,q,r,off", "...the keyboard E, Q, R, OFF")
eq(Config.rolePad(mod), "off", "rolePad: OFF when never set")
eq(Config.roleKey(mod), "off", "roleKey: OFF when never set")
optionStore = { role_pad = "r", role_key = "q" }
eq(Config.rolePad(mod), "r", "rolePad: R")
eq(Config.roleKey(mod), "q", "roleKey: Q")
optionStore = { role_pad = "x", role_key = 5 }
eq(Config.rolePad(mod), "off", "a bad saved value reads as the default (pad)")
eq(Config.roleKey(mod), "off", "...and (key)")
optionStore = {}

print("")
if failures > 0 then
  io.stderr:write(failures .. " failure(s)\n")
  os.exit(1)
end
print("config_unit_test: all passed")
