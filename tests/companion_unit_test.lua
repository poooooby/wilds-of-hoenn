-- Run: lua tests/companion_unit_test.lua
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

local Companion = assert(loadfile("lib/companion.lua"))()

local function newMod()
  local store = {}
  return {
    store = store,
    save = {
      get = function(_, key) return store[key] end,
      set = function(_, key, value) store[key] = value end,
    },
  }
end
local function mon(personality, t)
  local m = { personality = personality, species = 252, hp = 20, maxHp = 20 }
  for k, v in pairs(t or {}) do m[k] = v end
  return m
end

-- ------- nothing chosen: the lead healthy Pokemon follows (the old behaviour)
do
  local c = Companion.new(newMod())
  local party = { mon(1, { hp = 0 }), mon(2, { isEgg = true }), mon(3), mon(4) }
  local m, role = c:resolve(party)
  eq(m, party[3], "no choice: the first healthy, non-egg Pokemon")
  eq(role, "follow", "...following")
  local none, role2 = c:resolve({})
  eq(none, nil, "an empty party has no companion")
  eq(role2, "follow", "...and the role is still follow")
end

-- ------- choosing any party member and a role
do
  local mod = newMod()
  local c = Companion.new(mod)
  local party = { mon(10), mon(20), mon(30) }
  check(c:set(party[2], "battle"), "set returns true")
  local m, role = c:resolve(party)
  eq(m, party[2], "the chosen Pokemon is the companion, not the lead")
  eq(role, "battle", "with the chosen role")
  check(c:set(party[3], "forage"), "choosing another replaces the first")
  m, role = c:resolve(party)
  eq(m, party[3], "only one companion at a time")
  eq(role, "forage", "...with its own role")
end

-- ------- it survives reordering the party, and is saved with the save file
do
  local mod = newMod()
  local c = Companion.new(mod)
  local a, b, d = mon(10), mon(20), mon(30)
  c:set(b, "forage")
  local m = c:resolve({ d, a, b })
  eq(m, b, "found by personality after the party is reordered")
  local fresh = Companion.new(mod) -- a new session over the same save
  m = fresh:resolve({ a, b, d })
  eq(m, b, "the choice persists in mod.save")
  eq(select(2, fresh:resolve({ a, b, d })), "forage", "...with its role")
  c:reset()
  eq(c:resolve({ a, b, d }), b, "reset re-reads the saved choice")
end

-- ------- a companion that cannot be out falls back to the lead following
do
  local c = Companion.new(newMod())
  local lead, chosen = mon(1), mon(2)
  c:set(chosen, "battle")
  chosen.hp = 0
  local m, role = c:resolve({ lead, chosen })
  eq(m, lead, "a fainted companion is replaced by the lead")
  eq(role, "follow", "...following")
  chosen.hp = 5
  eq(select(2, c:resolve({ lead, chosen })), "battle", "and is back in its role once it can walk again")
  chosen.isEgg = true
  eq(c:resolve({ lead, chosen }), lead, "an egg is never a companion")
  eq(c:resolve({ lead }), lead, "a companion that left the party is replaced by the lead")
end

-- ------- bad input
do
  local c = Companion.new(newMod())
  check(not c:set(mon(1), "dance"), "an unknown role is refused")
  check(not c:set(nil, "follow"), "no Pokemon is refused")
  check(not c:set({ species = 1 }, "follow"), "a Pokemon without a personality is refused")
  eq(c:savedRole(mon(1)), nil, "nothing was saved")
  local noSave = Companion.new({})
  check(noSave:set(mon(5), "battle"), "without mod.save it still works for the session")
  eq(select(2, noSave:resolve({ mon(5) })), "battle", "...and remembers the role")
  local broken = newMod()
  broken.store["companion/state"] = { role = "nonsense", personality = 4 }
  eq(select(2, Companion.new(broken):resolve({ mon(4) })), "follow", "a corrupt saved role is ignored")
end

-- ------- recall: a saved role of its own, not one of the three jobs
do
  local m = newMod()
  local c = Companion.new(m)
  local mon5 = mon(5)
  check(c:set(mon5, "recall"), "recall is accepted")
  local who, role = c:resolve({ mon(4), mon5 })
  eq(who, mon5, "a recalled Pokemon is still the companion")
  eq(role, "recall", "...with the recall role")
  local c2 = Companion.new(m)
  eq(select(2, c2:resolve({ mon5 })), "recall", "a recall survives a save and load")
  eq(#Companion.ROLES, 3, "the jobs are still just follow / battle / forage")
end

if failures > 0 then
  io.stderr:write(failures .. " failure(s)\n")
  os.exit(1)
end
print("companion_unit_test: all passed")
