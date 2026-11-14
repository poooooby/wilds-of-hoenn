-- Run: lua tests/eco_hunt_unit_test.lua
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
-- a 30 x 30 field of grass; species ids = national dex + 1000
local TYPES = { [1261] = { 17 }, [1263] = { 0 }, [1265] = { 6 }, [1335] = { 0 }, [1336] = { 3 } }
local NAMES = { [0] = "NORMAL", [3] = "POISON", [6] = "BUG", [17] = "DARK" }
local BST = { [1261] = 220, [1263] = 240, [1265] = 195, [1335] = 458, [1336] = 458 }
local cries = {}
local fake = {
  terrainAt = function(x, y) if x >= 0 and y >= 0 and x < 30 and y < 30 then return "land" end return nil end,
  canEnter = function(_, x, y) return x >= 0 and y >= 0 and x < 30 and y < 30 end,
  cellFree = function() return true end,
  isWater = function() return false end,
  isWarpCell = function() return false end,
  ripplesAt = function() return false end,
  -- (as Gen 3 stores them: a single type in both slots)
  speciesTypes = function(s) local t = TYPES[s] or { 0 } return t[1], t[2] or t[1] end,
  typeName = function(t) return NAMES[t] or "NORMAL" end,
  baseStatTotal = function(s) return BST[s] or 300 end,
  playCry = function(s) cries[#cries + 1] = s end,
  battlerOf = function(mon) return { mon = mon } end,
  moveRow = function() return { power = 40, accuracy = 0 } end,
  moveDamage = function(att) return att.mon.hits or 6, { effectiveness = 1 } end,
  buildWildFighter = function(species, level)
    return { species = species, level = level, hp = 30, maxHp = 30, speed = species == 1261 and 50 or 20,
             moves = { 33 }, pp = { 35 }, hits = species == 1261 and 12 or nil }
  end,
}
local player = { x = 0, y = 29 }
fake.playerCell = function() return player end
local modules = { engine_patch = fake }
local V = { path = "." }
function V.require(name)
  if modules[name] == nil then modules[name] = assert(loadfile("lib/" .. name .. ".lua"))(V) end
  return modules[name]
end
local Config = V.require("config")
local Eco = V.require("eco")
local EcoHunt = V.require("eco_hunt")
local WildReactions = V.require("wild_reactions")

local nextId = 0
local function mon(dex, x, y, level, profile)
  nextId = nextId + 1
  local r = { isPmd = true, info = {}, anim = "idle" }
  function r:advanceAs(a) self.anim = a end
  function r:advance() self.anim = "idle" end
  return { id = nextId, species = 1000 + dex, level = level or 10, personality = 1, terrain = "land",
           cellX = x, cellY = y, px = x * 16, py = y * 16, facing = "down", state = Config.STATE.AVAILABLE,
           elevation = 3, renderer = r, profile = profile }
end
local HUNTER = { social = "solo", diet = "predator", temper = "territorial", prey = { "NORMAL", "BUG" }, dex = 261 }
local PREY = { social = "solo", diet = "prey", temper = "skittish", dex = 263 }

-- ------- who hunts whom
do
  local pred, prey = mon(261, 5, 5, 20, HUNTER), mon(263, 7, 5, 5, PREY)
  eq(EcoHunt.relation(pred, prey), "hunt", "a strong hunter goes for a weak Normal-type prey")
  local big = mon(263, 7, 5, 40, PREY)
  eq(EcoHunt.relation(pred, big), nil, "...not one stronger than itself")
  local wrongType = mon(336, 7, 5, 3, { diet = "prey", dex = 336 })
  eq(EcoHunt.relation(pred, wrongType), nil, "...nor a type it does not hunt (Poison)")
  local other = mon(261, 7, 5, 3, HUNTER)
  eq(EcoHunt.relation(pred, other), nil, "...nor its own kind")
  local zan = mon(335, 5, 5, 5, { diet = "predator", rival = { [336] = true }, dex = 335 })
  local sev = mon(336, 6, 5, 30, { diet = "predator", rival = { [335] = true }, dex = 336 })
  eq(EcoHunt.relation(zan, sev), "rival", "Zangoose and Seviper are rivals, whatever their size")
  local swim = mon(263, 7, 5, 3, PREY)
  swim.terrain = "water"
  eq(EcoHunt.relation(pred, swim), nil, "a land hunter does not go for a swimmer")
end

-- a little world for the chase + skirmish
local function world(list)
  local state = {}
  local ctx = { now = 0, rng = function(a, b) if a == 1 and b == 100 then return 1 end return math.random(a, b) end,
                player = player, game = {} }
  ctx.occupied = function(x, y, me)
    for _, o in ipairs(list) do
      if o ~= me and o.state == Config.STATE.AVAILABLE and ((o.cellX == x and o.cellY == y) or (o.moving and o.targetX == x and o.targetY == y)) then return true end
    end
    return false
  end
  local despawned = {}
  local sm = { despawn = function(_, id) for _, o in ipairs(list) do if o.id == id then o.state = Config.STATE.DESPAWNED despawned[#despawned + 1] = o end end end }
  ctx.onCatch = function(a, b) EcoHunt.catch(a, b, ctx, sm, state) end
  local function tick()
    ctx.now = ctx.now + 1
    EcoHunt.tick(state, ctx)
    for _, e in ipairs(list) do
      if e.state == Config.STATE.AVAILABLE then
        if e.eco then Eco.step(e, ctx, sm) elseif e.react then WildReactions.tick(e, ctx) end
      end
    end
  end
  return state, ctx, tick, despawned
end

-- ------- the scan: on screen, not by the player, then a cooldown
do
  local pred, prey = mon(261, 10, 10, 20, HUNTER), mon(263, 12, 10, 5, PREY)
  local list = { pred, prey }
  local state, ctx = world(list)
  player = { x = 11, y = 11 }
  ctx.player = player
  check(not EcoHunt.scan(list, ctx, state), "no hunt right beside the player")
  player = { x = 25, y = 25 }
  ctx.player = player
  ctx.now = 1000
  check(not EcoHunt.scan(list, ctx, state), "...nor out of the player's sight")
  player = { x = 10, y = 15 }
  ctx.player = player
  ctx.now = 2000
  check(not EcoHunt.scan(list, ctx, state), "...nor just off the top of the screen (5 tiles up on 240 x 160)")
  player = { x = 10, y = 14 }
  ctx.player = player
  ctx.now = 3000
  check(EcoHunt.scan(list, ctx, state), "in sight, a few tiles off: the hunt starts")
  eq(pred.react and pred.react.target, prey, "...the hunter chases its prey")
  eq(prey.react and prey.react.target, pred, "...the prey runs from it")
  local third = mon(263, 11, 9, 5, PREY)
  check(not EcoHunt.scan({ pred, prey, third }, ctx, state), "one hunt at a time")
end

-- ------- the chase ends in a fight; the prey faints and sinks away
do
  player = { x = 0, y = 29 }
  local pred, prey = mon(261, 10, 10, 30, HUNTER), mon(263, 12, 10, 5, PREY)
  local list = { pred, prey }
  local state, ctx, tick, despawned = world(list)
  local realEscape = Config.ECO.hunt.escapeChance
  Config.ECO.hunt.escapeChance = 0 -- this one fights it out
  EcoHunt.start(pred, prey, "hunt", ctx, state)
  local sawFight, sawBars, sawKo = false, false, false
  for _ = 1, 3000 do
    tick()
    local a = state.active
    if a and a.sk then
      sawFight = true
      local actors = {}
      EcoHunt.collectActors(state, actors)
      if #actors >= 2 then sawBars = true end
      if a.sk.phase == "ko" then sawKo = true end
    end
    if #despawned > 0 then break end
  end
  check(sawFight, "caught: they fight")
  check(sawBars, "...with health bars over both")
  check(sawKo, "...the prey faints")
  eq(despawned[1], prey, "...and is gone once it has sunk away")
  eq(pred.eco, nil, "the hunter is free again")
  eq(state.active, nil, "the hunt is over")
  check(state.next and state.next > ctx.now, "...and the next one waits a while")
  check(prey.owWild and prey.owWild.hp == 0, "the skirmish used real fighters (the prey's at 0 HP)")
  Config.ECO.hunt.escapeChance = realEscape
end

-- ------- a hunter worn down gives up and runs; damage stays on both
do
  player = { x = 0, y = 29 }
  local pred, prey = mon(261, 10, 10, 30, HUNTER), mon(263, 11, 10, 5, PREY)
  local list = { pred, prey }
  local state, ctx, tick = world(list)
  state.active = { pred = pred, prey = prey, rel = "hunt" }
  local sk = EcoHunt.catch(pred, prey, ctx, nil, state)
  check(sk ~= nil, "a catch starts a skirmish")
  pred.owWild.hits, prey.owWild.hits = 0, 100 -- the hunter's blows do nothing, the prey's hurt
  pred.owWild.hp = 5
  for _ = 1, 600 do tick() if sk.over then break end end
  check(sk.over, "the skirmish ends")
  eq(prey.state, Config.STATE.AVAILABLE, "the prey survives")
  check(pred.react and pred.react.mode ~= nil, "the beaten hunter runs from it")
  check(pred.owWild.hp <= 1, "...worn down (" .. pred.owWild.hp .. " HP), carried into a battle with it")
end

-- ------- touching one mid-skirmish ends it cleanly
do
  local pred, prey = mon(261, 10, 10, 30, HUNTER), mon(263, 11, 10, 5, PREY)
  local list = { pred, prey }
  local state, ctx, tick = world(list)
  state.active = { pred = pred, prey = prey, rel = "hunt" }
  local sk = EcoHunt.catch(pred, prey, ctx, nil, state)
  for _ = 1, 30 do tick() end
  prey.state = Config.STATE.ENCOUNTER_STARTING -- the player walked into it
  Eco.abort(prey)
  check(sk.over, "the skirmish is called off")
  eq(pred.eco, nil, "...the hunter let go")
  eq(pred.renderer.act, nil, "...its lean undone")
  eq(state.active, nil, "...and the hunt is over")
end

if failures > 0 then
  io.stderr:write(failures .. " failure(s)\n")
  os.exit(1)
end
print("eco_hunt_unit_test: all passed")
