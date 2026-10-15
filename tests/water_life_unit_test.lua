-- Run: lua tests/water_life_unit_test.lua
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

math.randomseed(5)

-- species: 1 Magikarp, 2 Goldeen, 3 Horsea, 4 Tentacool, 5 Wailmer, 6 Feebas, 7 Octillery,
-- 8 Poliwag (a pond)
local NAT = { 129, 118, 116, 72, 320, 349, 224, 60 }
local EGG = { { 12, 14 }, { 12, 12 }, { 2, 14 }, { 9, 9 }, { 5, 12 }, { 2, 14 }, { 2, 12 }, { 2, 2 } }
local HEIGHT = { 9, 6, 4, 9, 20, 6, 9, 6 }
local fake = {}
local optionStore = { sprite_style = "pokemmo" }
local mod = { options = { get = function(_, k) return optionStore[k] end }, read = function() return nil end }
local modules = { engine_patch = fake }
local V = { path = ".", mod = mod }
function V.require(name)
  if modules[name] ~= nil then return modules[name] end
  local value = assert(loadfile("lib/" .. name .. ".lua"))(V)
  modules[name] = value
  return value
end
fake.nationalFor = function(s) return NAT[s] end
fake.eggGroups = function(s) local e = EGG[s] if e then return e[1], e[2] end end
fake.heightDm = function(s) return HEIGHT[s] end
local pond = false
fake.tableFor = function()
  if pond then return { fishing = { slots = { { species = 1 }, { species = 8 } } } } end
  return { fishing = { slots = { { species = 1 }, { species = 1 }, { species = 2 }, { species = 5 } } },
           water = { slots = { { species = 4 }, { species = 3 }, { species = 6 }, { species = 7 } } } }
end
fake.mapType = function() return 3 end
fake.isWater = function(x, y) return x >= 0 and y >= 0 and x < 30 and y < 20 end -- a 30 x 20 lake
fake.objectOn = function() return false end
local ripples = 0
fake.startRipple = function() ripples = ripples + 1 return true end
fake.viewSize = function() return 480, 320 end
fake.playerCell = function() return { x = 0, y = 0, moving = false } end

local WL = V.require("water_life")
local Config = V.require("config")

-- ------- who leaps, who surfaces
do
  check(WL.isFish(1), "Magikarp leaps")
  check(WL.isFish(2), "Goldeen leaps")
  check(WL.isFish(6), "Feebas leaps (a fish, though not Water 2)")
  check(not WL.isFish(3), "never Horsea")
  check(not WL.isFish(7), "never Octillery (not a fish)")
  check(not WL.isFish(4), "Tentacool is no fish")
  check(not WL.isFish(5), "Wailmer is too big to leap")
  check(WL.isWhale(5), "Wailmer surfaces")
  local fish, whales = WL.poolFor("ROUTE_105")
  eq(#fish, 3, "the map's fish: Magikarp, Goldeen, Feebas")
  eq(#whales, 1, "...and its whale: Wailmer")
end

-- ------- splash and spray particles
do
  check(#WL.splash(1, 3) > 0, "a splash throws droplets")
  eq(#WL.splash(30, 3), 0, "...that are gone after a moment")
  local up = false
  for _, d in ipairs(WL.splash(4, 3)) do if d[2] < 0 then up = true end end
  check(up, "...upward first")
  local s = WL.spray(10, 48, 2)
  check(#s > 0, "a whale's spout throws droplets")
  local high = 0
  for _, d in ipairs(WL.spray(15, 48, 2)) do high = math.min(high, d[2]) end
  check(high < -12, "...high up (" .. high .. " px)")
  eq(#WL.spray(48 + 40, 48, 2), 0, "...and is over after its time")
end

-- ------- a leap: out of the water in an arc and back in
do
  local cfg = Config.WATER_LIFE.leap
  local c = { cx = 5, cy = 5, t = 0, n = 40, dir = 1, renderer = {} }
  local _, _, a0 = WL._leapState(c, cfg)
  check(a0.sink > 0.9, "it starts under the surface")
  c.t = 20
  local x, _, mid = WL._leapState(c, cfg)
  check(mid.sink == 0 and mid.dy < -cfg.height + 1, "mid-leap: all out of the water, at the top of its arc")
  check(x > 5 * 16, "...carried forward")
  c.t = 40
  local _, _, a1 = WL._leapState(c, cfg)
  check(a1.sink > 0.9 and math.abs(a1.dy) < 1, "it ends back under")
end

-- ------- a whale: rises, stays up, sinks
do
  local cfg = Config.WATER_LIFE.whale
  local c = { cx = 5, cy = 5, t = 0, stay = 200, drift = 1 }
  local _, _, a = WL._whaleState(c, cfg)
  check(a.sink > 0.9, "a whale starts under")
  c.t = cfg.riseTicks + 100
  local x, _, b = WL._whaleState(c, cfg)
  eq(b.sink, 0, "...lies at the surface a while")
  check(x > 5 * 16 and x < 6 * 16, "...drifting slowly")
  c.t = cfg.riseTicks * 2 + 200
  local _, _, d = WL._whaleState(c, cfg)
  check(d.sink > 0.9, "...and sinks back under")
end

-- ------- in play
do
  local wl = WL.new(mod)
  wl:onMapEntered("ROUTE_105")
  check(wl.allowed, "outdoors: life in the water")
  wl:collectActors({}, 0, 0)
  local seen = {}
  for _ = 1, 60 * 120 do
    wl:tick()
    for _, c in ipairs(wl.creatures) do seen[c.kind] = true end
    check(wl:count("leap") <= Config.WATER_LIFE.leap.max, "never too many leaping at once")
    if wl:count("leap") > Config.WATER_LIFE.leap.max then break end
  end
  check(seen.leap, "fish leap")
  check(seen.whale, "a whale surfaces")
  check(ripples > 0, "...with ripples")
  local actors = {}
  wl:collectActors(actors, 0, 0)
  wl:onMapExited()
  eq(wl:count(), 0, "leaving the map clears the water")
  fake.mapType = function() return 8 end
  wl:onMapEntered("HOUSE")
  check(not wl.allowed, "indoors: nothing")
  fake.mapType = function() return 3 end
  optionStore.water_life = false
  wl:onMapEntered("ROUTE_105")
  check(not wl.allowed, "Water Life off: nothing")
  optionStore.water_life = nil
end

-- ------- under the sea (a Dive map): every eligible fish of the dex swims by as a shadow
do
  -- 8 Kyogre (legendary: Undiscovered egg group), 9 Sharpedo-sized but 2.4 m (too big)
  NAT[8], EGG[8], HEIGHT[8] = 382, { 15, 15 }, 45
  NAT[9], EGG[9], HEIGHT[9] = 900, { 12, 12 }, 24
  local byNat = {}
  for s, n in pairs(NAT) do byNat[n] = s end
  fake.speciesForNational = function(n) return byNat[n] end
  WL._resetSwimmers()
  local all = WL.allSwimmers()
  local set = {}
  for _, s in ipairs(all) do set[s] = true end
  check(set[1] and set[2] and set[6], "the dex's fish swim under the sea (not just this map's table)")
  check(not set[8], "never a legendary")
  check(not set[9], "nothing massive")
  check(not set[3] and not set[4] and not set[5], "no Horsea, no non-fish, no whale")

  fake.mapType = function() return 5 end
  local wl = WL.new(mod)
  wl:onMapEntered("UNDERWATER_ROUTE124")
  check(wl.allowed and wl.underwater, "a Dive map: life under the sea")
  wl:collectActors({}, 0, 0)
  local seenSchool, maxSwim, bubbles, silhouettes = false, 0, false, true
  for _ = 1, 60 * 90 do
    wl:tick()
    maxSwim = math.max(maxSwim, wl:count("swim"))
    for _, c in ipairs(wl.creatures) do
      if c.kind ~= "swim" then silhouettes = false end
      if not c.renderer.silhouette then silhouettes = false end
      if #c.bubbles > 0 then bubbles = true end
    end
    if wl:count("swim") >= 3 then seenSchool = true end
  end
  check(maxSwim > 0, "fish swim by")
  check(silhouettes, "...as dark shadows, and nothing leaps or surfaces down here")
  check(bubbles, "...trailing bubbles")
  check(seenSchool, "small fish sometimes come as a school")
  local actors = {}
  wl:collectActors(actors, 0, 0)
  local dx, dy, al = WL.bubble(10, 1)
  check(dy < 0 and al < 1, "a bubble rises and fades")
  fake.mapType = function() return 3 end
end

-- ------- the body wiggle: across the way it swims, only while swimming
do
  local w = Config.WATER_LIFE.swim.wiggle
  local v = { facing = "right", flapClock = math.floor(w.ticks / 4) }
  WL._sway(v, true)
  check(v.swayX == 0 and math.abs(v.swayY) > 1.5, "swimming right, it sways up and down")
  v.facing = "up"
  WL._sway(v, true)
  check(v.swayY == 0 and math.abs(v.swayX) > 1.5, "swimming up, it sways side to side")
  WL._sway(v, false)
  check(v.swayX == 0 and v.swayY == 0, "resting: no wiggle")
end

-- ------- Finizen: a dolphin on the sea, alone or (rarely) a pod
do
  local cfg = Config.WATER_LIFE.dolphin
  eq(cfg.species, 963, "Finizen is national dex 963")
  local _, _, sea = WL.poolFor("ROUTE_105")
  check(sea, "a map whose tables hold Tentacool / Wailmer is the sea")
  pond = true
  local _, _, pondSea = WL.poolFor("POND")
  check(not pondSea, "...a pond of Magikarp and Poliwag is not")
  pond = false

  -- one Finizen's run: surface, porpoise in a row of leaps, dive
  local plan = WL.dolphinPlan(3, 1, cfg, function() return true end)
  local kinds = {}
  for _, s in ipairs(plan.segments) do kinds[#kinds + 1] = s.kind end
  eq(table.concat(kinds, ","), "rise,leap,glide,leap,glide,leap,dive", "it surfaces, porpoises three times, dives")
  check(plan.dist > 3 * cfg.leapDist, "...moving along as it goes")
  local x0, l0, r0 = WL.dolphinAt(plan, 0, cfg, 16)
  check(x0 == 0 and l0 == 0 and r0 < 0.05, "at first it is under the water")
  local _, _, rSurface = WL.dolphinAt(plan, cfg.riseTicks - 1, cfg, 16)
  check(math.abs(rSurface - cfg.surfaceShow) < 0.05, "surfaced: only its back and fin show")
  local leap = plan.segments[2]
  local _, lTop, rTop = WL.dolphinAt(plan, leap.t0 + math.floor(leap.n / 2), cfg, 16)
  check(lTop > 15 and rTop == 1, "mid-leap: wholly out of the water, high in its arc")
  local _, lEnd, rEnd = WL.dolphinAt(plan, plan.n + 5, cfg, 16)
  check(lEnd == 0 and rEnd == 0, "after the dive it is gone")
  local back = WL.dolphinPlan(2, -1, cfg)
  check(back.dist < 0, "a run can go either way")

  -- a pod in a ring, taking turns to leap
  local play, n = 600, 4
  local leapers, maxLeapers, seenAt = {}, 0, {}
  for t = 0, play do
    local now = 0
    for k = 1, n do
      local x, y, lift, reveal, facing, leaping = WL.podMember(k, n, t, play, cfg, 16, 1)
      check(math.abs(x) <= cfg.ring[1] + 0.01 and math.abs(y) <= cfg.ring[2] + 0.01, "a pod member keeps to its ring")
      if leaping then now = now + 1 leapers[k] = true end
      if t == play then seenAt[k] = reveal end
      if t == 300 and not leaping then check(math.abs(reveal - cfg.surfaceShow) < 0.01, "at play it rides the surface") end
    end
    maxLeapers = math.max(maxLeapers, now)
  end
  eq(#leapers, n, "every one of the pod leaps")
  check(maxLeapers < n, "...taking turns, never all at once")
  local gone = true
  for k = 1, n do if seenAt[k] > 0.01 then gone = false end end
  check(gone, "at the end they have all gone under")
  local _, _, _, _, f1 = WL.podMember(1, n, 0, play, cfg, 16, 1)
  local _, _, _, _, f2 = WL.podMember(1, n, math.floor(cfg.lapTicks / 4), play, cfg, 16, 1)
  check(f1 ~= f2, "swimming round, it turns as it goes")

  -- only on the sea, rare, sized by its Species Sizes factor (never enlarged)
  local wl = WL.new(mod, { rng = math.random })
  pond = true
  wl:onMapEntered("POND")
  check(not wl.sea and not wl:_spawnDolphin(), "no Finizen on a pond")
  pond = false
  wl:onMapEntered("ROUTE_105")
  check(wl.sea and wl.timers.dolphin ~= nil, "on the sea its timer runs")
  check(cfg.every[1] >= 3600, "...and it is rare (a minute and more apart)")
  local HdField = V.require("hd_field")
  local s = WL.dolphinScale(mod, { isPmd = false })
  check(s <= 1 and math.abs(s - (V.require("HGSS_scale")[963] or 1)) < 1e-9, "Finizen is drawn at its HGSS size, never enlarged")
  check(WL.dolphinScale(mod, { isPmd = true }) == math.min(1, V.require("PMD_scale")[963] or 1), "...and at its PMD size")
  HdField.setSpeciesSizes(false)
  eq(WL.dolphinScale(mod, { isPmd = true }), 1, "Species Sizes off: its own size")
  HdField.setSpeciesSizes(true)
  wl:collectActors({}, 0, 0)
  local spawned, pods = 0, 0
  for _ = 1, 200 do
    wl.creatures = {}
    if wl:_spawnDolphin() then
      spawned = spawned + 1
      if wl.creatures[1].kind == "pod" then pods = pods + 1 end
    end
  end
  check(spawned > 150, "on open sea a Finizen surfaces")
  check(pods > 0 and pods < spawned / 3, "...a pod only now and then")
  -- it plays out without errors and is drawn, puffs and splashes included
  wl.creatures = {}
  wl:_spawnDolphin()
  local drawn, splashes = 0, 0
  for _ = 1, 900 do
    wl:tick()
    local actors = {}
    wl:collectActors(actors, 0, 0)
    for _, a in ipairs(actors) do
      if a.kind == "ow_water_life" then drawn = drawn + 1 elseif a.kind == "ow_water_droplets" then splashes = splashes + 1 end
    end
  end
  check(drawn > 0 and splashes > 0, "it is drawn, with splashes / puffs")
end

if failures > 0 then
  io.stderr:write(failures .. " failure(s)\n")
  os.exit(1)
end
print("water_life_unit_test: all passed")
