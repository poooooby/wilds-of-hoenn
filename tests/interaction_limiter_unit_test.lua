-- Run: lua tests/interaction_limiter_unit_test.lua
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

local Limiter = assert(loadfile("lib/interaction_limiter.lua"))(nil)

local CFG = {
  cooldown = { pet = 30, play = 45, talk = 15 },
  window = 600, maxGains = 6,
  abuseWindow = 45, abuseAttempts = 6,
  lockBase = 300, lockMax = 3600, strikeReset = 7200,
}

local clockNow = 1000
local function fresh(store)
  return Limiter.new({ cfg = CFG, clock = function() return clockNow end, store = store })
end

-- ------- a normal player: each action works, once per cooldown
local L = fresh()
check(L:attempt("pet").ok, "first Pet is granted")
local r = L:attempt("pet")
check(not r.ok and r.reason == "cooldown", "an immediate second Pet is on cooldown")
check(r.wait > 29 and r.wait <= 30, "...and reports how long to wait")
check(L:attempt("play").ok, "a different action has its own cooldown")
check(L:attempt("talk").ok, "...and so does the third")
clockNow = clockNow + 31
check(L:attempt("pet").ok, "Pet works again after its 30s cooldown")
check(not L:attempt("play").ok, "Play (45s) is still cooling down at +31s")

-- ------- the window budget
L = fresh()
clockNow = 5000
local granted = 0
for i = 1, 6 do
  if L:attempt(({ "pet", "play", "talk" })[(i - 1) % 3 + 1]).ok then granted = granted + 1 end
  clockNow = clockNow + 50 -- longer than any cooldown, longer than nothing else matters
end
eq(granted, 6, "six spaced interactions are all granted")
r = L:attempt("pet")
check(not r.ok and r.reason == "tired", "the 7th inside the window: tired of attention")
clockNow = clockNow + 700
check(L:attempt("pet").ok, "the budget refills once the window has passed")

-- ------- abuse: spamming locks the menu, escalating each time
L = fresh()
clockNow = 20000
L:attempt("pet") -- granted
local reasons = {}
for i = 1, 5 do
  clockNow = clockNow + 1
  local a = L:attempt("pet")
  reasons[#reasons + 1] = a.reason
  if i < 5 then check(not a.ok and a.reason == "cooldown", "spam attempt " .. i .. " is refused (cooldown)") end
end
r = L:attempt("pet") -- (never reached: the 6th selection already locked)
check(r.reason == "locked", "mashing the same action locks the menu")
local st = L:status()
check(st.locked and st.remaining > 290 and st.remaining <= 300, "the first lock is ~5 minutes")
eq(st.strikes, 1, "and counts as a strike")

-- locked: nothing is granted, even a different action, and time heals it
r = L:attempt("talk")
check(not r.ok and r.reason == "locked" and not r.newlyLocked, "while locked every action is refused")
clockNow = clockNow + 301
check(not L:status().locked, "the lock expires")
check(L:attempt("talk").ok, "and the player is served again")

-- second offence: twice as long
local function spamUntilLocked()
  local info
  for _ = 1, 8 do
    clockNow = clockNow + 1
    info = L:attempt("pet")
    if info.reason == "locked" and info.newlyLocked then return info end
  end
  return info
end
clockNow = clockNow + 100
local second = spamUntilLocked()
check(second.reason == "locked" and second.newlyLocked, "spamming again locks again")
check(second.remaining == 600, "the second lock is doubled (10 minutes)")
eq(L:status().strikes, 2, "two strikes")
clockNow = clockNow + 601
local third = spamUntilLocked()
check(third.remaining == 1200, "the third is doubled again (20 minutes)")
clockNow = clockNow + 1201
local fourth = spamUntilLocked()
check(fourth.remaining == 2400, "the fourth is 40 minutes")
clockNow = clockNow + 2401
local fifth = spamUntilLocked()
check(fifth.remaining == 3600, "and it is capped at an hour")

-- strikes fade after a long quiet spell
clockNow = clockNow + 3601 + CFG.strikeReset
eq(L:status().strikes, 0, "strikes reset after a long quiet period")

-- ------- cancelling and then using normally never trips the abuse lock
L = fresh()
clockNow = 90000
for _ = 1, 4 do
  check(L:attempt("talk").ok or true, "polite use")
  clockNow = clockNow + 20
end
check(not L:status().locked, "polite, spaced use never locks")

-- ------- anti-bypass: the clock only moves forward
L = fresh()
clockNow = 200000
L:attempt("pet")
clockNow = 100 -- the system clock was set back
r = L:attempt("pet")
check(not r.ok and r.reason == "cooldown", "setting the clock back does not skip a cooldown")
clockNow = 200000 + 31
check(L:attempt("pet").ok, "real time passing still does")
-- ...and a lock survives a clock rewind
L = fresh()
clockNow = 300000
for _ = 1, 8 do clockNow = clockNow + 1 L:attempt("pet") end
check(L:status().locked, "locked")
clockNow = 5
check(L:status().locked, "a clock set back does not lift a lock")

-- ------- persistence: the state round-trips through the store
local saved
local store = {
  load = function() return saved end,
  save = function(state)
    -- a copy, as real storage would serialise it
    local function copy(v) if type(v) ~= "table" then return v end local o = {} for k, x in pairs(v) do o[k] = copy(x) end return o end
    saved = copy(state)
  end,
}
clockNow = 400000
local A = fresh(store)
A:attempt("pet")
for _ = 1, 8 do clockNow = clockNow + 1 A:attempt("pet") end
check(A:status().locked, "locked through a store")
local B = fresh(store) -- e.g. the game was closed and reopened
check(B:status().locked, "a fresh limiter reading the same store is still locked")
r = B:attempt("play")
check(not r.ok and r.reason == "locked", "...and still refuses")
A:reset()
check(A:status().locked, "reset() re-reads the store, which still says locked")

-- garbage in the store is ignored, never an error
saved = { gains = "nope", attempts = { "x", 5 }, last = 7, lockUntil = "soon" }
local C = fresh(store)
check(pcall(function() C:attempt("pet") end), "a corrupt saved state is tolerated")
check(not C:status().locked, "and starts clean")
local D = fresh({ load = function() error("storage offline") end, save = function() error("storage offline") end })
check(pcall(function() D:attempt("pet") end), "a failing store never throws")
check(D:attempt("play").ok, "the limiter still works in memory without storage")

print("")
if failures > 0 then
  io.stderr:write(failures .. " failure(s)\n")
  os.exit(1)
end
print("interaction_limiter_unit_test: all passed")
