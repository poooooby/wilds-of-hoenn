-- Run: lua tests/gb_friendship_unit_test.lua
-- lib/gb_friendship.lua: the mod-kept friendship on the Game Boy games.
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

local V = { require = function(name) return assert(loadfile("lib/" .. name .. ".lua"))(V) end }
local GbFriendship = assert(loadfile("lib/gb_friendship.lua"))(V)

local saved = {}
local mod = { save = {
  get = function(_, k) return saved[k] end,
  set = function(_, k, v) saved[k] = v end,
} }
local gameSave = {}
local store = GbFriendship.new(mod, function() return gameSave end)

local mon = { species = "CHARMANDER", dvs = { attack = 12, defense = 3, speed = 15, special = 7 } }
local other = { species = "CHARMANDER", dvs = { attack = 12, defense = 3, speed = 15, special = 8 } }

-- seeding, keys, persistence
eq(store:valueOf(mon), 70, "a new mon seeds at 70")
eq(mon.happiness, 70, "...mirrored onto the mon (lib/mon_mood.lua reads it)")
check(GbFriendship.keyOf(mon) ~= GbFriendship.keyOf(other), "different DVs, different keys")
eq(store:set(mon, 200), 200, "set writes through")
eq(store:set(mon, 999), 255, "...clamped high")
eq(store:set(mon, -5), 0, "...and low")
store:set(mon, 120)
store:reset()
eq(store:valueOf(mon), 120, "a reset re-reads the persisted value")
eq(store:valueOf(other), 70, "the other mon keeps its own")

-- walking
store:set(mon, 100)
for _ = 1, GbFriendship.STEP_EVERY - 1 do store:onStep(mon) end
eq(store:valueOf(mon), 100, "no gain before STEP_EVERY steps")
store:onStep(mon)
eq(store:valueOf(mon), 101, "one point every STEP_EVERY steps walked")
store:set(mon, 255)
for _ = 1, GbFriendship.STEP_EVERY do store:onStep(mon) end
eq(store:valueOf(mon), 255, "never past 255")

-- Yellow's starter Pikachu reads and writes the game's own happiness byte
gameSave.pikachuHappiness = 90
local pika = { species = "PIKACHU", dvs = { attack = 1, defense = 1, speed = 1, special = 1 } }
eq(store:valueOf(pika), 90, "Yellow's Pikachu reads save.pikachuHappiness")
store:set(pika, 140)
eq(gameSave.pikachuHappiness, 140, "...and writes it back")
check(saved.gb_friendship == nil or saved.gb_friendship[GbFriendship.keyOf(pika)] == nil,
  "...never shadowed in the mod's own table")
local steps0 = store.steps
store:onStep(pika)
eq(store.steps, steps0, "walking gains are the engine's own for Yellow's Pikachu")
gameSave.pikachuHappiness = nil
eq(store:valueOf(pika), 70, "a Pikachu outside Yellow is an ordinary mon (seeds 70)")

print("")
if failures > 0 then
  io.stderr:write(failures .. " failure(s)\n")
  os.exit(1)
end
print("gb_friendship_unit_test: all passed")
