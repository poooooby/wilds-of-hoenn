-- Run: lua tests/battle_trigger_unit_test.lua
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
local Config = V.require("config")

-- ------- fake spawn manager: just enough surface for BattleTrigger
local function fakeSpawnManager()
  return {
    game = { tag = "game" },
    entities = {
      [1] = {
        id = 1, species = 999, level = 12, personality = 42, ivs = { hp = 1 },
        roamer = false, moves = nil, state = Config.STATE.AVAILABLE,
      },
    },
    markEncounterStarting = function(self, id)
      if self.entities[id] then self.entities[id].state = Config.STATE.ENCOUNTER_STARTING end
    end,
    despawn = function(self, id) self.entities[id] = nil end,
  }
end

local BattleTrigger = V.require("battle_trigger")

-- ------- a successful start: marks the entity, calls startWild with the
-- EXACT mon (species/level/personality/ivs/roamer/moves), and only on
-- battle end does the entity get despawned.
local startCalls = {}
fakeEngine.startWild = function(game, enc, opts)
  startCalls[#startCalls + 1] = { game = game, enc = enc, opts = opts }
  return true
end

local sm = fakeSpawnManager()
local bt = BattleTrigger.new({}, sm, { warn = function() end })
check(not bt:isPending(), "not pending before any contact")
bt:onPlayerBumped(sm.entities[1])
check(bt:isPending(), "pending immediately after a successful start")
eq(sm.entities[1].state, Config.STATE.ENCOUNTER_STARTING, "entity marked encounter_starting")
eq(#startCalls, 1, "startWild called exactly once")
eq(startCalls[1].game, sm.game, "startWild got the spawn manager's live game reference")
eq(startCalls[1].enc.species, 999, "startWild got the entity's species")
eq(startCalls[1].enc.level, 12, "startWild got the entity's level")
eq(startCalls[1].enc.personality, 42, "startWild got the entity's personality")
check(startCalls[1].enc.ivs ~= nil, "startWild got the entity's ivs")
check(sm.entities[1] ~= nil, "entity is not despawned until the battle actually ends")

-- A second bump while pending must not start a second battle.
bt:onPlayerBumped(sm.entities[1])
eq(#startCalls, 1, "a second bump while pending starts no second battle")

-- The battle ends -> done() fires -> entity despawns, no longer pending.
startCalls[1].opts.done("win")
check(not bt:isPending(), "no longer pending once the battle's done callback fires")
check(sm.entities[1] == nil, "entity despawned once the battle actually ended")

-- ------- startWild failing (already in battle, mid-warp, ...): the
-- entity is NOT despawned and goes back to available so it can be bumped
-- again later; pending clears so a future contact can retry.
fakeEngine.startWild = function(_game, _enc, _opts) return false, "a battle is already running" end
sm = fakeSpawnManager()
bt = BattleTrigger.new({}, sm, { warn = function() end })
bt:onPlayerBumped(sm.entities[1])
check(not bt:isPending(), "a failed start never leaves pending set")
eq(sm.entities[1].state, Config.STATE.AVAILABLE, "a failed start reverts the entity to available")
check(sm.entities[1] ~= nil, "a failed start never despawns the entity")

print("")
if failures > 0 then
  io.stderr:write(failures .. " failure(s)\n")
  os.exit(1)
end
print("battle_trigger_unit_test: all passed")
