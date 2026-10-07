-- Run: lua tests/forager_unit_test.lua
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
  local value = assert(loadfile("lib/" .. name .. ".lua"))(V)
  modules[name] = value
  return value
end
local Forager = V.require("forager")

local CFG = {
  minSpread = 5, maxSpread = 10, maxWalk = 30, forageMin = 300, forageMax = 300, findChance = 0.2,
  wanderWaitMin = 10, wanderWaitMax = 10, lingerMin = 10, lingerMax = 10,
  walkSpeed = 2, forageSpeed = 3, runSpeed = 4, cryPause = 6, digTicks = 12, popupTicks = 40,
  maxTmPrice = 3000,
}

-- a long open road with a wall column at x = 40 (north of y = 30 only)
local function open(x, y)
  if x < 0 or x > 5000 or y < 0 or y > 80 then return false end
  if x == 40 and y < 30 then return false end
  return true
end

local function newForager(deps)
  local d = { cellFree = open, rng = function() return 0.5 end, cfg = CFG,
              pickItem = function() return "Potion" end }
  for k, v in pairs(deps or {}) do d[k] = v end
  return Forager.new(d)
end

local MON = { species = 252 }
-- the player at cell (px, 30), the follower one cell behind; `moving` = walking
local function env(px, moving, t)
  local e = { still = not moving, fx = px - 1, fy = 30, fpx = (px - 1) * 16, fpy = 30 * 16,
              px = px, py = 30, mon = MON }
  for k, v in pairs(t or {}) do e[k] = v end
  return e
end

-- walk the player along the row for `ticks`, one cell per 16 ticks
local function walk(f, startPx, ticks, onTick)
  local px = startPx
  for i = 1, ticks do
    if i % 16 == 0 then px = px + 1 end
    local s = f:step(env(px, true))
    if onTick then onTick(s, px, i) end
  end
  return px
end

-- ------- a standing player: it stays beside them and nothing starts
do
  local f = newForager()
  local quiet = true
  for _ = 1, 600 do if f:step(env(20, false)) ~= nil then quiet = false end end
  check(quiet, "standing player: no override, ever")
  check(not f:isBusy(), "...and it is not busy")
end

-- ------- a walking player: it roams 5-10 tiles out, then runs back to within a tile
do
  local f = newForager({ rng = function() return 0.99 end })
  local sawOut, sawBack, maxDist, minDist, backedWithin = false, false, 0, 99, false
  walk(f, 20, 1500, function(_, px)
    if f.mode == "out" or f.mode == "linger" then sawOut = true end
    if f.mode == "back" then sawBack = true end
    -- measured the moment it reaches a wander spot (the player walks on afterwards)
    if f.mode == "linger" and f.t == 1 then
      local wcx, wcy = math.floor(f.wx / 16 + 0.5), math.floor(f.wy / 16 + 0.5)
      local d = math.max(math.abs(wcx - px), math.abs(wcy - 30))
      maxDist, minDist = math.max(maxDist, d), math.min(minDist, d)
    end
    if sawBack and f.mode == "near" then backedWithin = true end
  end)
  check(sawOut, "while the player walks it heads out")
  check(minDist >= 4, "...at least ~5 tiles from the player when it arrives (closest " .. minDist .. ")")
  check(maxDist <= 12, "...and about 10 at most (the player keeps walking while it goes) (farthest " .. maxDist .. ")")
  check(sawBack, "then runs back")
  check(backedWithin, "...to the player's side")
end

-- ------- it is back within a tile of the player when it returns
do
  local f = newForager({ rng = function() return 0.99 end })
  local closest = 1e9
  walk(f, 20, 1200, function()
    if f.mode == "near" then closest = math.min(closest, math.abs(f.dx), math.abs(f.dy)) end
  end)
  eq(closest, 0, "returning ends exactly beside the follower")
end

-- ------- stopping drops a wander and brings it home
do
  local f = newForager({ rng = function() return 0.99 end })
  local px = walk(f, 20, 200)
  local away = false
  for _ = 1, 40 do f:step(env(px, true)) if f:isBusy() then away = true end end
  check(away, "it was out on a wander")
  local ticks = 0
  while f:isBusy() and ticks < 800 do
    ticks = ticks + 1
    f:step(env(px, false))
  end
  check(not f:isBusy(), "when the player stops it comes home (" .. ticks .. " ticks)")
  for _ = 1, 600 do f:step(env(px, false)) end
  check(not f:isBusy(), "...and stays there while they stand")
end

-- ------- every 10-30 seconds of walking: a forage with a cry, a dig, a find, a run back
do
  local log, cries = {}, 0
  local f = newForager({
    rng = function() return 0.05 end, -- under the 20% find chance
    playCry = function(species) cries = cries + 1 log[#log + 1] = "cry" eq(species, 252, "the cry is the Forager's own species") end,
    pickItem = function() log[#log + 1] = "pick" return "Potion" end,
    playFound = function() log[#log + 1] = "found" end,
  })
  local sawDig, sawPopup, popupText, order = false, false, nil, {}
  local lastMode
  walk(f, 20, 900, function(s)
    if f.mode ~= lastMode then order[#order + 1] = f.mode lastMode = f.mode end
    if s and s.bounce then sawDig = true end
    if s and s.popup then sawPopup, popupText = true, s.popup.text end
  end)
  check(cries >= 1, "it cried to tell the player it found something (" .. cries .. " cries)")
  eq(log[1], "pick", "the find came first")
  eq(log[2], "found", "...with the sound")
  eq(log[3], "cry", "...and then the cry")
  check(sawDig, "it dug (bounce animation)")
  check(sawPopup and popupText == "Found Potion!", "a 'Found Potion!' label showed")
  local joined = table.concat(order, ">")
  check(joined:find("out>dig>cry>back", 1, true) ~= nil, "a forage that finds something is out > dig > cry > back (" .. joined .. ")")
end

-- ------- the real defaults: 10-30 seconds between forages, a 20% find chance
do
  local Config = V.require("config")
  eq(Config.FORAGE.forageMin, 600, "a forage at least 10 s (600 ticks) apart")
  eq(Config.FORAGE.forageMax, 1800, "...at most 30 s apart")
  eq(Config.FORAGE.findChance, 0.2, "a 20% chance to find an item")
  check(Config.FORAGE.allowedMapTypes[3] and Config.FORAGE.allowedMapTypes[4], "routes (3) and caves (4) are allowed")
  check(not (Config.FORAGE.allowedMapTypes[1] or Config.FORAGE.allowedMapTypes[2] or Config.FORAGE.allowedMapTypes[8]
    or Config.FORAGE.allowedMapTypes[5] or Config.FORAGE.allowedMapTypes[6]), "towns, cities, buildings and water are not")
  local f = Forager.new({ cellFree = open, cfg = Config.FORAGE })
  check(f.forageGoal >= 600 and f.forageGoal <= 1800, "the first forage is due after 600-1800 walking ticks (" .. f.forageGoal .. ")")
end

-- ------- the find chance: a low roll finds, a high roll finds nothing (and says nothing)
do
  local picks, popups = 0, 0
  local f = newForager({ rng = function() return 0.5 end, pickItem = function() picks = picks + 1 return "Potion" end })
  f.forageGoal = 20
  walk(f, 20, 700, function(s) if s and s.popup then popups = popups + 1 end end)
  eq(picks, 0, "a roll at or above 20% finds nothing")
  eq(popups, 0, "...and shows no label")
  local f2 = newForager({ rng = function() return 0.1 end, pickItem = function() picks = picks + 1 return "Potion" end })
  f2.forageGoal = 20
  walk(f2, 20, 700)
  check(picks >= 1, "a roll under 20% finds an item")
end

-- ------- a forage that finds nothing is silent: no cry, no label
do
  local cries, picks, sawDig, sawPopup = 0, 0, false, false
  local f = newForager({ rng = function() return 0.9 end, -- over the 20% find chance
    playCry = function() cries = cries + 1 end, pickItem = function() picks = picks + 1 return "Potion" end })
  f.forageGoal = 20
  local order, lastMode = {}, nil
  walk(f, 20, 1500, function(s)
    if f.mode ~= lastMode then order[#order + 1] = f.mode lastMode = f.mode end
    if s and s.bounce then sawDig = true end
    if s and s.popup then sawPopup = true end
  end)
  check(sawDig, "it still digs")
  eq(cries, 0, "...but a dig that finds nothing never cries")
  eq(picks, 0, "...and picks nothing")
  check(not sawPopup, "...and shows no label")
  check(table.concat(order, ">"):find("out>dig>back", 1, true) ~= nil, "it goes straight back (out > dig > back)")
end

-- ------- no forage before the timer runs out
do
  local cries = 0
  local f = newForager({ playCry = function() cries = cries + 1 end, rng = function() return 0.05 end })
  f.forageGoal = 2000
  walk(f, 20, 900)
  eq(cries, 0, "no forage before the timer is up")
  f.forageGoal = 1000
  walk(f, 80, 400)
  check(cries >= 1, "...but one once it is")
end

-- ------- the timer only runs while walking
do
  local cries = 0
  local f = newForager({ playCry = function() cries = cries + 1 end, rng = function() return 0.05 end })
  f.forageGoal = 100
  for _ = 1, 1000 do f:step(env(20, false)) end
  eq(cries, 0, "a standing player never starts a forage")
  eq(f.forageTimer, 0, "...and the timer does not run")
end

-- ------- towns, buildings and water are off limits
do
  local cries = 0
  local f = newForager({ playCry = function() cries = cries + 1 end, rng = function() return 0.05 end })
  f.forageGoal = 20
  local px, quiet = 20, true
  for i = 1, 1500 do
    if i % 16 == 0 then px = px + 1 end
    if f:step(env(px, true, { forageOk = false })) ~= nil then quiet = false end
  end
  check(quiet, "where foraging is not allowed it just trots along")
  eq(cries, 0, "no forage there")
  eq(f.forageTimer, 0, "...and the timer does not run there")
  check(not f:isBusy(), "...it never leaves the player's side")
  -- back where it is allowed, the (kept) timer carries on
  f.forageTimer = 10
  walk(f, px, 700)
  check(cries >= 1, "back on a route it forages again")
end

-- ------- a map change cancels the trip but keeps the timer
do
  local f = newForager({ rng = function() return 0.99 end })
  walk(f, 20, 300)
  f.forageTimer = 123
  f:mapChanged()
  check(not f:isBusy(), "a map change brings it back to the player's side")
  eq(f.forageTimer, 123, "...and keeps the forage timer")
  f:reset()
  eq(f.forageTimer, 0, "(a full reset, e.g. a save load, clears it)")
end

-- ------- a forage that has begun is finished even if the player stops
do
  local cries, picked = 0, 0
  local f = newForager({ rng = function() return 0.05 end, playCry = function() cries = cries + 1 end,
    pickItem = function() picked = picked + 1 return "Potion" end })
  f.forageGoal, f.forageTimer = 1, 1
  local px = 20
  local ticks = 0
  -- walk until the trip is out
  while f.mode ~= "out" and ticks < 2000 do
    ticks = ticks + 1
    if ticks % 16 == 0 then px = px + 1 end
    f:step(env(px, true))
  end
  eq(f.purpose, "forage", "a forage trip is under way")
  for _ = 1, 600 do f:step(env(px, false)) end
  eq(cries, 1, "it still cried although the player stopped")
  eq(picked, 1, "...and still found its item")
  check(not f:isBusy(), "...and came home")
end

-- ------- hemmed in / blocked: it just trots along
do
  local f = newForager({ cellFree = function(x, y) return x == 19 and y == 30 end })
  for _ = 1, 400 do f:step(env(20, true)) end
  check(not f:isBusy(), "with nowhere to go it never sets off")
end

-- ------- it avoids cells a wild Pokemon stands on
do
  local asked = 0
  local f = newForager({ occupied = function() asked = asked + 1 return true end })
  for _ = 1, 400 do f:step(env(20, true)) end
  check(asked > 0 and not f:isBusy(), "occupied cells are never a destination")
end

-- ------- never into or across a wall
do
  local bad = 0
  local f = newForager({ rng = function() return 0.3 end })
  walk(f, 36, 3000, function()
    local cx, cy = math.floor(f.wx / 16 + 0.5), math.floor(f.wy / 16 + 0.5)
    if f.mode == "out" and not open(cx, cy) then bad = bad + 1 end
  end)
  eq(bad, 0, "on the way out it only ever stands on open cells")
end

-- ------- no find: no label, still comes home
do
  local f = newForager({ rng = function() return 0.05 end, pickItem = function() return nil end })
  f.forageGoal = 1
  local sawPopup = false
  walk(f, 20, 3000, function(s) if s and s.popup then sawPopup = true end end)
  check(not sawPopup, "no find, no label")
end

-- ------- reset
do
  local f = newForager()
  walk(f, 20, 200)
  f:reset()
  check(not f:isBusy(), "reset puts it back at the player's side")
  check(f.forageTimer == 0 and f.forageGoal == 300, "...and clears the forage timer")
end

-- ------- the real defaults carry every knob it reads, with the asked-for ranges
do
  local Config = V.require("config")
  for _, k in ipairs({ "minSpread", "maxSpread", "maxWalk", "forageMin", "forageMax", "findChance", "allowedMapTypes",
    "wanderWaitMin", "wanderWaitMax", "lingerMin", "lingerMax", "walkSpeed", "forageSpeed", "runSpeed",
    "cryPause", "digTicks", "popupTicks", "maxTmPrice" }) do
    check(Config.FORAGE[k] ~= nil, "Config.FORAGE." .. k)
  end
  eq(Config.FORAGE.minSpread, 5, "it roams from 5 tiles ...")
  eq(Config.FORAGE.maxSpread, 10, "... to 10 tiles out")
end

if failures > 0 then
  io.stderr:write(failures .. " failure(s)\n")
  os.exit(1)
end
print("forager_unit_test: all passed")
