-- Run: lua tests/local_scenes_unit_test.lua
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
local mod = { options = { get = function(_, k) return optionStore[k] end }, read = function() return nil end }
local modules = { engine_patch = fake }
local V = { path = ".", mod = mod }
function V.require(name)
  if modules[name] ~= nil then return modules[name] end
  local value = assert(loadfile("lib/" .. name .. ".lua"))(V)
  modules[name] = value
  return value
end
-- a 40 x 30 wood, two rows of trees (x 2..37) the way Gen 3 draws them: a crown row (a wall
-- drawn over actors) in rows 4 and 12, the trees' lower leaves (a wall in the lower layer)
-- in rows 5 and 13; the rows under them open ground
local function tree(x, y) return x >= 2 and x <= 37 and (y == 4 or y == 5 or y == 12 or y == 13) end
fake.mapBounds = function() return 40, 30 end
fake.isWall = function(x, y) return tree(x, y) end
fake.isWater = function() return false end
fake.coversActors = function(x, y) return tree(x, y) and (y == 4 or y == 12) end
fake.objectOn = function() return false end
fake.signCells = function() return {} end
fake.isWarpCell = function() return false end
fake.viewSize = function() return 240, 160 end
fake.mapType = function() return 3 end
local player = { x = 20, y = 20, moving = false, facing = "up" }
fake.playerCell = function() return player end
local busy = false
fake.fieldBusy = function() return busy end
fake.battleActive = function() return false end

local LS = V.require("local_scenes")
local Config = V.require("config")

-- ------- places
do
  eq(LS.placeName("EM_PETALBURG_WOODS"), "PETALBURG_WOODS", "Emerald's prefix comes off")
  eq(LS.placeName("FR_LAVENDER_TOWN"), "LAVENDER_TOWN", "FireRed's too")
  check(LS.placeOf("RU_FORTREE_CITY") and LS.placeOf("SA_FORTREE_CITY") and LS.placeOf("EM_FORTREE_CITY"), "Fortree in Ruby, Sapphire, Emerald")
  check(LS.placeOf("LG_LAVENDER_TOWN"), "Lavender in LeafGreen")
  check(LS.placeOf("EM_ROUTE_101") == nil, "nothing on an ordinary route")
end

-- ------- pure timelines
do
  eq(LS.fade(0, 100, 20), 0, "a ghost starts unseen")
  eq(LS.fade(50, 100, 20), 1, "...is fully there midway")
  eq(LS.fade(100, 100, 20), 0, "...and gone at the end")
  local cfg = Config.LOCAL_SCENES.hang.cocoon
  local c = { drop = 18, down = 60, stay = 300, up = 90 }
  local dy0, _, a0 = LS.hangState(c, cfg, 0)
  check(dy0 < 0 and a0 == 0, "a bug starts up among the leaves, unseen")
  local dyMid, dxMid = LS.hangState(c, cfg, 60 + 90)
  check(dyMid >= 18, "...hangs below it on its thread")
  check(math.abs(dxMid) > 0, "...swinging")
  local dyEnd, _, aEnd = LS.hangState(c, cfg, 60 + 300 + 90)
  check(dyEnd < 0 and aEnd == 0, "...and is reeled back up into them")
  check(LS.treeEdge(10, 5), "a tree's bottom edge over the path is where one hangs")
  check(not LS.treeEdge(10, 4), "...not its crown")
  check(not LS.treeEdge(10, 6), "...not open ground")
  check(not LS.treeEdge(1, 5), "...not where there is no tree")
  local zs = V.require("wild_emote").zzz(100, 40)
  check(#zs >= 2, "a sleeper's z's float up one after another")
  local grew = false
  for _, z in ipairs(zs) do if z[3] > 1 and z[2] < -5 then grew = true end end
  check(grew, "...growing as they rise")
end

local function newScenes()
  local ls = LS.new(mod)
  return ls
end

local function has(ls, kind)
  for _, c in ipairs(ls.scenes) do if c.kind == kind or c == kind then return true end end
  return false
end

local function run(ls, ticks, each)
  for _ = 1, ticks do
    ls:tick()
    if each then each(ls) end
  end
end

-- ------- Petalburg Woods
do
  local ls = newScenes()
  ls:onMapEntered("EM_PETALBURG_WOODS")
  check(ls.place and ls.perches and ls.perches:count() > 0, "Petalburg Woods: its tree tops are found")
  ls:collectActors({}, 0, 0) -- the camera: the view is cells 0..14 x 0..9
  check(ls:start("burmy"), "a Burmy comes down")
  local b = ls.scenes[1]
  check(LS.treeEdge(b.spot.x, b.spot.y), "...from a tree's bottom edge, over open ground")
  for _ = 1, 40 do ls:tick() end
  local actors = {}
  ls:collectActors(actors, 0, 0)
  local thread, sprite = false, nil
  for _, a in ipairs(actors) do
    if a.kind == "ow_silk" then thread = true end
    if a.kind == "ow_local_scene" then sprite = a end
  end
  check(thread, "...on a silk thread")
  check(sprite and sprite.oamPriority == nil, "...drawn as an ordinary actor (under roofs and tree crowns)")
  check(ls:start("sleeper"), "a Slakoth naps on a tree top")
  local slak = ls.scenes[2]
  check(slak.spot ~= b.spot, "...not on a spot already in use")
  run(ls, 120)
  actors = {}
  ls:collectActors(actors, 0, 0)
  local zzz, over = false, false
  for _, a in ipairs(actors) do
    if a.kind == "ow_zzz" then zzz = true end
    if a.kind == "ow_local_scene" and a.oamPriority == 1 then over = true end
  end
  check(zzz, "...z's over it")
  check(over, "...drawn over the tree tops")
  ls:clear()

  check(ls:start("dancer"), "Vigoroth leaps in")
  local d = ls.scenes[1]
  check(d.x < 0 or d.x > 240, "...from off screen")
  local danced, landedX = false, nil
  run(ls, d.n + 5, function(s)
    local c = s.scenes[1]
    if c and c.danceT and c.danceT > 0 then danced = true landedX = c.x end
  end)
  check(danced, "...dances on a tree top")
  eq(landedX, d.spot.x * 16, "...the one it picked")
  eq(ls:count(), 0, "...and is gone again")

  -- on their timers: never more than one occasional and one rare at a time
  ls:onMapEntered("EM_PETALBURG_WOODS")
  ls:collectActors({}, 0, 0)
  local seen, maxOcc = {}, 0
  run(ls, 60 * 600, function(s)
    maxOcc = math.max(maxOcc, s:count("occasional"))
    for _, c in ipairs(s.scenes) do seen[c.kind] = true end
  end)
  eq(maxOcc, 1, "one occasional scene at a time")
  check(seen.burmy and seen.cocoon and seen.sleeper, "Burmy, Silcoon / Cascoon and Slakoth all turn up")
  check(seen.dancer, "...and now and then Vigoroth")

  busy = true
  ls:onMapEntered("EM_PETALBURG_WOODS")
  ls:collectActors({}, 0, 0)
  run(ls, 60 * 120)
  eq(ls:count(), 0, "nothing starts while the field is busy (a cutscene, a trainer)")
  busy = false
end

-- ------- Fortree City
do
  -- a deep wood of tree tops (rows 1-9), a path (row 10) below it
  local wall0, cover0 = fake.isWall, fake.coversActors
  local function deep(x, y) return x >= 1 and x <= 13 and y >= 1 and y <= 9 end
  fake.isWall, fake.coversActors = deep, deep
  check(not LS.deepCanopy({ at = function(_, x, y) return deep(x, y) and { kind = "canopy" } or nil end }, 5, 9),
    "a tree top over a path is not deep enough")
  local ls = newScenes()
  ls:onMapEntered("EM_FORTREE_CITY")
  ls:collectActors({}, 0, 0)
  check(ls:start("tropius"), "a Tropius rises out of the trees")
  local c = ls.scenes[1]
  check(#c.cells >= 2, "...with tree tops to walk on")
  ls:tick()
  check(c.act.reveal < 0.05, "...starting under them")
  run(ls, Config.LOCAL_SCENES.tropius.rise + 5)
  eq(c.act.reveal, Config.LOCAL_SCENES.tropius.half, "...then only its top half shows over them")
  local actors = {}
  ls:collectActors(actors, 0, 0)
  local leaves = false
  for _, a in ipairs(actors) do if a.kind == "ow_leaves" then leaves = true end end
  check(leaves, "...the leaves round its neck drawn over it")
  eq(LS.tropiusReveal(1, 0.4), 0, "all under: nothing shows")
  eq(LS.tropiusReveal(0, 0.4), 0.4, "risen: its head")
  local moved = false
  local sx = c.x + c.y * 1000
  run(ls, 400, function() if c.x + c.y * 1000 ~= sx then moved = true end end)
  check(moved, "...walks across them")
  for _, s in ipairs(c.cells) do check(LS.deepCanopy(ls.perches, s.x, s.y), "...only deep in the tree tops") end
  run(ls, 2000)
  check(not has(ls, c), "...and sinks back under")
  fake.isWall, fake.coversActors = wall0, cover0
end

-- ------- Lavender Town
do
  local ls = newScenes()
  ls:onMapEntered("FR_LAVENDER_TOWN")
  ls:collectActors({}, 0, 0)
  check(ls:start("ghost"), "a ghost drifts in")
  local g = ls.scenes[1]
  check(g.renderer.shade ~= nil, "...dark")
  local maxA, minX, maxX, minY, maxY = 0, 1e9, -1e9, 1e9, -1e9
  run(ls, g.n + 2, function()
    maxA = math.max(maxA, g.alpha)
    minX, maxX = math.min(minX, g.x), math.max(maxX, g.x)
    minY, maxY = math.min(minY, g.y), math.max(maxY, g.y)
  end)
  check(maxA > 0.4 and maxA < 1, "...and see-through")
  check(maxX - minX + maxY - minY > 0, "...wanders about")
  check(minX >= 16 and maxX <= 13 * 16 and minY >= 16 and maxY <= 8 * 16, "...staying in view")
  eq(ls:count(), 0, "...and is gone")

  -- the girl who asks "Do you believe in ghosts?" was told no
  player.facing = "up"
  check(not ls:onScriptText("g3:0817f548", true), "a Yes brings nothing")
  check(ls:onScriptText("g3:0817f568", true), "a No can bring Gengar")
  local gen = ls.scenes[1]
  eq(gen.cx, 20, "...right behind the player")
  eq(gen.cy, 22, "...two steps back (past the follower)")
  eq(gen.facing, "up", "...looking at them")
  busy = true
  run(ls, 120)
  check(math.abs(gen.alpha - Config.LOCAL_SCENES.gengar.alpha) < 1e-6, "...fades in and stays while she talks")
  ls:onScriptEnded()
  busy = false
  run(ls, Config.LOCAL_SCENES.gengar.fade + 2)
  check(not has(ls, "gengar"), "...and fades once she is done")

  -- never on a roof / tree: open ground behind, else next to it, else nothing
  local bx, by = LS.behindCell(1, 10, { 0, -1 }, 2)
  check(bx == 1 and by == 12, "open ground two steps back: there")
  bx, by = LS.behindCell(2, 10, { 0, -1 }, 2)
  check(bx == 1 and by == 12, "a tree two steps back: the nearest open cell beside it")
  bx, by = LS.behindCell(10, 10, { 0, -1 }, 2)
  check(bx ~= nil and not fake.isWall(bx, by), "only trees right behind: the nearest open ground (" .. tostring(bx) .. "," .. tostring(by) .. ")")
  check(not (bx == 10 and (by == 10 or by == 11 or by == 9)), "...never the player's, the follower's or the girl's cell")

  -- the backstop: no script.ended, but the field has been free a while
  ls:onScriptText("g3:0817f544", true)
  run(ls, Config.LOCAL_SCENES.gengar.linger + Config.LOCAL_SCENES.gengar.fade + 5)
  check(not has(ls, "gengar"), "Gengar never stays once the talk is over")

  -- 1 in 4
  local hits = 0
  for _ = 1, 400 do
    if ls:onScriptText("g3:0817f568") then hits = hits + 1 end
    ls:clear()
  end
  check(hits > 60 and hits < 140, "Gengar comes about 1 time in 4 (" .. hits .. "/400)")

  local other = newScenes()
  other:onMapEntered("EM_PETALBURG_WOODS")
  check(not other:onScriptText("g3:0817f568", true), "never anywhere but Lavender Town")
end

-- ------- off
do
  optionStore.local_scenes = false
  local ls = newScenes()
  ls:onMapEntered("EM_PETALBURG_WOODS")
  ls:collectActors({}, 0, 0)
  run(ls, 60 * 300)
  eq(ls:count(), 0, "Local Scenes off: nothing")
  check(not ls:onScriptText("g3:0817f568", true), "...not even Gengar")
  optionStore.local_scenes = nil
end

if failures > 0 then
  io.stderr:write(failures .. " failure(s)\n")
  os.exit(1)
end
print("local_scenes_unit_test: all passed")
