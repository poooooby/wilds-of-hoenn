-- Run: lua tests/follower_adapter_unit_test.lua
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

local fakeEngine = {}
local modules = {}
local optionStore = { follower = true }
local mod = {
  options = { get = function(_, k) return optionStore[k] end },
  read = function(_, rel)
    local f = io.open(rel, "rb")
    if not f then return nil end
    local data = f:read("*a")
    f:close()
    return data
  end,
}
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

local npc = nil
fakeEngine.followerCurrent = function() return npc end
fakeEngine.leadPartySpecies = function() return 999 end
fakeEngine.nationalFor = function(id) if id == 999 then return 252 end return nil end

local FollowerAdapter = V.require("follower_adapter")
local fa = FollowerAdapter.new(mod)

-- ------- shouldSpawn mirrors the Follower option
eq(fa:shouldSpawn(), true, "shouldSpawn true when the option is on")
optionStore.follower = false
eq(fa:shouldSpawn(), false, "shouldSpawn false when the option is off")
optionStore.follower = true

-- ------- tick() with no follower spawned does nothing
fa:tick()
eq(fa.renderer, nil, "no renderer built when no follower is spawned")

-- ------- tick() with a follower spawned sets npc.sprite to a renderer
-- for the current party lead's national dex
npc = { sprite = nil }
fa:tick()
check(npc.sprite ~= nil, "npc.sprite is set once a follower exists")
check(fa.renderer == npc.sprite, "FollowerAdapter tracks the renderer it installed")
eq(fa.renderer.dex, 252, "renderer uses the party lead's NATIONAL dex, not the internal id")

-- ------- tick() does not rebuild the renderer every call for the same lead
local same = npc.sprite
fa:tick()
check(npc.sprite == same, "same lead species -> renderer is not rebuilt")

-- ------- a lead species change rebuilds the renderer
fakeEngine.leadPartySpecies = function() return 1 end
fakeEngine.nationalFor = function(id) if id == 1 then return 1 end if id == 999 then return 252 end return nil end
fa:tick()
check(npc.sprite ~= same, "a new lead species rebuilds the renderer")
eq(fa.renderer.dex, 1, "renderer now uses the new lead's national dex")

-- ------- a Sprite Style change rebuilds the renderer even with the same
-- lead species, and takes effect without waiting for a species change
npc = { sprite = nil }
fakeEngine.leadPartySpecies = function() return 999 end
fakeEngine.nationalFor = function(id) if id == 999 then return 252 end return nil end
optionStore.sprite_style = "followers"
fa = FollowerAdapter.new(mod)
fa:tick()
eq(fa.renderer.style, "followers", "renderer starts in the followers style")
local beforeStyleSwitch = npc.sprite
optionStore.sprite_style = "pokemmo"
fa:tick()
check(npc.sprite ~= beforeStyleSwitch, "a style change rebuilds the renderer, same lead species")
eq(fa.renderer.style, "pokemmo", "renderer now uses the new style")
eq(fa.renderer.dex, 252, "dex is unchanged by a pure style switch")

-- ------- the follower vanishing (map transition) clears the tracked state
npc = nil
fa:tick()
eq(fa.leadSpecies, nil, "leadSpecies cleared once the follower is gone")

print("")
if failures > 0 then
  io.stderr:write(failures .. " failure(s)\n")
  os.exit(1)
end
print("follower_adapter_unit_test: all passed")
