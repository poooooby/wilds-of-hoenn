-- Run: lua tests/eco_unit_test.lua
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

local modules = { engine_patch = {} }
local V = {}
function V.require(name)
  if modules[name] == nil then modules[name] = assert(loadfile("lib/" .. name .. ".lua"))(V) end
  return modules[name]
end
local Eco = V.require("eco")
local Config = V.require("config")

local aborted = {}
Eco.register("wiggle", {
  step = function(e, _ctx, _sm, s)
    e.wiggles = (e.wiggles or 0) + 1
    if s.hide then s.untouchable = true end
    return s.t >= 5
  end,
  abort = function(e) aborted[#aborted + 1] = e end,
})
Eco.register("broken", { step = function() error("boom") end })

-- ------- an activity runs, then puts things back when it ends
do
  local e = {}
  check(Eco.start(e, "wiggle"), "a registered activity starts")
  eq(e.eco.kind, "wiggle", "...kept on the Pokemon")
  check(not Eco.start({}, "nonsense"), "an unknown one does not")
  for _ = 1, 10 do Eco.step(e, {}, nil) end
  eq(e.wiggles, 5, "it ran until it said it was done")
  eq(e.eco, nil, "...then it ended")
  eq(aborted[#aborted], e, "...and put back what it changed")
end

-- ------- abort, hiding, and a broken activity
do
  local e = {}
  Eco.start(e, "wiggle", { hide = true })
  Eco.step(e, {}, nil)
  check(not Eco.touchable(e), "an activity can make it untouchable (mid-leap)")
  Eco.abort(e)
  eq(e.eco, nil, "abort ends it at once")
  check(Eco.touchable(e), "...and it can be met again")
  local b = {}
  Eco.start(b, "broken")
  Eco.step(b, {}, nil)
  eq(b.eco, nil, "an activity that errors is dropped, never left running")
end

-- ------- choosers are asked on each Pokemon's own timer
do
  local asked = 0
  Eco.addChooser(function(e)
    asked = asked + 1
    if e.wants then return "wiggle", { from = "chooser" } end
  end)
  local e = { wants = true }
  local ctx = { now = 0, rng = function(a) return a end }
  check(not Eco.consider(e, ctx), "the first look only sets its timer")
  ctx.now = 1
  check(Eco.consider(e, ctx), "...then a chooser starts its activity")
  eq(e.eco.from, "chooser", "...with the chooser's state")
  local quiet = {}
  local n0 = asked
  ctx.now = 100
  Eco.consider(quiet, ctx) -- sets its timer
  for t = 101, 101 + Config.ECO.chooseEvery * 2 do ctx.now = t Eco.consider(quiet, ctx) end
  check(asked - n0 <= 3, "a Pokemon is asked about once per chooseEvery ticks (" .. (asked - n0) .. ")")
  local moving = { moving = true, ecoNext = 0 }
  check(not Eco.consider(moving, ctx), "nobody starts something mid-step")
end

if failures > 0 then
  io.stderr:write(failures .. " failure(s)\n")
  os.exit(1)
end
print("eco_unit_test: all passed")
