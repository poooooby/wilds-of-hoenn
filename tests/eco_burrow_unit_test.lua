-- Run: lua tests/eco_burrow_unit_test.lua
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

-- a 20 x 20 field; column 10 is a path (not encounter ground)
local player = { x = 30, y = 30 }
local fake = {
  terrainAt = function(x, y)
    if x >= 0 and y >= 0 and x < 20 and y < 20 and x ~= 10 then return "land" end
    return nil
  end,
  canEnter = function() return true end,
  isWater = function() return false end,
  isWarpCell = function(x, y) return x == 3 and y == 3 end,
  playerCell = function() return player end,
}
local modules = { engine_patch = fake }
local V = { path = "." }
function V.require(name)
  if modules[name] == nil then modules[name] = assert(loadfile("lib/" .. name .. ".lua"))(V) end
  return modules[name]
end
local Config = V.require("config")
local Eco = V.require("eco")
local EcoBurrow = V.require("eco_burrow")

local held = {}
local sm = {
  _cellFree = function(_, x, y) return not held[x .. "," .. y] end,
  occupiedBy = function() return nil end,
  source = { canStay = function(_, x) return x < 18 end }, -- x 18-19: out of reach
}

local function mon()
  local r = { isPmd = true, info = {}, anim = "idle" }
  function r:advance(moving) self.anim = moving and "walk" or "idle" end
  return { id = 1, species = 50, terrain = "land", cellX = 5, cellY = 5, px = 80, py = 80, facing = "down",
           state = "available", renderer = r, profile = { burrower = true, social = "solo" } }
end
local function ctx(now) return { now = now or 0, rng = function(a) return a end, player = player } end

-- ------- pure parts
do
  local s = { sinkTicks = 20 }
  eq(EcoBurrow.sinkAt(s, 0), 0, "not begun: on top")
  eq(EcoBurrow.sinkAt(s, 20), 1, "after its sink: gone")
  eq(EcoBurrow.sinkAt(s, 200), 1, "...and stays gone until it rises")
  s.riseAt = 100
  check(EcoBurrow.sinkAt(s, 110) > 0 and EcoBurrow.sinkAt(s, 110) < 1, "rising: partly up")
  eq(EcoBurrow.sinkAt(s, 120), 0, "risen: on top")
  check(#EcoBurrow.dust(0, 3) > 0, "dust at the puff")
  eq(#EcoBurrow.dust(40, 3), 0, "...gone after its life")
  check(#EcoBurrow.mound(20) > 20, "a mound of earth at the hole")
  check(EcoBurrow.mound(1)[1][3] < EcoBurrow.mound(20)[1][3], "...rising out of the ground")
  eq(#EcoBurrow.mound(200), 0, "...and gone after a while")
  local up = true
  for _, d in ipairs(EcoBurrow.dust(4, 3)) do if d[2] > 1 then up = false end end
  check(up, "...thrown up, never below the ground")
  -- drawn every frame from one reused buffer: same particles, no new tables
  local buf = {}
  local _, n = EcoBurrow.dust(4, 3, buf)
  local first = buf[1]
  local fresh = EcoBurrow.dust(4, 3)
  eq(n, #fresh, "into a buffer: as many particles")
  check(buf[1][1] == fresh[1][1] and buf[1][2] == fresh[1][2] and buf[1][3] == fresh[1][3], "...the same ones")
  local _, m = EcoBurrow.mound(20, 0, buf)
  eq(m, #EcoBurrow.mound(20), "the mound into the same buffer")
  check(buf[1] == first, "...its entries reused")
  local _, z = EcoBurrow.dust(40, 3, buf)
  eq(z, 0, "...none once the dust is gone (the old entries not counted)")
  local fx = { { kind = "mound", life = 70, parts = EcoBurrow.mound, color = { 0.5, 0.4, 0.2 }, x = 8, y = 14,
                 sortY = 2, age = 10, seed = 0 } }
  local actors = {}
  V.require("eco_water").collectFx({ id = 4, ecoFx = fx }, actors)
  check(#actors == 1 and actors[1].parts == EcoBurrow.mound and actors[1].age == 10, "one actor that draws its parts itself")
end

-- ------- where it comes up
do
  local e = mon()
  local cfg = Config.ECO.burrow
  for _ = 1, 30 do
    local x, y = EcoBurrow.spot(e, sm, ctx(), cfg.hop, nil, math.random)
    local d = math.max(math.abs(x - 5), math.abs(y - 5))
    if d < cfg.hop[1] or d > cfg.hop[2] or x == 10 or (x == 3 and y == 3) then
      check(false, "a spot within its hop, on its own ground, not a doorway: " .. x .. "," .. y)
      break
    end
  end
  check(true, "spots are within its hop, on its own ground, never a doorway")
  player.x, player.y = 4, 5
  local x = EcoBurrow.spot(e, sm, ctx(), cfg.fleeHop, { x = 4, y = 5 }, function(a) return a end)
  check(x and x >= 5 + cfg.fleeHop[1], "ducking from the player: it comes up away from them (x " .. tostring(x) .. ")")
  local far = mon()
  far.cellX = 15
  local fx = EcoBurrow.spot(far, sm, ctx(), { 3, 4 }, { x = 4, y = 5 }, function(a) return a end)
  check(fx == nil or fx < 18, "never out of the player's reach")
  player.x, player.y = 30, 30
end

-- ------- a burrow from start to end
do
  local e = mon()
  local st = EcoBurrow.state(e, sm, ctx(), nil, function(a) return a end)
  check(st ~= nil, "a burrow is planned")
  Eco.start(e, "burrow", st)
  local n = st.sinkTicks
  for t = 1, n - 1 do Eco.step(e, ctx(t), sm) end
  check(e.renderer.act and e.renderer.act.sink > 0.5 and e.renderer.act.sink < 1, "going down")
  check(e.eco.untouchable == nil, "...still met while it goes down")
  check(e.ecoFx and #e.ecoFx > 0, "...in a puff of dust")
  local mound = false
  for _, f in ipairs(e.ecoFx) do if f.kind == "mound" then mound = true end end
  check(mound, "...digging a mound of earth")
  Eco.step(e, ctx(n), sm)
  eq(e.renderer.act.sink, 1, "under")
  check(e.eco.untouchable, "...not met under the ground")
  eq(e.cellX, st.rx, "...already at the cell it comes up on")
  -- the player stands on that cell when it is due up: it waits
  player.x, player.y = e.cellX, e.cellY
  for t = n + 1, n + st.under + 10 do Eco.step(e, ctx(t), sm) end
  check(e.eco and e.eco.untouchable and not e.eco.riseAt, "the player on its cell: it stays under")
  player.x, player.y = 30, 30
  for t = n + st.under + 11, n + st.under + 200 do
    if not e.eco then break end
    Eco.step(e, ctx(t), sm)
  end
  eq(e.eco, nil, "the player gone: it comes up and is done")
  eq(e.renderer.act, nil, "...whole again")
  eq(e.px, e.cellX * 16, "...standing on its new cell")
end

-- ------- startled, it ducks under away from the player
do
  local e = mon()
  check(EcoBurrow.duck(e, sm, ctx(), 6, 5), "a startled burrower ducks underground")
  eq(e.eco and e.eco.kind, "burrow", "...burrowing")
  check(e.eco.rx < 5, "...coming up away from the player")
  local bird = mon()
  bird.isFlyer = true
  check(not EcoBurrow.duck(bird, sm, ctx(), 6, 5), "a flyer never burrows")
  local plain = mon()
  plain.profile = { social = "solo" }
  check(not EcoBurrow.duck(plain, sm, ctx(), 6, 5), "nor a Pokemon that is no burrower")
  -- the chooser: now and then, away from the player
  local c = mon()
  local now, picked = 0, nil
  for t = 0, 4000, 60 do
    now = t
    local kind = EcoBurrow.choose(c, { now = now, rng = math.random, player = player }, sm)
    if kind then picked = kind break end
  end
  eq(picked, "burrow", "left alone, it burrows now and then")
  player.x, player.y = 6, 5
  local close = mon()
  close.ecoDue = { burrow = 0 }
  eq(EcoBurrow.choose(close, { now = 10, rng = math.random, player = player }, sm), nil, "never with the player right there")
  player.x, player.y = 30, 30
end

if failures > 0 then
  io.stderr:write(failures .. " failure(s)\n")
  os.exit(1)
end
print("all eco_burrow tests passed")
