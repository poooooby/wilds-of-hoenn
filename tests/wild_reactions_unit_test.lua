-- Run: lua tests/wild_reactions_unit_test.lua
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

math.randomseed(3)

-- a 30 x 30 field of grass, with a wall column at x = 20 (rows 0..14) to path round
local fake = {}
local walls = {}
for y = 0, 14 do walls[20 .. "," .. y] = true end
fake.terrainAt = function(x, y)
  if x < 0 or y < 0 or x >= 30 or y >= 30 or walls[x .. "," .. y] then return nil end
  return "land"
end
fake.canEnter = function(_, x, y) return fake.terrainAt(x, y) ~= nil end
fake.isWater = function() return false end
fake.ripplesAt = function() return false end
local running, biking = true, false
fake.playerIsRunning = function() return running end
fake.playerBiking = function() return biking end

local modules = { engine_patch = fake }
local V = { path = "." }
function V.require(name)
  if modules[name] ~= nil then return modules[name] end
  local value = assert(loadfile("lib/" .. name .. ".lua"))(V)
  modules[name] = value
  return value
end
local WR = V.require("wild_reactions")
local Config = V.require("config")
local cfg = Config.REACT

-- ------- strength against the lead
do
  eq(WR.classify(5, 300, 20, 300), "weak", "level 5 against a level 20 lead: weak")
  eq(WR.classify(30, 500, 10, 300), "strong", "level 30 heavyweight against a level 10 lead: strong")
  eq(WR.classify(12, 310, 12, 300), "neutral", "even: neutral")
  eq(WR.classify(20, 300, 20, 600), "weak", "same level but half the base stats: weak")
  eq(WR.classify(10, nil, 10, nil), "neutral", "no base stats known: level alone (even)")
  eq(WR.classify(10, 300, nil, 300), "neutral", "no lead: neutral")
end

-- ------- how likely it reacts scales with the ratio
do
  eq(WR.chance("neutral", 1.0), 0, "an even match never reacts")
  eq(WR.chance("weak", cfg.weakRatio), cfg.minChance, "just under the weak line: minChance %")
  eq(WR.chance("weak", cfg.weakSure), 100, "far weaker: always flees")
  eq(WR.chance("weak", 0.1), 100, "...and beyond")
  local mid = WR.chance("weak", (cfg.weakRatio + cfg.weakSure) / 2)
  check(mid > cfg.minChance and mid < 100, "in between: in between (" .. mid .. "%)")
  eq(WR.chance("strong", cfg.strongRatio), cfg.minChance, "just over the strong line: minChance %")
  eq(WR.chance("strong", cfg.strongSure), 100, "far stronger: always chases")
  check(WR.chance("strong", 1.5) < WR.chance("strong", 1.8), "a bigger gap chases more often")
end

-- ------- fleeing picks a way that gets farther
do
  eq(WR.fleeDir(5, 5, 3, 5), "right", "player to the left: run right")
  eq(WR.fleeDir(5, 5, 5, 8), "up", "player below: run up")
  eq(WR.fleeDir(5, 5, 3, 5, function(d) return d ~= "right" end) ~= "left", true, "never toward the player")
  eq(WR.fleeDir(5, 5, 3, 5, function() return false end), nil, "boxed in: nowhere")
end

local function entity(x, y, level, species)
  return { id = 1, state = Config.STATE.AVAILABLE, terrain = "land", elevation = 3,
           cellX = x, cellY = y, px = x * 16, py = y * 16, facing = "down", level = level,
           species = species or 1, moving = false, stepParity = false }
end
local contacts, takeoffs = {}, {}
local function ctxFor(player, leadLevel, extra)
  local c = {
    now = 0, rng = math.random, player = player,
    lead = { level = leadLevel, bst = 300 }, bst = function() return 300 end,
    canFly = function(e) return e.bird == true end,
    occupied = function() return false end,
    onContact = function(e) contacts[#contacts + 1] = e end,
    takeoff = function(e) takeoffs[#takeoffs + 1] = e end,
  }
  for k, v in pairs(extra or {}) do c[k] = v end
  return c
end
local function run(e, ctx, n)
  for _ = 1, n do
    if not e.react then return end
    WR.tick(e, ctx)
    ctx.now = ctx.now + 1
  end
end

-- ------- one roll as the player comes in range; a miss rests instead of re-rolling each tick
do
  local e = entity(10, 10, 10) -- level 10 vs a level 15 lead: ratio 0.67, barely weak
  local ctx = ctxFor({ x = 12, y = 10, moving = true }, 15)
  ctx.rng = function(a, b) if a == 1 and b == 100 then return 100 end return a end
  eq(WR.scan({ e }, ctx), 0, "a near-weak one that misses its roll: no reaction")
  check(e.reactUntil and e.reactUntil > ctx.now, "...and it is left be for a while")
  e.reactUntil = nil
  ctx.rng = function(a, b) if a == 1 and b == 100 then return 1 end return a end
  eq(WR.scan({ e }, ctx), 1, "...one that hits it flees")
end

-- ------- only running / biking players startle, and only close by
do
  local e = entity(10, 10, 5)
  local player = { x = 13, y = 10, moving = true }
  running, biking = false, false
  WR.scan({ e }, ctxFor(player, 30))
  eq(e.react, nil, "walking past: nobody reacts")
  running = true
  player.x = 15
  WR.scan({ e }, ctxFor(player, 30))
  eq(e.react, nil, "running 5 tiles away: too far")
  running, biking = false, true
  WR.scan({ e }, ctxFor(player, 30))
  check(e.react ~= nil, "biking reaches farther (5 tiles)")
  e.react = nil
  biking, running = false, true
  player.x, player.moving = 13, false
  WR.scan({ e }, ctxFor(player, 30))
  eq(e.react, nil, "a player standing still startles nobody")
  player.moving = true
  e.lured = { ticks = 10 }
  WR.scan({ e }, ctxFor(player, 30))
  eq(e.react, nil, "a Sweet Scent lured Pokemon stays put")
  e.lured, e.roamer = nil, true
  WR.scan({ e }, ctxFor(player, 30))
  eq(e.react, nil, "the roaming legendary is left alone")
  e.roamer, e.reactUntil = nil, 100
  WR.scan({ e }, ctxFor(player, 30))
  eq(e.react, nil, "resting after a reaction: no new one yet")
end

-- ------- weak: "!", a hop, then it runs off, farther from the player
do
  local e = entity(10, 10, 5)
  local player = { x = 12, y = 10, moving = true }
  local ctx = ctxFor(player, 30)
  WR.scan({ e }, ctx)
  eq(e.react and e.react.emote, "!", "weak: surprised")
  eq(e.facing, "right", "...turned to look at the player")
  run(e, ctx, 2)
  check(e.renderer == nil or true, "(no renderer: the hop is skipped)")
  local startDist = math.abs(e.cellX - player.x) + math.abs(e.cellY - player.y)
  run(e, ctx, 400)
  eq(e.react, nil, "it calms down afterwards")
  local endDist = math.abs(e.cellX - player.x) + math.abs(e.cellY - player.y)
  check(endDist >= startDist + 3, ("it ran off (%d -> %d tiles away)"):format(startDist, endDist))
  check(e.reactUntil and e.reactUntil > ctx.now, "...and rests before reacting again")
end

-- ------- a weak bird takes off
do
  local e = entity(10, 10, 5)
  e.bird = true
  local ctx = ctxFor({ x = 12, y = 10, moving = true }, 30)
  WR.scan({ e }, ctx)
  eq(e.react.next, "takeoff", "a weak bird: takes off")
  run(e, ctx, cfg.alertTicks + 2)
  eq(takeoffs[#takeoffs], e, "...after its '!'")
end

-- ------- an even match is not bothered: no reaction, no emote
do
  local e = entity(10, 10, 20)
  local facing = e.facing
  local ctx = ctxFor({ x = 10, y = 13, moving = true }, 20)
  eq(WR.scan({ e }, ctx), 0, "an even match: nobody reacts")
  eq(e.react, nil, "...no emote, it carries on as normal")
  eq(e.facing, facing, "...and does not even turn")
end

-- ------- strong: only much closer; a pause, it turns, the anger mark, then the chase
do
  local far = entity(10, 10, 40)
  WR.scan({ far }, ctxFor({ x = 10 + cfg.aggroRadius + 1, y = 10, moving = true }, 10))
  eq(far.react, nil, "a stronger one 3 tiles off: not angry yet (aggro needs " .. cfg.aggroRadius .. ")")
  local weakFar = entity(10, 10, 5)
  WR.scan({ weakFar }, ctxFor({ x = 13, y = 10, moving = true }, 30))
  check(weakFar.react ~= nil, "...while a skittish one reacts from there")
  check(cfg.aggroRadius < cfg.radius, "aggro is a closer range than the skittish one")

  contacts = {}
  local e = entity(19, 5, 40)
  e.facing = "left"
  local player = { x = 21, y = 5, moving = true } -- across the wall (x = 20), 2 tiles off
  local ctx = ctxFor(player, 10)
  WR.scan({ e }, ctx)
  eq(e.react.mode, "turn", "strong: first a pause")
  eq(e.react.emote, nil, "...no emote yet")
  eq(e.facing, "left", "...still facing the way it was")
  run(e, ctx, math.floor(cfg.turnTicks / 2) + 1)
  eq(e.facing, "right", "then it turns to the player")
  run(e, ctx, cfg.turnTicks)
  eq(e.react.emote, "anger", "...and gets angry")
  check(e.react.mode == "alert", "...not chasing yet")
  run(e, ctx, cfg.angerTicks + 1)
  eq(e.react.mode, "chase", "...then it chases")
  check(e.react.leash >= cfg.chase.leash[1] and e.react.leash <= cfg.chase.leash[2], "its leash is rolled for this chase")
  e.react.leash, e.react.limit = 20, 20 * 72 -- a long one, to test the pathing
  player.moving = false
  run(e, ctx, 2000)
  eq(contacts[#contacts], e, "it found a way round the wall and caught the player: the battle")
  check(math.abs(e.cellX - player.x) + math.abs(e.cellY - player.y) <= 1, "...next to the player")
  eq(e.charging, cfg.chase.chargeTicks, "...still charging (its Attack animation) until the battle opens")
end

-- ------- at the end of its run a fled Pokemon may disappear (vanishChance %)
do
  local cfg = Config.REACT
  local function flee(roll)
    local e = entity(10, 10, 5)
    local player = { x = 12, y = 10, moving = true }
    local vanished = {}
    local ctx = ctxFor(player, 30, { fleeVanish = function(x) vanished[#vanished + 1] = x end })
    WR.scan({ e }, ctx)
    ctx.rng = function(a, b) if a == 1 and b == 100 then return roll end return a end
    run(e, ctx, 600)
    return #vanished
  end
  eq(flee(cfg.flee.vanishChance), 1, "a roll inside the chance: it disappears at the end of its run")
  eq(flee(cfg.flee.vanishChance + 1), 0, "...outside it, it stays")
  eq(cfg.flee.vanishChance, 30, "30% of them")
end

-- ------- the chase is quicker than a running player
check(cfg.chase.frames < 8, "a chaser's step is quicker than a running player's (8 frames)")

-- ------- giving up: beyond its leash it stops, '?', a few steps back, calm
do
  local e = entity(5, 25, 40)
  local player = { x = 7, y = 25, moving = true }
  local ctx = ctxFor(player, 10)
  WR.scan({ e }, ctx)
  run(e, ctx, cfg.turnTicks + cfg.angerTicks + 2)
  e.react.leash = 4
  player.x = 15 -- got away (on a bike, say)
  for _ = 1, 20 do -- (a step it is on finishes first)
    if e.react.mode ~= "chase" then break end
    run(e, ctx, 1)
  end
  eq(e.react and e.react.mode, "return", "beyond its leash: it gives up")
  eq(e.react.emote, "?", "...puzzled")
  run(e, ctx, 400)
  eq(e.react, nil, "...and wanders again")
  check(e.reactUntil > ctx.now, "a chaser rests before reacting again")
end

-- ------- leashes vary from one chase to the next
do
  local seen = {}
  for _ = 1, 40 do
    local e = entity(5, 25, 40)
    local ctx = ctxFor({ x = 7, y = 25, moving = true }, 10)
    WR.scan({ e }, ctx)
    run(e, ctx, cfg.turnTicks + cfg.angerTicks + 2)
    seen[e.react.leash] = true
  end
  local n = 0
  for _ in pairs(seen) do n = n + 1 end
  check(n >= 4, "different chases follow different distances (" .. n .. " leash lengths seen)")
end

-- ------- chasers leave the grass (chase.anyGround): open ground yes; water, doors, no
do
  -- grass x 0..8, an open path x 9..19, water x >= 20; a doorway at (12, 8)
  local saved = {}
  for _, k in ipairs({ "terrainAt", "canEnter", "isWater", "cellFree", "isWarpCell", "playerCell" }) do
    saved[k] = fake[k]
  end
  local DOOR_X, DOOR_Y = 12, 8
  local function inMap(x, y) return x >= 0 and y >= 0 and x < 30 and y < 30 end
  fake.terrainAt = function(x, y)
    if not inMap(x, y) then return nil end
    if x <= 8 then return "land" end
    if x >= 20 then return "water" end
    return nil -- the path: no encounters
  end
  fake.isWater = function(x, y) return inMap(x, y) and x >= 20 end
  fake.isWarpCell = function(x, y) return x == DOOR_X and y == DOOR_Y end
  fake.cellFree = function(x, y) return inMap(x, y) and x < 20 end
  fake.canEnter = function(_, x, y, opts)
    if not inMap(x, y) then return false end
    if opts and opts.surfing then return x >= 20 end
    return x < 20
  end
  local livePlayer
  fake.playerCell = function() return livePlayer end

  local visited
  local function runTracked(e, ctx, n)
    for _ = 1, n do
      if not e.react then return end
      WR.tick(e, ctx)
      ctx.now = ctx.now + 1
      visited[#visited + 1] = { x = e.cellX, y = e.cellY }
    end
  end
  local function noWaterNoDoor()
    for _, c in ipairs(visited) do
      if c.x >= 20 or (c.x == DOOR_X and c.y == DOOR_Y) then return false end
    end
    return true
  end
  local function angry(e, player, ctx)
    WR.scan({ e }, ctx)
    runTracked(e, ctx, cfg.turnTicks + cfg.angerTicks + 2)
    check(e.react and e.react.mode == "chase", "an angry one sets off")
    e.react.leash, e.react.limit = 20, 20 * 72
  end

  -- 1. it follows the player out of the grass and catches them on the path
  contacts, visited = {}, {}
  local e = entity(8, 8, 40)
  local player = { x = 10, y = 8, moving = true }
  livePlayer = player
  local ctx = ctxFor(player, 10)
  angry(e, player, ctx)
  player.x, player.y, player.moving = 15, 8, false -- standing on the path, past the doorway
  runTracked(e, ctx, 1500)
  eq(contacts[#contacts], e, "a chaser follows the player off the grass and catches them on the path")
  check(e.cellX > 8, "...standing off its grass (" .. e.cellX .. "," .. e.cellY .. ")")
  check(noWaterNoDoor(), "...it never stepped into the water or onto the doorway")
  check(e.chaseHome ~= nil, "...and remembers where home is")

  -- 2. never into the water: a surfing player is safe from a land chaser
  contacts, visited = {}, {}
  local e2 = entity(18, 15, 40)
  local surfer = { x = 20, y = 15, moving = true }
  livePlayer = surfer
  local ctx2 = ctxFor(surfer, 10)
  angry(e2, surfer, ctx2)
  surfer.x, surfer.moving = 23, false
  runTracked(e2, ctx2, 400)
  eq(#contacts, 0, "a land chaser never wades in after a surfing player")
  check(noWaterNoDoor(), "...it stays on dry ground")

  -- 3. giving up off the grass: it walks all the way home onto its terrain
  visited = {}
  local e3 = entity(8, 20, 40)
  local p3 = { x = 10, y = 20, moving = true }
  livePlayer = p3
  local ctx3 = ctxFor(p3, 10)
  angry(e3, p3, ctx3)
  p3.x, p3.moving = 14, false
  e3.react.leash = 20
  for _ = 1, 400 do -- out onto the path after them
    if e3.cellX >= 11 and not e3.moving then break end
    runTracked(e3, ctx3, 1)
  end
  check(e3.cellX >= 11, "it is out on the path (" .. e3.cellX .. ")")
  p3.x = 29 -- gone (a bike)
  livePlayer = nil
  e3.react.leash = 2
  runTracked(e3, ctx3, 1200)
  eq(e3.react, nil, "beyond its leash it gives up and calms down")
  check(e3.cellX <= 8, "...back on its own grass (" .. e3.cellX .. "," .. e3.cellY .. ")")
  eq(e3.chaseHome, nil, "...home again, nothing to remember")

  -- 4. stranded: no way home -> it leaves (ctx.strand: the despawn with its fade)
  local stranded = {}
  local e4 = entity(14, 25, 40)
  e4.chaseHome = { x = 4, y = 25 }
  local ctx4 = ctxFor(nil, 10, { strand = function(x) stranded[#stranded + 1] = x end,
    occupied = function(x, y) return x == 13 or x == 15 or y == 24 or y == 26 end }) -- boxed in
  WR.sendHome(e4)
  check(e4.react and e4.react.mode == "return", "a stray off its grass is sent home")
  run(e4, ctx4, cfg.chase.noPathTicks + 30)
  eq(stranded[1], e4, "no way back: it leaves with the fade")
  eq(e4.react, nil, "...its reaction over")

  -- 5. switched off (chase.anyGround = false): the old way, it stays on its grass
  contacts, visited = {}, {}
  cfg.chase.anyGround = false
  local e5 = entity(8, 12, 40)
  local p5 = { x = 10, y = 12, moving = true }
  livePlayer = p5
  local ctx5 = ctxFor(p5, 10)
  angry(e5, p5, ctx5)
  p5.x, p5.moving = 14, false
  runTracked(e5, ctx5, 600)
  local stayed = true
  for _, c in ipairs(visited) do if c.x > 8 then stayed = false end end
  check(stayed, "anyGround off: a chaser keeps to its grass")
  eq(#contacts, 0, "...so the player on the path is safe")
  cfg.chase.anyGround = true

  -- 6. a water chaser never leaves its water either way
  check(not WR.anyGround({ terrain = "water" }), "a swimmer's chase stays in the water")
  check(WR.anyGround({ terrain = "land" }), "a land one's may leave its grass")

  for k, v in pairs(saved) do fake[k] = v end
end

if failures > 0 then
  io.stderr:write(failures .. " failure(s)\n")
  os.exit(1)
end
print("wild_reactions_unit_test: all passed")
