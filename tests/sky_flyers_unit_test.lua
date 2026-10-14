-- Run: lua tests/sky_flyers_unit_test.lua
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

math.randomseed(7)

local fake = {}
local optionStore = { sprite_style = "pokemmo" }
local mod = {
  id = "wilds_of_hoenn",
  options = { get = function(_, k) return optionStore[k] end },
  read = function() return nil end,
}
local modules = { engine_patch = fake }
local V = { path = ".", mod = mod }
function V.require(name)
  if modules[name] ~= nil then return modules[name] end
  local value = assert(loadfile("lib/" .. name .. ".lua"))(V)
  modules[name] = value
  return value
end

-- species: 10 Taillow (Normal/Flying), 11 Wingull (Water/Flying), 12 Zigzagoon (Normal)
-- 13 Gyarados (Water/Flying, but it does not fly)
local TYPES = { [10] = { 0, 2 }, [11] = { 11, 2 }, [12] = { 0, 0 }, [13] = { 11, 2 } }
local NAT = { [10] = 276, [11] = 278, [12] = 263, [13] = 130 }
local tables = {
  ROUTE_104 = { land = { slots = { { species = 12 }, { species = 10 }, { species = 10 } } },
                water = { slots = { { species = 11 }, { species = 13 } } } },
  ROUTE_102 = { land = { slots = { { species = 12 } } } },
  PETALBURG = nil,
}
local mapType, neighbours, weather = 3, {}, 0
local player = { x = 0, y = 0, moving = false }
fake.tableFor = function(id) return tables[id] end
fake.isFlying = function(s) local t = TYPES[s] return t and (t[1] == 2 or t[2] == 2) or false end
fake.isWaterType = function(s) local t = TYPES[s] return t and (t[1] == 11 or t[2] == 11) or false end
fake.speciesTypes = function(s) local t = TYPES[s] or { 0, 0 } return t[1], t[2] end
fake.mapType = function() return mapType end
fake.skyAllowed = function() return mapType == 1 or mapType == 2 or mapType == 3 or mapType == 6 end
fake.neighbourMapIds = function() return neighbours end
fake.weatherId = function() return weather end
fake.nationalFor = function(s) return NAT[s] end
-- Pokedex heights (dm, by internal species id): Gyarados is far too big to be a bird
local HEIGHT = { [10] = 3, [11] = 6, [12] = 4, [13] = 65 }
fake.heightDm = function(s) return HEIGHT[s] end
fake.mapBounds = function() return 30, 20 end
-- a row of tree crowns along y = 2, open water for x >= 20
fake.isWall = function(_, y) return y == 2 end
fake.coversActors = function(_, y) return y == 2 end
fake.isWater = function(x) return x >= 20 end
fake.objectOn = function() return false end
fake.isWarpCell = function() return false end
fake.signCells = function() return {} end
local ripples = 0
fake.startRipple = function() ripples = ripples + 1 return true end
local cries = 0
fake.playCry = function() cries = cries + 1 return true end
fake.playerIsRunning = function() return false end
fake.viewSize = function() return 480, 320 end
fake.playerCell = function() return player end

local SkyFlyers = V.require("sky_flyers")
local FlightPath = V.require("flight_path")
local Config = V.require("config")

-- ------- which species: the Flying types of the map, sea birds marked
do
  local pool = SkyFlyers.poolFor("ROUTE_104")
  local by = {}
  for _, e in ipairs(pool) do by[e.species] = e end
  check(by[10] and by[11] and not by[12], "only Flying types (Taillow, Wingull; not Zigzagoon)")
  check(not by[13], "never a Flying type that does not fly (Gyarados)")
  check(not SkyFlyers.flies(13) and SkyFlyers.flies(10), "flies(): Taillow yes, Gyarados no")
  do -- the flyer audit: Charizard is no bird, Dragonite (its Special0 glide) is
    local savedNat, savedFly = fake.nationalFor, fake.isFlying
    fake.nationalFor = function(s) if s == 20 then return 6 elseif s == 21 then return 149 end return savedNat(s) end
    fake.isFlying = function(s) return s == 20 or s == 21 or savedFly(s) end
    check(not SkyFlyers.flies(20), "flies(): never Charizard (ruled out by the audit)")
    check(SkyFlyers.flies(21), "flies(): Dragonite does")
    fake.nationalFor, fake.isFlying = savedNat, savedFly
  end
  eq(by[10].weight, 2, "weighted by how many slots it has")
  check(by[11].sea and not by[10].sea, "Wingull is a sea bird (water slot, Water type), Taillow is not")
  mapType, neighbours = 1, { "ROUTE_104" }
  local town = SkyFlyers.poolFor("PETALBURG")
  check(#town == 2, "a town (no table) takes the Flying types of the routes joined to it")
  mapType, neighbours = 3, { "ROUTE_104" }
  check(#SkyFlyers.poolFor("ROUTE_102") == 2, "a route without flyers borrows its neighbours'")
  neighbours = {}
end

-- ------- open sky only
do
  local sky = SkyFlyers.new(mod)
  mapType = 8
  sky:onMapEntered("HOUSE")
  check(not sky.allowed, "no birds indoors")
  mapType = 3
  sky:onMapEntered("ROUTE_104")
  check(sky.allowed, "a route: birds")
  check(sky.perches:count() > 0, "...with the tree crowns as perches")
  optionStore.flyers = false
  sky:onOptionChanged("ROUTE_104")
  check(not sky.allowed and sky:count() == 0, "Flying Mons off: none")
  optionStore.flyers = nil
end

-- ------- in play: passers, perchers and divers come, birds never pile up
do
  local sky = SkyFlyers.new(mod)
  sky:onMapEntered("ROUTE_104")
  local actors = {}
  sky:collectActors(actors, 0, 0) -- the camera: the view is (0, 0) .. (480, 320) = 30 x 20 cells
  player.x, player.y = 0, 19
  local seen, maxAt = {}, 0
  for _ = 1, 60 * 120 do
    sky:tick()
    for _, b in ipairs(sky.birds) do seen[b.kind] = true end
    maxAt = math.max(maxAt, sky:count("passer"))
  end
  check(seen.passer, "birds pass overhead")
  check(seen.perch, "birds come to perch")
  check(seen.dive, "sea birds dive")
  check(maxAt <= Config.FLYERS.passer.max, "never more passers than the cap")
  check(ripples > 0, "a dive splashes (engine ripple)")
  actors = {}
  sky:collectActors(actors, 0, 0)
  for _, a in ipairs(actors) do
    if a.kind == "sky_mon" or a.kind == "sky_mon_far" then
      check(a.priority == 1, "a bird is drawn above roofs and tree crowns") break
    end
  end
  sky:onMapExited()
  eq(sky:count(), 0, "leaving the map clears the sky")
end

-- ------- a perched bird flies off when the player walks up
do
  local sky = SkyFlyers.new(mod)
  sky:onMapEntered("ROUTE_104")
  sky:collectActors({}, 0, 0)
  player.x, player.y = 0, 19
  local bird
  for _ = 1, 60 * 60 do
    sky:tick()
    for _, b in ipairs(sky.birds) do if b.kind == "perch" and b.sitting then bird = b end end
    if bird then break end
  end
  check(bird ~= nil, "a bird settles on a perch")
  if bird then
    local spot = bird.perch
    check(sky.taken[spot] == bird, "...and holds that perch")
    eq(bird.pose, "stand", "...wings folded (its standing art, no flapping)")
    player.x, player.y = spot.x, spot.y + 1
    sky:tick() sky:tick()
    check(not bird.sitting, "the player comes close: it takes off")
    check(sky.taken[spot] == nil, "...and frees the perch")
  end
  player.x, player.y = 0, 19
end

-- ------- a wild Flying-type Pokemon arriving by air
do
  local sky = SkyFlyers.new(mod)
  sky:onMapEntered("ROUTE_104")
  local renderer = V.require("renderer_factory").new(mod, 276, false, "pokemmo", "land")
  local e = { id = 5, cellX = 4, cellY = 8, dex = 276, renderer = renderer, isFlyer = true }
  check(sky:canFly(e), "a Flying type may arrive by air")
  check(not sky:canFly({ isFlyer = true, roamer = true }), "never the roaming legendary")
  check(not sky:canFly({ isFlyer = false }), "never a ground species")
  local fx = sky:planArrival(e)
  eq(fx.kind, "land", "an arrival")
  local first = FlightPath.current(fx.plan)
  check(first.type == "fly" and first.from.h >= 0.55, "it starts mid or high up")
  local ticks = 0
  while not sky:stepFlight(fx) do ticks = ticks + 1 if ticks > 2000 then break end end
  check(ticks < 2000, "it lands")
  check(math.abs(fx.view.x - 64) < 1e-6 and math.abs(fx.view.y - 128) < 1e-6, "...on its own cell")
  eq(fx.view.h, 0, "...on the ground")
  SkyFlyers.restore(fx.view)
  eq(renderer.presentation, "land", "its ground art is back")

  -- by way of a perch: forced
  local saved = Config.FLYERS.land.perchChance
  Config.FLYERS.land.perchChance = 1
  local e2 = { id = 6, cellX = 5, cellY = 4, dex = 276, renderer = renderer, isFlyer = true }
  local fx2 = sky:planArrival(e2)
  local types = {}
  for _, ph in ipairs(fx2.plan.phases) do types[#types + 1] = ph.type end
  eq(table.concat(types, ","), "fly,sit,hop", "a perch near its cell: fly to it, sit, hop down")
  local perch = fx2.view.perch
  check(perch and sky.taken[perch] == e2, "...holding the perch meanwhile")
  local n = 0
  while not sky:stepFlight(fx2) do n = n + 1 if n > 5000 then break end end
  check(perch and sky.taken[perch] == nil, "...and freeing it once down")
  Config.FLYERS.land.perchChance = saved

  local dep = sky:planDeparture(e)
  eq(dep.kind, "leave", "a departure")
  local last = dep.plan.phases[#dep.plan.phases]
  check(last.to.h >= 0.55 and last.fadeOut, "it climbs away mid or high, fading at the end")
end

-- ------- overhead passers: rare, one at a time, across the TOP of the screen on an arc
do
  local sky = SkyFlyers.new(mod)
  sky:onMapEntered("ROUTE_104")
  local cam = { x = 160, y = 320 }
  sky:collectActors({}, cam.x, cam.y)
  player.x, player.y = 25, 35
  local vw, vh = fake.viewSize()
  local band = Config.FLYERS.passer.band * vh
  local worst, maxN, passers, straight = -1e9, 0, 0, false
  local seenIds = {}
  for t = 1, 60 * 240 do
    sky.timers.perch, sky.timers.dive = 99999, 99999
    sky:tick()
    -- the view scrolls a little now and then (the player walking)
    if t % 40 == 0 then cam.x = cam.x + 16 end
    local actors = {}
    sky:collectActors(actors, cam.x, cam.y)
    local n = 0
    for _, b in ipairs(sky.birds) do
      if b.kind == "passer" then
        n = n + 1
        if not seenIds[b.id] then
          seenIds[b.id] = true
          passers = passers + 1
          if (b.plan.phases[1].curve or 0) == 0 then straight = true end
        end
        local p = FlightPath.look(b.h).parallax
        local _, sy = FlightPath.toScreen(b.x, b.y, p, cam.x, cam.y, vw, vh)
        worst = math.max(worst, sy + 16) -- its feet
      end
    end
    maxN = math.max(maxN, n)
  end
  check(passers >= 2 and passers <= 9, "4 minutes: a few passers, not a flock (" .. passers .. ")")
  eq(maxN, 1, "never more than one overhead at a time")
  check(worst <= band + 0.5, ("their feet stay in the top band of the screen (lowest %.0f, band %.0f)"):format(worst, band))
  check(not straight, "never a straight line: always an arc")
end

-- ------- swoops stay clear of the player
do
  local sky = SkyFlyers.new(mod)
  sky:onMapEntered("ROUTE_104")
  sky:collectActors({}, 0, 0)
  player.x, player.y = 15, 10 -- the middle of the 30 x 20 view
  local worst = math.huge
  for k = 1, 40 do
    local cx, cy = (k % 2 == 0) and 4 or 26, 2 + (k % 16)
    local e = { id = 100 + k, cellX = cx, cellY = cy, dex = 276, isFlyer = true,
                renderer = V.require("renderer_factory").new(mod, 276, false, "pokemmo", "land") }
    for _, fx in ipairs({ sky:planArrival(e), sky:planDeparture(e) }) do
      local ph = fx.plan.phases[1]
      local a, b = ph.from, ph.to
      worst = math.min(worst, SkyFlyers._closestTo(a, b, ph.curve, player.x * 16, player.y * 16))
      local sx, sy = FlightPath.toScreen(fx.kind == "land" and a.x or b.x, fx.kind == "land" and a.y or b.y,
        FlightPath.look(fx.kind == "land" and a.h or b.h).parallax, 0, 0, 480, 320)
      check(sx < 0 or sx > 480 or sy < 0 or sy > 320, "a swoop starts / ends off screen") if not (sx < 0 or sx > 480 or sy < 0 or sy > 320) then break end
      check(ph.curve ~= 0, "...on an arc")
    end
  end
  check(worst >= 4 * 16 - 1, ("no swoop path comes within 3 tiles of the player (closest %d px)"):format(math.floor(worst)))
  check(not sky:clearOfPlayer(17, 12) and sky:clearOfPlayer(19, 10), "clearOfPlayer: 3 tiles is too close, 4 is not")
  player.x, player.y = 0, 19
end

if failures > 0 then
  io.stderr:write(failures .. " failure(s)\n")
  os.exit(1)
end
print("sky_flyers_unit_test: all passed")
