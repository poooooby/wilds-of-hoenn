-- Run: lua tests/fly_mount_unit_test.lua
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
local function near(a, b) return math.abs(a - b) < 1e-9 end

-- a V whose engine_patch is a stub (FlyMount takes everything else through deps)
local fakeEP = { playerTraveling = function() return false end }
local modules = { engine_patch = fakeEP }
local V = { path = "." }
function V.require(name)
  if modules[name] ~= nil then return modules[name] end
  modules[name] = assert(loadfile("lib/" .. name .. ".lua"))(V)
  return modules[name]
end
local FlyMount = V.require("fly_mount")
local Config = V.require("config")

-- ------- resolve: the chosen one, else the first that knows Fly, else nil (Pidgeot)
do
  local knowsSet = {}
  local function knows(m) return knowsSet[m] == true end
  local pidgeot, swellow, egg, bulba = { species = 18 }, { species = 277 }, { species = 18, isEgg = true }, { species = 1 }
  knowsSet[pidgeot], knowsSet[swellow], knowsSet[egg] = true, true, true
  check(FlyMount.resolve(swellow, { pidgeot, swellow }, knows) == swellow, "the Pokemon chosen for Fly carries you")
  check(FlyMount.resolve(bulba, { bulba, swellow }, knows) == swellow, "chosen without Fly: the first that knows it")
  check(FlyMount.resolve(nil, { egg, bulba, pidgeot }, knows) == pidgeot, "eggs are skipped")
  check(FlyMount.resolve(bulba, { bulba }, knows) == nil, "nobody knows Fly: nil (the fallback species)")
end

-- ------- the option: off unless switched on
check(Config.flyMountOn(nil) == false, "Fly Mount is off by default")

-- ------- no flying art: Pidgeot flies for it
do
  local nf = Config.FLY_MOUNT.noFlight
  check(FlyMount.cannotFly(644, nf) and FlyMount.cannotFly("646-black", nf), "Zekrom and every Kyurem have no flying art")
  check(FlyMount.cannotFly(487, nf) and not FlyMount.cannotFly("487-origin", nf), "Giratina's Altered Forme none, its Origin Forme flies")
  check(not FlyMount.cannotFly(6, nf) and not FlyMount.cannotFly(384, nf), "Charizard and Rayquaza fly themselves")
end

-- ------- geometry
do
  local cx, cy = FlyMount.birdCentre(160, 96, { x = 120, x2 = 0, y = 72, y2 = 0 })
  check(cx == 168 and cy == 96, "a bird on the player's spot is centred on their tile (as draw_bird)")
  cx, cy = FlyMount.birdCentre(160, 96, { x = 120, x2 = -40, y = 0, y2 = 30 })
  check(cx == 128 and cy == 54, "...and moves with the bird's offsets")
  local cfg = { minScale = 0.05, maxScale = 1.6 }
  check(FlyMount.scaleOf({}, cfg) == 1, "no zoom: scale 1")
  check(near(FlyMount.scaleOf({ aff = { scale = 512 } }, cfg), 1.6), "a big zoom is capped (the rider is not scaled)")
  check(near(FlyMount.scaleOf({ aff = { scale = 8 } }, cfg), 0.05), "...a tiny one floored")
  check(near(FlyMount.scaleOf({ aff = { scale = 192 } }, cfg), 0.75), "...in between kept")
  local tx, ty = FlyMount.tileFor(100, 50, 20, 1, 4)
  check(tx == 92 and ty == 50 + 4 + 10 - 16, "the art's middle sits `seat` px below the bird's centre")
end

-- ------- the seat: where a point of the art lands, gen3-hd-sprites' growth included
do
  local x, y = FlyMount.seatPoint(2, 3, 1, 1, 10, 20, 15, 5)
  check(x == 17 and y == 8, "seatPoint: plain, the point's own px from the art's origin")
  x, y = FlyMount.seatPoint(2, 3, 2, 1, 10, 20, 15, 5)
  check(x == 32 and y == 13, "...grown by the draw scale")
  x, y = FlyMount.seatPoint(0, 0, 1, 2, 10, 20, 10, 20)
  check(x == 10 and y == 20, "...a library-grown sprite keeps its pivot")
  x, y = FlyMount.seatPoint(0, 0, 1, 2, 10, 20, 15, 5)
  check(x == 20 and y == -10, "...and grows everything else away from it")
  local seats = assert(loadfile("lib/fly_seats.lua"))()
  check(seats.pmd[6] and seats.pmd[384] and seats.hgss[6] and seats.hgss[384], "seats baked for Charizard and Rayquaza, both styles")
  local ok = true
  for _, style in ipairs({ "pmd", "hgss" }) do
    for k, list in pairs(seats[style]) do
      if #list < 2 or #list % 2 ~= 0 then ok = false; print("bad seat list", style, k) end
    end
  end
  check(ok, "every seat list is x, y pairs (one per frame)")
end

-- ------- tick / collectActors / active, with a fake engine
do
  local anims = {}
  local built = {}
  local traveling = false
  local swellow = { species = 277, personality = 5 }
  local drawn = {}
  local function newRenderer(_, key, shiny, style, pres)
    local r = { key = key, shiny = shiny, style = style, pres = pres, isPmd = true, advanced = 0 }
    function r:advanceAs(anim, speed, fb) self.advanced = self.advanced + 1; self.lastAnim = anim; self.fb = fb end
    function r:headLift() return 20 end
    function r:draw(x, y, camX, camY, facing) drawn[#drawn + 1] = { x = x, y = y, facing = facing, scale = self.act and self.act.scale } end
    built[#built + 1] = r
    return r
  end
  local on = true
  local lifted = false
  local fm = FlyMount.new(nil, {
    liftPlayer = function(v) lifted = v end,
    newRenderer = newRenderer,
    flyAnims = function(out)
      for i = 1, #anims do out[i] = anims[i] end
      for i = #out, #anims + 1, -1 do out[i] = nil end
      return #anims
    end,
    playerPixel = function() return 160, 96 end,
    playerRide = function() return -36, -18, 3 end,
    partyMons = function() return { { species = 1 }, swellow } end,
    knows = function(m) return m == swellow end,
    artKeyFor = function(_, sp) return sp == 277 and 277 or nil end,
    isShiny = function() return false end,
    on = function() return on end,
    traveling = function() return traveling end,
  })
  fm:onFlyStarted(nil)
  fm:tick()
  check(not fm:active(), "no cutscene yet: nothing to stand in for")
  local bird = { x = 120, x2 = 0, y = 72, y2 = 0, cb = "swoop", attached = false }
  anims[1] = { kind = "fly_out", bird = bird }
  fm:tick()
  check(fm:active() and #built == 1 and built[1].key == 277, "the first party Pokemon that knows Fly is the mount")
  check(built[1].lastAnim == "fly" and built[1].fb == "walk", "PMD: its fly sheet, its walk loop without one")
  built[1].info = { mount = {} }
  fm:tick()
  check(built[1].lastAnim == "mount", "PMD with a mount sheet: that (turned toward the camera, like FireRed's bird)")
  built[1].info = nil
  local actors = {}
  fm:collectActors(actors)
  local a = actors[1]
  check(#actors == 1 and a.kind == "fly_mount", "one mount per bird")
  check(a.fixedPriority == true and a.priority == 1, "flying free it goes over everything, like the bird")
  a.draw(a, 0, 0)
  check(drawn[1] and drawn[1].facing == "left", "it faces left")
  check(drawn[1].x == 168 - 8, "drawn on the bird's centre")
  bird.attached, bird.cb = true, "with_player"
  bird.aff = { scale = 900 }
  actors = {}
  fm:collectActors(actors)
  a = actors[1]
  check(a.fixedPriority == true and a.priority == 1 and a.subpriority == 2 and a.y == 96 - 18,
    "carrying the player: over everything, drawn just before them")
  fm:tick()
  check(lifted == true, "...and the player lifted over everything with it")
  a.draw(a, 0, 0)
  check(near(drawn[2].scale, Config.FLY_MOUNT.maxScale), "its zoom capped")
  bird.cb, bird.attached, bird.aff = "return", false, nil
  actors = {}
  fm:collectActors(actors)
  actors[1].draw(actors[1], 0, 0)
  check(drawn[3].facing == "down", "coming back into its ball it faces down")
  bird.invisible = true
  actors = {}
  fm:collectActors(actors)
  check(#actors == 0, "a bird the engine has hidden is not drawn")
  -- between fly_out and fly_in: still travelling, kept
  anims[1] = nil
  traveling = true
  fm:tick()
  check(fm.renderer ~= nil and not fm:active(), "between the two cutscenes the mount is kept (not drawn)")
  anims[1] = { kind = "fly_in", bird = { x = 120, y = 72, cb = "with_player", attached = true } }
  fm:tick()
  check(#built == 1 and fm:active(), "...and the same one flies the arrival")
  anims[1] = nil
  traveling = false
  fm:tick()
  check(fm.renderer == nil and not fm.pending, "landed: this Fly is forgotten")
  check(lifted == false, "...the player put back")
  -- option off: never active, the engine's bird stays
  on = false
  fm:onFlyStarted(swellow)
  anims[1] = { kind = "fly_out", bird = { x = 120, y = 72, cb = "swoop" } }
  fm:tick()
  check(not fm:active(), "Fly Mount off: the engine's bird")
  on = true
  -- nobody knows Fly: Pidgeot
  fm:reset()
  fm.deps.knows = function() return false end
  fm:onFlyStarted({ species = 1 })
  fm:tick()
  check(built[#built].key == Config.FLY_MOUNT.fallbackDex and built[#built].shiny == false, "nobody knows Fly: Pidgeot")
  fm:reset()
  local zekrom = { species = 644 }
  fm.deps.knows = function(m) return m == zekrom end
  fm.deps.artKeyFor = function(_, sp) return sp end
  fm:onFlyStarted(zekrom)
  fm:tick()
  check(built[#built].key == Config.FLY_MOUNT.fallbackDex, "Zekrom (no flying art): Pidgeot carries you")
end

if failures > 0 then
  io.stderr:write(failures .. " failure(s)\n")
  os.exit(1)
end
print("fly_mount_unit_test: all passed")
