-- Run: lua tests/eco_land_unit_test.lua
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

-- an open field of grass 20 x 20
local cries = {}
local player = { x = 30, y = 30 }
local running = false
local fake = {
  terrainAt = function(x, y) if x >= 0 and y >= 0 and x < 20 and y < 20 then return "land" end return nil end,
  canEnter = function(_, x, y) return x >= 0 and y >= 0 and x < 20 and y < 20 end,
  isWater = function() return false end,
  ripplesAt = function() return false end,
  playerCell = function() return player end,
  playerIsRunning = function() return running end,
  playCry = function(s) cries[#cries + 1] = s end,
}
local modules = { engine_patch = fake }
local V = { path = "." }
function V.require(name)
  if modules[name] == nil then modules[name] = assert(loadfile("lib/" .. name .. ".lua"))(V) end
  return modules[name]
end
local Config = V.require("config")
local Eco = V.require("eco")
local EcoLand = V.require("eco_land")

local function mon(social, anims, diet)
  local info = {}
  for _, a in ipairs(anims or {}) do info[a] = { cols = 2 } end
  local r = { isPmd = true, info = info, anim = "idle" }
  function r:advanceAs(a, _, fallback) self.anim = self.info[a] and a or (fallback or "idle") end
  function r:advance(moving) self.anim = moving and "walk" or "idle" end
  function r:holdIdle() self.anim = "hold" end
  local e = { id = 1, species = 1261, terrain = "land", cellX = 5, cellY = 5, px = 80, py = 80, facing = "down",
              state = "available", renderer = r, profile = { social = social, diet = diet or "neutral" } }
  if social ~= "solo" then e.group = { leader = 1, members = { 1 }, social = social } end
  return e
end
local function ctx(now) return { now = now or 0, rng = function(a) return a end, player = player, game = {} } end

-- ------- a burst: a few steps at its pace, then done
do
  local e = mon("pack")
  Eco.start(e, "burst", EcoLand.burstState(e, 3, 12, function(a) return a end))
  local steps, x0, y0 = 0, e.cellX, e.cellY
  for _ = 1, 200 do
    if not e.eco then break end
    local before = e.moving
    Eco.step(e, ctx(), nil)
    if e.moving and not before then steps = steps + 1 end
  end
  eq(e.eco, nil, "the burst ends")
  eq(steps, 3, "...after its 3 steps")
  check(e.cellX ~= x0 or e.cellY ~= y0, "...somewhere else")
  -- boxed in at the field's corner heading out of it: it turns
  local c = mon("pack")
  c.cellX, c.cellY, c.px, c.py = 0, 0, 0, 0
  Eco.start(c, "burst", { n = 2, frames = 12, dir = "up", blocked = 0 })
  for _ = 1, 200 do if not c.eco then break end Eco.step(c, ctx(), nil) end
  check(c.cellX > 0 or c.cellY > 0, "a blocked heading turns another way")
end

-- ------- a pose: grazing with Eat art, standing without it
do
  local e = mon("herd", { "eat" })
  Eco.start(e, "pose", EcoLand.poseState(e, "eat", 30))
  eq(e.eco.groupAnim, "eat", "a herd grazes: its group eats too")
  Eco.step(e, ctx(), nil)
  eq(e.renderer.anim, "eat", "...with its Eat animation")
  for _ = 1, 40 do Eco.step(e, ctx(), nil) end
  eq(e.eco, nil, "...until it is done")
  local plain = mon("herd", {})
  Eco.start(plain, "pose", EcoLand.poseState(plain, "eat", 10))
  Eco.step(plain, ctx(), nil)
  eq(plain.renderer.anim, "idle", "no Eat art: it just stands")
  eq(plain.eco.groupAnim, nil, "...and its group does not pretend to eat")
end

-- ------- a nap: asleep with EventSleep art, waking with Wake when the player comes close
do
  local e = mon("huddle", { "nap", "wake" })
  Eco.start(e, "pose", EcoLand.poseState(e, "nap", 1000, { wake = true }))
  for _ = 1, 20 do Eco.step(e, ctx(), nil) end
  eq(e.renderer.anim, "nap", "a huddle naps")
  player = { x = 6, y = 5 }
  local sawWake = false
  for _ = 1, 100 do
    if not e.eco then break end
    Eco.step(e, ctx(), nil)
    if e.renderer.anim == "wake" then sawWake = true end
  end
  check(sawWake, "the player right beside it: it wakes up (Wake)")
  eq(e.eco, nil, "...and the nap is over")
  player = { x = 30, y = 30 }
  local noArt = mon("huddle", {})
  Eco.start(noArt, "pose", EcoLand.poseState(noArt, "nap", 20, { wake = true }))
  Eco.step(noArt, ctx(), nil)
  eq(noArt.renderer.anim, "hold", "no sleeping art: it rests still on Idle's first frame")
end

-- ------- what each kind chooses
do
  local function firstChoice(e, rounds)
    for t = 0, rounds or 20000, 30 do
      local kind = EcoLand.choose(e, ctx(t), nil)
      if kind then return kind, t end
    end
  end
  local pack = mon("pack", { "rearup" })
  local kind = firstChoice(pack)
  check(kind == "burst" or kind == "pose", "a pack trots or howls (" .. tostring(kind) .. ")")
  local herd = mon("herd", { "eat" })
  check(firstChoice(herd) ~= nil, "a herd grazes / drifts")
  local swarm = mon("swarm")
  eq(firstChoice(swarm), "burst", "a swarm darts about")
  local huddle = mon("huddle", { "nap" })
  eq(firstChoice(huddle), "pose", "a huddle naps")
  local solo = mon("solo", { "eat" }, "prey")
  eq(firstChoice(solo), "pose", "a lone grazer with Eat art stops to eat now and then")
  local hunter = mon("solo", { "eat" }, "predator")
  eq(firstChoice(hunter), nil, "a lone hunter does not graze")
  local water = mon("pack")
  water.terrain = "water"
  eq(firstChoice(water), nil, "nothing on land for a water spawn")
  player = { x = 6, y = 5 }
  local near = mon("swarm")
  eq(firstChoice(near), nil, "nothing starts right beside the player")
  player = { x = 30, y = 30 }
end

-- ------- sitting down (a back view: it turns away first), getting up again
do
  local e = mon("solo", {})
  local speeds = {}
  e.renderer.info.sit = { durations = { 8, 8, 8 }, rows = 1, facing = "up" }
  function e.renderer:advanceAs(a, speed) self.anim = a speeds[#speeds + 1] = speed end
  Eco.start(e, "pose", EcoLand.poseState(e, "sit", 40, { rouse = 1 }))
  Eco.step(e, ctx(), nil)
  eq(e.facing, "up", "sitting down: it turns its back to the camera")
  eq(e.renderer.anim, "sit", "...and sits (Sit)")
  eq(e.eco.groupAnim, "sit", "...its group with it")
  for _ = 1, 45 do Eco.step(e, ctx(), nil) end
  check(e.eco and e.eco.unwinding and speeds[#speeds] == -1, "the time up: it gets up again, the pose played back")
  for _ = 1, 30 do if e.eco then Eco.step(e, ctx(), nil) end end
  eq(e.eco, nil, "...then it is done")
  -- the player walking right up to it: it gets up at once
  local s = mon("solo", {})
  s.renderer.info.sit = { durations = { 8, 8, 8 }, rows = 1, facing = "up" }
  Eco.start(s, "pose", EcoLand.poseState(s, "sit", 400, { rouse = 1 }))
  for _ = 1, 5 do Eco.step(s, ctx(), nil) end
  player = { x = 6, y = 5 }
  Eco.step(s, ctx(), nil)
  check(s.eco and s.eco.unwinding, "the player beside it: it gets up")
  player = { x = 30, y = 30 }
  -- the chooser: only with Sit art, never a swarm
  local plain, sitter = mon("solo", {}), mon("solo", {})
  sitter.renderer.info.sit = { durations = { 8, 8, 8 }, rows = 1, facing = "up" }
  local cfg = Config.ECO.land.sit
  sitter.ecoDue, plain.ecoDue = { sit = 0, graze = math.huge }, { sit = 0 }
  local kind, st = EcoLand.choose(sitter, ctx(10), nil)
  check(kind == "pose" and st.anim == "sit", "a Pokemon with Sit art sits down now and then")
  check(EcoLand.choose(plain, ctx(10), nil) == nil, "...one without just stands")
  local sw = mon("swarm", {})
  sw.renderer.info.sit = sitter.renderer.info.sit
  sw.ecoDue = { sit = 0, buzz = math.huge }
  check(EcoLand.choose(sw, ctx(10), nil) == nil, "...a swarm never sits")
  check(cfg.ticks[1] > 0, "(sit lengths set)")
end

-- ------- a bird flying over: those with LookUp art look up at it, once per bird
do
  local bird = { id = 7 }
  local sm = { sky = { passerOver = function() return bird end } }
  local e = mon("solo", {})
  e.renderer.info.lookup = { durations = { 6, 6, 6 }, rows = 1, facing = "up" }
  local kind, st = EcoLand.chooseLookUp(e, ctx(), sm)
  check(kind == "pose" and st.anim == "lookup" and st.face == "up", "a bird overhead: it looks up at it")
  eq(EcoLand.chooseLookUp(e, ctx(), sm), nil, "...only once for the same bird")
  bird = { id = 8 }
  check(EcoLand.chooseLookUp(e, ctx(), sm) ~= nil, "...but again for the next")
  sm.sky.passerOver = function() return nil end
  eq(EcoLand.chooseLookUp(mon("solo", { "lookup" }), ctx(), sm), nil, "no bird: nobody looks up")
  bird = { id = 9 }
  sm.sky.passerOver = function() return bird end
  eq(EcoLand.chooseLookUp(mon("solo", {}), ctx(), sm), nil, "no LookUp art: nothing")
  local r = mon("solo", { "lookup" })
  r.react = { mode = "flee" }
  eq(EcoLand.chooseLookUp(r, ctx(), sm), nil, "busy reacting: nothing")
  local quick = ctx()
  quick.rng = function(_, b) return b end -- the roll misses
  eq(EcoLand.chooseLookUp(mon("solo", { "lookup" }), quick, sm), nil, "a missed roll: it does not notice")
end

if failures > 0 then
  io.stderr:write(failures .. " failure(s)\n")
  os.exit(1)
end
print("eco_land_unit_test: all passed")
