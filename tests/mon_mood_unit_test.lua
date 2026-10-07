-- Run: lua tests/mon_mood_unit_test.lua
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

local MonMood = assert(loadfile("lib/mon_mood.lua"))(nil)

local function mon(t)
  local m = { hp = 100, maxHp = 100, friendship = 100 }
  for k, v in pairs(t or {}) do m[k] = v end
  return m
end

-- ------- statusOf: strings, the GBA bitfield, and the sleep counter
eq(MonMood.statusOf(mon()), nil, "no status")
for s, want in pairs({ PSN = "poison", TOX = "poison", TOXIC = "poison", POISON = "poison",
    BRN = "burn", PAR = "paralysis", FRZ = "freeze", SLP = "sleep" }) do
  eq(MonMood.statusOf(mon({ status = s })), want, "string status " .. s)
end
eq(MonMood.statusOf(mon({ status = "psn" })), "poison", "status strings are case-insensitive")
eq(MonMood.statusOf(mon({ status = 3 })), "sleep", "bitfield: sleep turns in the low 3 bits")
eq(MonMood.statusOf(mon({ status = 8 })), "poison", "bitfield: PSN = 8")
eq(MonMood.statusOf(mon({ status = 16 })), "burn", "bitfield: BRN = 16")
eq(MonMood.statusOf(mon({ status = 32 })), "freeze", "bitfield: FRZ = 32")
eq(MonMood.statusOf(mon({ status = 64 })), "paralysis", "bitfield: PAR = 64")
eq(MonMood.statusOf(mon({ status = 128 })), "poison", "bitfield: TOX = 128")
eq(MonMood.statusOf(mon({ status = 0, sleep = 2 })), "sleep", "a sleep counter alone means asleep")
eq(MonMood.statusOf(mon({ status = "", sleep = 0 })), nil, "empty status is none")
eq(MonMood.statusOf(nil), nil, "nil mon is none")

-- ------- hp / friendship readers
eq(MonMood.hpFraction(mon({ hp = 25 })), 0.25, "hp fraction")
eq(MonMood.hpFraction(mon({ hp = 500 })), 1, "hp fraction is clamped to 1")
eq(MonMood.hpFraction({}), nil, "no hp fields -> nil")
eq(MonMood.hpFraction(mon({ maxHp = 0 })), nil, "zero max hp -> nil")
eq(MonMood.friendshipOf(mon({ friendship = 300 })), 255, "friendship is clamped to 255")
eq(MonMood.friendshipOf({ happiness = 40 }), 40, "falls back to the happiness field")
eq(MonMood.friendshipOf({}), MonMood.DEFAULT_FRIENDSHIP, "no friendship field -> the default")

-- ------- friendship tiers (a healthy mon)
local function f(n) return MonMood.emotionFor(mon({ friendship = n })) end
eq(f(0), "Angry", "0 -> Angry")
eq(f(29), "Angry", "29 -> Angry")
eq(f(30), "Sad", "30 -> Sad")
eq(f(69), "Sad", "69 -> Sad")
eq(f(70), "Normal", "70 -> Normal")
eq(f(129), "Normal", "129 -> Normal")
eq(f(130), "Happy", "130 -> Happy")
eq(f(199), "Happy", "199 -> Happy")
eq(f(200), "Joyous", "200 -> Joyous (the engine's top friendship tier)")
eq(f(254), "Joyous", "254 -> Joyous")
eq(f(255), "Inspired", "255 -> Inspired")

-- ------- HP
local function hp(n, fr) return MonMood.emotionFor(mon({ hp = n, friendship = fr or 255 })) end
eq(hp(0), "Teary-Eyed", "fainted -> Teary-Eyed, whatever the friendship")
eq(hp(10), "Crying", "10% HP -> Crying")
eq(hp(11), "Pain", "11% HP -> Pain")
eq(hp(25), "Pain", "25% HP -> Pain")
eq(hp(26), "Worried", "26% HP -> Worried")
eq(hp(49), "Worried", "49% HP -> Worried")
eq(hp(50), "Happy", "50% HP at max friendship: too sore to beam -> Happy")
eq(hp(99, 255), "Happy", "99% HP at max friendship -> Happy")
eq(hp(100, 255), "Inspired", "full HP at max friendship -> Inspired")
eq(hp(60, 100), "Normal", "a mildly hurt mon of middling friendship keeps its tier")
eq(hp(60, 10), "Angry", "...and so does a hostile one")

-- ------- status beats low-ish HP, critical HP beats status
local function st(s, hpv) return MonMood.emotionFor(mon({ status = s, hp = hpv or 100, friendship = 255 })) end
eq(st("PSN"), "Pain", "poison -> Pain")
eq(st("TOX"), "Pain", "bad poison -> Pain")
eq(st("BRN"), "Shouting", "burn -> Shouting")
eq(st("PAR"), "Stunned", "paralysis -> Stunned")
eq(st("FRZ"), "Stunned", "freeze -> Stunned")
eq(st("SLP"), "Dizzy", "sleep -> Dizzy")
eq(st("BRN", 40), "Shouting", "a status outranks mere low HP")
eq(st("SLP", 10), "Crying", "critical HP outranks a status")
eq(st("PSN", 0), "Teary-Eyed", "fainted outranks everything")

-- ------- unusable input
eq(MonMood.emotionFor(nil), "Normal", "nil mon -> Normal")
eq(MonMood.emotionFor({}), "Normal", "a mon with no state fields -> the default friendship tier")
eq(MonMood.emotionFor({ friendship = 255 }), "Inspired", "no HP fields: friendship alone decides")

print("")
if failures > 0 then
  io.stderr:write(failures .. " failure(s)\n")
  os.exit(1)
end
print("mon_mood_unit_test: all passed")
