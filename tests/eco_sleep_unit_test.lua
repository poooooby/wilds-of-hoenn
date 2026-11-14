-- Run: lua tests/eco_sleep_unit_test.lua
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

local player = { x = 30, y = 30, moving = false }
local running, biking = false, false
local fake = {
  terrainAt = function(x, y) if x >= 0 and y >= 0 and x < 40 and y < 40 then return "land" end return nil end,
  canEnter = function() return true end,
  isWater = function() return false end,
  playerCell = function() return player end,
  playerIsRunning = function() return running end,
  playerBiking = function() return biking end,
}
local modules = { engine_patch = fake }
local V = { path = "." }
function V.require(name)
  if modules[name] == nil then modules[name] = assert(loadfile("lib/" .. name .. ".lua"))(V) end
  return modules[name]
end
local Config = V.require("config")
local Eco = V.require("eco")
local EcoSleep = V.require("eco_sleep")

local function mon(activity, temper, anims)
  local info = {}
  for _, a in ipairs(anims or {}) do info[a] = { cols = 2, top = 8 } end
  local r = { isPmd = true, info = info, anim = "idle" }
  function r:advanceAs(a, _, fallback) self.anim = self.info[a] and a or (fallback or "idle") end
  function r:advance(moving) self.anim = moving and "walk" or "idle" end
  function r:holdIdle() self.anim = "hold" end
  function r:headLift(list) return list and list[1] == "sleep" and 9 or 20 end
  return { id = 1, species = 1, level = 10, terrain = "land", cellX = 5, cellY = 5, px = 80, py = 80,
           facing = "down", state = "available", renderer = r,
           profile = { activity = activity, temper = temper or "calm", social = "solo" } }
end
local function ctx(now, night, extra)
  local c = { now = now or 0, night = night, player = player, game = {},
              rng = function(a, b) return (extra and extra.roll) or a end }
  for k, v in pairs(extra or {}) do c[k] = v end
  return c
end

-- ------- the hours and the odds (pure)
do
  local cfg = Config.ECO.sleep
  check(EcoSleep.isNight(22, cfg) and EcoSleep.isNight(3, cfg), "22:00 and 03:00 are night")
  check(not EcoSleep.isNight(12, cfg) and not EcoSleep.isNight(6, cfg), "noon and 06:00 are day")
  check(not EcoSleep.isNight(nil, cfg), "no hour: not night")
  eq(EcoSleep.chance("day", true, cfg), cfg.chance.dayAtNight, "a day Pokemon sleeps at night")
  eq(EcoSleep.chance("day", false, cfg), 0, "...never by day")
  eq(EcoSleep.chance("night", false, cfg), cfg.chance.nightByDay, "a night Pokemon sleeps by day")
  eq(EcoSleep.chance("night", true, cfg), 0, "...never at night")
  eq(EcoSleep.chance("any", true, cfg), cfg.chance.anyAtNight, "anything else now and then at night")
  eq(EcoSleep.chance("any", false, cfg), 0, "...never by day")
end

-- ------- falling asleep
do
  local e = mon("day", "calm", { "sleep", "wake" })
  local kind, st = EcoSleep.choose(e, ctx(0, true, { roll = 1 }))
  eq(kind, "sleep", "a day Pokemon falls asleep at night (rolled sleepy)")
  eq(st.anim, "sleep", "...curled up in its Sleep animation")
  eq(e.sleepPeriod, "night", "...its roll kept for the night")
  local d = mon("day")
  eq(EcoSleep.choose(d, ctx(0, false)), nil, "the same Pokemon by day stays up")
  local n = mon("night", "calm", { "nap" })
  local _, ns = EcoSleep.choose(n, ctx(0, false, { roll = 1 }))
  eq(ns and ns.anim, "nap", "a night Pokemon asleep by day; EventSleep when it has no Sleep")
  local unlucky = mon("day")
  eq(EcoSleep.choose(unlucky, ctx(0, true, { roll = 100 })), nil, "an unlucky roll: up all night")
  eq(EcoSleep.choose(unlucky, ctx(60, true, { roll = 1 })), nil, "...decided once a night, not every look")
  eq(EcoSleep.choose(mon("day"), ctx(0, nil, { roll = 1 })), nil, "the hour unknown: nobody sleeps")
  local water = mon("day")
  water.terrain = "water"
  eq(EcoSleep.choose(water, ctx(0, true, { roll = 1 })), nil, "a swimmer does not sleep")
  local near = mon("day")
  player.x, player.y = 6, 5
  eq(EcoSleep.choose(near, ctx(0, true, { roll = 1 })), nil, "nor with the player right beside it")
  player.x, player.y = 30, 30
  local woken = mon("day")
  woken.awakeUntil = 500
  eq(EcoSleep.choose(woken, ctx(100, true, { roll = 1 })), nil, "nor just after it was woken")
end

-- ------- sleeping, waking by itself
do
  local e = mon("day", "calm", { "sleep", "wake" })
  Eco.start(e, "sleep", EcoSleep.state(e, true))
  for t = 1, 100 do Eco.step(e, ctx(t, true), nil) end
  eq(e.renderer.anim, "sleep", "it sleeps on, in its Sleep animation")
  eq(e.eco.zzz, 100, "...its z's counting up")
  check(e.eco.sleeping and not e.eco.waking, "...asleep")
  Eco.step(e, ctx(101, false), nil) -- morning
  check(e.eco and e.eco.waking, "morning: it wakes")
  eq(e.renderer.anim, "wake", "...with its Wake animation")
  for t = 102, 200 do Eco.step(e, ctx(t, false), nil) end
  eq(e.eco, nil, "...and gets up")
  eq(e.react, nil, "...no fuss: nobody woke it")
  check((e.awakeUntil or 0) > 200, "...and stays up a while")
  local h = mon("day")
  h.renderer.isPmd = false
  Eco.start(h, "sleep", EcoSleep.state(h, true))
  Eco.step(h, ctx(1, true), nil)
  eq(h.renderer.anim, "idle", "HGSS art just stands (the z's say it sleeps)")
  local still = mon("day")
  Eco.start(still, "sleep", EcoSleep.state(still, true))
  Eco.step(still, ctx(1, true), nil)
  eq(still.renderer.anim, "hold", "PMD art with no sleeping pose lies still on Idle's first frame")
  eq(EcoSleep.headOf(e.renderer, "sleep"), 9, "the z's start over its sleeping head")
end

-- ------- woken by the player
do
  -- a territorial one: angry at once
  local e = mon("day", "territorial", { "sleep" })
  Eco.start(e, "sleep", EcoSleep.state(e, true))
  Eco.step(e, ctx(1, true), nil)
  player.x, player.y, player.moving = 7, 5, false
  Eco.step(e, ctx(2, true), nil) -- two tiles off, standing: it sleeps on
  check(e.eco and not e.eco.waking, "the player two tiles off, standing: it sleeps on (sneak by)")
  player.x = 6
  Eco.step(e, ctx(3, true, { lead = { level = 10, bst = 300 }, bst = function() return 300 end }), nil)
  eq(e.eco, nil, "right beside it: it wakes (no Wake art: at once)")
  eq(e.react and e.react.mode, "turn", "...and a territorial one turns on the player, angry")
  -- a skittish one: it runs
  local s = mon("day", "skittish", { "sleep" })
  Eco.start(s, "sleep", EcoSleep.state(s, true))
  Eco.step(s, ctx(4, true, { lead = { level = 10, bst = 300 }, bst = function() return 300 end }), nil)
  eq(s.react and s.react.next, "flee", "a skittish one runs")
  -- a calm one: just awake
  local c = mon("day", "calm", { "sleep" })
  Eco.start(c, "sleep", EcoSleep.state(c, true))
  Eco.step(c, ctx(5, true, { lead = { level = 10, bst = 300 }, bst = function() return 300 end }), nil)
  check(c.eco == nil and c.react == nil, "a calm even match just wakes up")
  -- running wakes it from farther
  player.x, player.y, player.moving, running = 8, 5, true, true
  local r = mon("day", "calm", { "sleep" })
  Eco.start(r, "sleep", EcoSleep.state(r, true))
  Eco.step(r, ctx(6, true), nil)
  check(r.eco == nil, "running three tiles off wakes it")
  running, player.moving = false, false
  local w = mon("day", "calm", { "sleep" })
  Eco.start(w, "sleep", EcoSleep.state(w, true))
  player.moving = true
  Eco.step(w, ctx(7, true), nil)
  check(w.eco and w.eco.sleeping, "walking three tiles off does not")
  player.x, player.y, player.moving = 30, 30, false
end

if failures > 0 then
  io.stderr:write(failures .. " failure(s)\n")
  os.exit(1)
end
print("all eco_sleep tests passed")
