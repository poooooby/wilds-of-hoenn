-- Run: lua tests/engine_gb_unit_test.lua
-- lib/engine_gb.lua (+ lib/gb/gen1.lua, lib/gb/gen2.lua) against fake Gen 1 / Gen 2
-- engine modules behind a monkeypatched `require`: the dispatch from engine_patch.lua,
-- the draw proxies, the collision rule, terrain and encounters, holding the player,
-- species names <-> national dex, the follower's sprite.
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

-- love.graphics, just enough for the draw paths
local drawn = {}
love = {
  graphics = {
    push = function() end, pop = function() end, translate = function() end, scale = function() end,
    getShader = function() return nil end, setShader = function() end,
    newShader = function() return { fake = true } end,
    getColor = function() return 1, 1, 1, 1 end, setColor = function() end,
  },
}

-- ------- fake engine modules
local fake = {}
local realRequire = require
require = function(path)
  if fake[path] ~= nil then return fake[path] end
  return realRequire(path)
end

local generation = 1
local isYellow = false
fake["src.core.GameVersion"] = { generation = function() return generation end,
  isYellow = function() return isYellow end }

local function newEnv()
  local modules = {}
  local V = { path = "." }
  function V.require(name)
    if modules[name] ~= nil then return modules[name] end
    local chunk = assert(loadfile("lib/" .. name .. ".lua"))
    local value = chunk(V)
    modules[name] = value
    return value
  end
  return V
end

-- a map: rows of characters. g grass, w water, . walkable floor, # wall
local function fakeMap(rows, extra)
  local m = { widthCells = #rows[1], heightCells = #rows, def = {}, id = "ROUTE_1" }
  local function at(x, y) return rows[y + 1] and rows[y + 1]:sub(x + 1, x + 1) or "#" end
  function m:inBounds(x, y) return x >= 0 and y >= 0 and x < self.widthCells and y < self.heightCells end
  function m:isGrassCell(x, y) return at(x, y) == "g" end
  function m:isWaterCell(x, y) return at(x, y) == "w" end
  function m:isWalkableCell(x, y) local c = at(x, y) return c == "g" or c == "." end
  function m:isWalkable(x, y) return self:isWalkableCell(x, y) end
  function m:warpAtCell(x, y) return at(x, y) == "D" and {} or nil end
  function m:cellCollision(x, y) return at(x, y) end
  for k, v in pairs(extra or {}) do m[k] = v end
  return m
end

-- ------- Gen 1 engine
local OverworldState = {}
function OverworldState.drawWorld(ow)
  -- what the engine sees while it draws
  drawn.during = {}
  for _, e in ipairs(ow.entities) do
    drawn.during[#drawn.during + 1] = e
    if e._wilds and e.pose then drawn.pose = { e:pose() } end
  end
  table.sort(ow.entities, function(a, b) return (a.py or 0) < (b.py or 0) end)
  for _, e in ipairs(ow.entities) do if e.draw then e:draw(ow.camera.x, ow.camera.y) end end
  if drawn.fail then error("engine draw failed") end
end
function OverworldState.update(_ow) drawn.updated = (drawn.updated or 0) + 1 end
function OverworldState.handleInput(_ow) drawn.input = (drawn.input or 0) + 1 end
function OverworldState.interact(_ow) drawn.interacted = (drawn.interacted or 0) + 1 end
function OverworldState.rollsIndoorEncounters(def) return def.indoor == true end
fake["src.world.OverworldController"] = OverworldState
fake["src.battle.BattleState"] = { newWild = function(_g, sp, lv) return { species = sp, level = lv } end }
fake["src.world.Map"] = { isOutdoor = function(def) return def.indoor ~= true end,
  isFlyTown = function(def) return def.town == true end,
  ghostBattles = function() return nil end, inRegion = function() return false end }
fake["src.world.FieldDefaults"] = {
  constant = function() return { 50, 100, 140, 170, 195, 215, 230, 242, 251, 256 } end,
  field = function(_data, key)
    if key ~= "fishing" then return nil end
    return { OLD_ROD = { always = { species = "MAGIKARP", level = 5 } },
             GOOD_ROD = { pool = { { species = "GOLDEEN", level = 10 } } },
             SUPER_ROD = { perMap = "superRod" } }
  end,
}
local Game1 = {
  data = {
    pokemon = {
      PIKACHU = { dex = 25, name = "PIKACHU", types = { "ELECTRIC" }, dexEntry = { heightFt = 1, heightIn = 4 },
                  baseStats = { hp = 35, attack = 55, defense = 30, speed = 90, special = 50 },
                  baseExp = 82, growthRate = "MEDIUM", learnset = { { level = 1, move = "THUNDERSHOCK" },
                    { level = 9, move = "THUNDER_WAVE" }, { level = 16, move = "QUICK_ATTACK" } } },
      PIDGEY = { dex = 16, name = "PIDGEY", types = { "NORMAL", "FLYING" }, dexEntry = { heightFt = 1, heightIn = 0 },
                 baseStats = { hp = 40, attack = 45, defense = 40, speed = 56, special = 35 },
                 baseExp = 55, growthRate = "MEDIUM_SLOW", learnset = { { level = 1, move = "GUST" } },
                 evolutions = { { method = "LEVEL", level = 18, species = "PIDGEOTTO" } } },
      PIDGEOTTO = { dex = 17, name = "PIDGEOTTO", types = { "NORMAL", "FLYING" },
                    baseStats = { hp = 63, attack = 60, defense = 55, speed = 71, special = 50 },
                    baseExp = 113, growthRate = "MEDIUM_SLOW", learnset = {} },
      RATTATA = { dex = 19, name = "RATTATA", types = { "NORMAL" } },
      GOLDEEN = { dex = 118, name = "GOLDEEN", types = { "WATER" }, dexEntry = { heightFt = 2, heightIn = 0 } },
      MAGIKARP = { dex = 129, name = "MAGIKARP", types = { "WATER" }, dexEntry = { heightFt = 2, heightIn = 11 } },
      TENTACOOL = { dex = 72, name = "TENTACOOL", types = { "WATER", "POISON" }, dexEntry = { heightFt = 2, heightIn = 11 } },
    },
    moves = {
      TACKLE = { id = "TACKLE", name = "TACKLE", power = 40, accuracy = 95, pp = 35, type = "NORMAL" },
      GROWL = { id = "GROWL", name = "GROWL", power = 0, accuracy = 100, pp = 40, type = "NORMAL" },
      GUST = { id = "GUST", name = "GUST", power = 40, accuracy = 100, pp = 35, type = "NORMAL" },
      THUNDERSHOCK = { id = "THUNDERSHOCK", name = "THUNDERSHOCK", power = 40, accuracy = 100, pp = 30, type = "ELECTRIC" },
      THUNDER_WAVE = { id = "THUNDER_WAVE", name = "THUNDER WAVE", power = 0, accuracy = 100, pp = 20, type = "ELECTRIC" },
      QUICK_ATTACK = { id = "QUICK_ATTACK", name = "QUICK ATTACK", power = 40, accuracy = 100, pp = 30, type = "NORMAL" },
    },
    items = {
      POTION = { id = "POTION", name = "POTION", price = 300 },
      POKE_BALL = { id = "POKE_BALL", name = "POKE BALL", price = 200 },
      MASTER_BALL = { id = "MASTER_BALL", name = "MASTER BALL", price = 0 },
      BICYCLE = { id = "BICYCLE", name = "BICYCLE", price = 0, keyItem = true },
      FIRE_STONE = { id = "FIRE_STONE", name = "FIRE STONE", price = 2100 },
      HM01 = { id = "HM01", name = "HM01", price = 0 },
      TM01 = { id = "TM01", name = "TM01", price = 3000 },
      NUGGET = { id = "NUGGET", name = "NUGGET", price = 10000 },
    },
    statuses = {},
    rulesets = { gen1_faithful = { name = "gen1_faithful", randMin = 217, randMax = 255 } },
    constants = { levelCap = 100 },
    encounters = {
      ROUTE_1 = { grass = { rate = 25, slots = { { species = "PIDGEY", level = 3 }, { species = "RATTATA", level = 2 },
        { species = "PIDGEY", level = 4 }, { species = "PIDGEY", level = 4 }, { species = "PIDGEY", level = 4 },
        { species = "PIDGEY", level = 4 }, { species = "PIDGEY", level = 4 }, { species = "PIDGEY", level = 4 },
        { species = "PIDGEY", level = 4 }, { species = "PIKACHU", level = 5 } } } },
      CAVE = { grass = { rate = 10, slots = { { species = "RATTATA", level = 8 } } } },
      SEASIDE = { water = { rate = 10, slots = { { species = "TENTACOOL", level = 10 } } } },
    },
    field = { indoorEncounters = {}, superRod = { SEASIDE = { { species = "GOLDEEN", level = 10 } } } },
  },
  save = { party = { { species = "PIKACHU", level = 9 } }, pokedex = { owned = { PIDGEY = true } }, repelSteps = 0 },
  stack = (function()
    local st = { list = {} }
    -- _top doubles as the test's own poke-hole: reads prefer it, pushes stack over it
    function st.top(self) return self.list[#self.list] or self._top end
    function st.push(self, state) self.list[#self.list + 1] = state end
    function st.pop(self) local t = self.list[#self.list] self.list[#self.list] = nil return t end
    return st
  end)(),
}
fake["src.core.Game"] = Game1
fake["src.render.PaletteFX"] = { honorsTrueColor = function() return false end, markTrueColor = function() end }
-- the dialogue box and the list menu (the talk seams). A fake box types out instantly.
local TextBox = {}
TextBox.__index = TextBox
function TextBox.new(game, text, onDone, opts)
  return setmetatable({ isTextBox = true, game = game, text = text, onDone = onDone, opts = opts,
                        pages = { text }, pageIndex = 1, done = true }, TextBox)
end
function TextBox.draw() drawn.boxDrawn = (drawn.boxDrawn or 0) + 1 end
function TextBox.update() drawn.boxTicked = (drawn.boxTicked or 0) + 1 end
TextBox.__call = nil
fake["src.render.TextBox"] = TextBox
local ListMenu = {}
ListMenu.__index = ListMenu
function ListMenu.new(game, title, items, opts)
  return setmetatable({ game = game, items = items, onChoose = opts.onChoose, onCancel = opts.onCancel,
                        index = 1 }, ListMenu)
end
function ListMenu:close()
  local stack = self.game.stack
  if stack:top() == self then stack:pop() end
end
fake["src.ui.ListMenu"] = ListMenu
fake["src.render.Pipelines"] = { worldPipeline = function() return drawn.pipeline end }

-- ------- fake battle / bag / font engine, for the role seams (Tier 2b)
local FakeStats = {
  calc = function(def, level)
    local b = def.baseStats or {}
    return { hp = (b.hp or 30) + level * 2, attack = b.attack or 10, defense = b.defense or 10,
             speed = b.speed or 10, special = b.special or 10 }
  end,
  ensure = function(_def, mon) return mon end,
}
fake["src.pokemon.Stats"] = FakeStats
local FakeGrowth = {
  expForLevel = function(_rate, level) return level * level * level end,
  levelForExp = function(_rate, exp, cap)
    local lv = math.floor((exp + 1e-9) ^ (1 / 3) + 1e-9)
    return math.min(cap or 100, math.max(1, lv))
  end,
}
fake["src.pokemon.Growth"] = FakeGrowth
fake["src.battle.Experience"] = {
  gainFor = function(def, level) return math.max(1, math.floor((def.baseExp or 50) * level / 7)) end,
  movesLearnedAt = function(def, level)
    local out = {}
    for _, e in ipairs(def.learnset or {}) do
      if e.level == level then out[#out + 1] = e.move end
    end
    return out
  end,
}
fake["src.pokemon.Pokemon"] = {
  new = function(data, species, level)
    local def = data.pokemon[species]
    local moves = {}
    for _, e in ipairs(def.learnset or {}) do
      if e.level <= level and #moves < 4 then
        moves[#moves + 1] = { id = e.move, pp = (data.moves[e.move] or {}).pp or 10 }
      end
    end
    local stats = FakeStats.calc(def, level)
    return { species = species, level = level, dvs = { attack = 1, defense = 2, speed = 3, special = 4 },
             statExp = {}, exp = FakeGrowth.expForLevel(def.growthRate, level),
             stats = stats, hp = stats.hp, moves = moves }
  end,
}
local damageCalls = {}
fake["src.battle.Damage"] = {
  compute = function(ruleset, attacker, defender, move, opts)
    damageCalls[#damageCalls + 1] = { ruleset = ruleset, attacker = attacker, defender = defender,
                                      move = move, opts = opts }
    return move.power, { crit = false, typeMult = 20 }
  end,
}
local evoRequests = {}
local FakeEvolution = {} -- declared first: request's closure needs the local in scope
function FakeEvolution.pendingFor(game, mon, _trigger)
  local def = game.data.pokemon[mon.species]
  for _, e in ipairs(def and def.evolutions or {}) do
    if e.method == "LEVEL" and (tonumber(mon.level) or 0) >= e.level then return e.species, e end
  end
  return nil
end
function FakeEvolution.request(game, mon, trigger, onDone)
  local species = FakeEvolution.pendingFor(game, mon, trigger)
  if not species then
    if onDone then onDone() end
    return nil
  end
  evoRequests[#evoRequests + 1] = { mon = mon, to = species, onDone = onDone }
  return species
end
fake["src.pokemon.Evolution"] = FakeEvolution
local screenPushes = {}
fake["src.ui.Screens"] = {
  push = function(_game, name, mon, moveId, cb) screenPushes[#screenPushes + 1] = { name = name, mon = mon, moveId = moveId, cb = cb } end,
}
local learnedTold = {}
fake["src.world.PikachuFollower"] = {
  onMoveLearned = function(_save, mon, moveId) learnedTold[#learnedTold + 1] = { mon = mon, moveId = moveId } end,
}
fake["src.mods.Runtime"] = { wants = function() return false end, emit = function() end }
-- the Gen 1 single bag, two slots wide so "full" is easy to reach
fake["src.inventory.Bag"] = (function()
  local B = {}
  function B.pocketOf(_id, _data) return "ITEM" end
  function B.capacity(_data, _pocket) return 2 end
  function B.order(save, _data) save.bagOrder = save.bagOrder or {} return save.bagOrder end
  function B.slots(save, _data, _pocket)
    local n = 0
    for _ in pairs(save.inventory or {}) do n = n + 1 end
    return n
  end
  function B.addTo(store, order, id, qty, _data, used, cap)
    local old = store[id]
    if not old and used >= cap then return false end
    store[id] = (old or 0) + (qty or 1)
    if not old then order[#order + 1] = id end
    return true
  end
  function B.add(save, id, qty, data)
    save.inventory = save.inventory or {}
    return B.addTo(save.inventory, B.order(save, data), id, qty or 1, data, B.slots(save, data), B.capacity(data))
  end
  return B
end)()
local sounds = {}
fake["src.core.Sound"] = {
  play = function(_data, name) sounds[#sounds + 1] = name end,
  playCry = function() end,
}
local fontDraws = {}
fake["src.render.Font"] = {
  width = function(text) return 4 * #tostring(text) end,
  draw = function(text, x, y) fontDraws[#fontDraws + 1] = { text = text, x = x, y = y } end,
}

generation = 1
local V1 = newEnv()
local EP = assert(loadfile("lib/engine_patch.lua"))(V1)
eq(EP.isGb, true, "engine_patch.lua hands out the Gen 1 / Gen 2 layer on a Gen 1 boot")
eq(EP.layoutName(), "gen1", "layout gen1")
local okProbe, missing = EP.probe()
check(okProbe, "the Gen 1 probe passes on the fake engine (" .. table.concat(missing or {}, "; ") .. ")")
eq(EP.supports("sky"), true, "Gen 1 carries the sky (lib/gb/gen1.lua FEATURES)")
eq(EP.supports("water_life"), true, "...and the water life")
eq(EP.supports("local_scenes"), true, "...and the local scenes")
eq(EP.supports("wild_reacts"), true, "...and the wild reactions")
eq(EP.supports("roles"), true, "...and the partner roles")

local player = { cellX = 3, cellY = 2, px = 48, py = 32, moving = false, facing = "down" }
local ow = {
  map = fakeMap({ "......", "..ggg.", "..ggg.", "..www.", "......" }),
  player = player, camera = { x = 0, y = 0 }, npcs = {}, scriptMoves = {},
  runner = { isRunning = function() return false end },
}
ow.entities = { player }
Game1.stack._top = ow
ow.pushBattle = function(self, battle) self.pushed = battle end
ow.afterBattle = function(self, result) self.after = result end

-- the collected actors, as SpawnManager / FollowerAdapter hand them over
local actorDraws = 0
local hooks = {
  collectActors = function(actors)
    actors[#actors + 1] = { kind = "wild_mon", x = 64, y = 16, sortY = 16, facing = "down",
      renderer = { draw = function() actorDraws = actorDraws + 1 end } }
    actors[#actors + 1] = { kind = "fx", x = 0, y = 40, sortY = 40.5, draw = function() actorDraws = actorDraws + 1 end }
  end,
  followerTick = function(game) drawn.ticked = game end,
  interact = function(game) drawn.interactGame = game return drawn.consumeInteract == true end,
  messageDraw = function() drawn.portraits = (drawn.portraits or 0) + 1 end,
}
-- a map entered before any wrapped frame ran (a boot, a save loaded): the world is adopted
EP.noteMap(Game1, ow.map)
eq(EP.world(), ow, "map.entered adopts the overworld that loaded the map")
eq(EP.mapBounds(), 6, "...so the map's cells can be scanned at once")
check(EP.install(hooks, nil), "install wraps the Gen 1 draw, tick and input")

OverworldState.update(ow)
eq(drawn.ticked, Game1, "the frame's tail runs the follower tick with the game")
eq(EP.world(), ow, "the tick remembers the live world")

OverworldState.drawWorld(ow)
eq(#drawn.during, 3, "while the engine draws, our two actors are in its entity list")
eq(actorDraws, 2, "the engine drew both through the proxies")
eq(#ow.entities, 1, "after the draw only the engine's own entities are left")
eq(ow.entities[1], player, "...the player")
local wildProxy
for _, e in ipairs(drawn.during) do if e._wilds and e.cellX then wildProxy = e end end
check(wildProxy and wildProxy.cellX == 4 and wildProxy.cellY == 1 and wildProxy.passable,
  "the wild Pokemon's proxy stands on its cell (grass cover) and blocks nobody")
check(wildProxy and wildProxy.inGrass == true, "...and knows it is in grass")

drawn.fail = true
local okDraw = pcall(OverworldState.drawWorld, ow)
drawn.fail = false
check(not okDraw, "an engine draw error still reaches the caller")
eq(#ow.entities, 1, "...and the proxies are gone anyway")

drawn.pipeline = "voxel"
OverworldState.drawWorld(ow)
eq(#drawn.during, 1, "a render pipeline mod, no voxel sheets: no proxies")
local vsprite = { def = { image = "v.png" } }
EP.voxelSheets = { spriteFor = function(_, r, luma) drawn.luma = luma return r and vsprite or nil end }
OverworldState.drawWorld(ow)
eq(#drawn.during, 2, "with voxel sheets: the renderer-drawn actor goes in (not the custom drawing)")
local spr, px, py, facing, phase = drawn.pose[1], drawn.pose[2], drawn.pose[3], drawn.pose[4], drawn.pose[5]
check(spr == vsprite, "its pose() hands the pipeline the voxel sprite")
check(px == 64 and py == 16 and facing == "down" and phase == 0, "...at its tile, facing, standing")
eq(drawn.luma, true, "a palette colour mode asks for the luminance sheet")
eq(#ow.entities, 1, "...and it is gone after the draw")
drawn.pipeline = nil

-- terrain: grass, water, indoor floor
eq(EP.terrainAt(2, 1), "land", "Gen 1 grass is land")
eq(EP.terrainAt(2, 3), "water", "Gen 1 water is water")
eq(EP.terrainAt(0, 0), nil, "a plain floor outdoors is nothing")
ow.map.def.indoor = true
eq(EP.terrainAt(0, 0), "land", "an indoor (cave) floor is land")
eq(EP.mapType(), 4, "indoors reads as map type 4")
ow.map.def.indoor = nil
eq(EP.mapType(), 3, "outdoors reads as map type 3")
ow.map.def.town = true
eq(EP.mapType(), 1, "a Fly town reads as map type 1 (the birds may perch)")
ow.map.def.town = nil
eq(EP.skyAllowed(), true, "open sky outdoors")

-- the ambient systems' seams (Tier 1)
eq(EP.isFlying("PIDGEY"), true, "Pidgey is a Flying type (by key)")
eq(EP.isFlying(16), true, "...and by national dex number")
eq(EP.isFlying("RATTATA"), false, "Rattata is not")
eq(EP.isWaterType("GOLDEEN"), true, "Goldeen is a Water type")
eq(EP.heightDm("PIDGEY"), 3, "Pidgey's 1'0\" dex height is 3 dm")
eq(EP.heightDm(118), 6, "Goldeen's 2'0\" is 6 dm (by dex number)")
eq(EP.baseStatTotal("PIKACHU"), 260, "Pikachu's five base stats sum to 260")
ow.map.def.signs = { { x = 2, y = 0, text = "T" } }
local signs = EP.signCells()
check(#signs == 1 and signs[1].x == 2 and signs[1].y == 0, "the map's signposts come through")
ow.neighbors = { { map = { id = "ROUTE_2" } }, { map = { id = "VIRIDIAN_CITY" } } }
local nb = EP.neighbourMapIds()
check(#nb == 2 and nb[1] == "ROUTE_2" and nb[2] == "VIRIDIAN_CITY", "the live neighbour map ids")
ow.npcs = { { cellX = 4, cellY = 4 } }
eq(EP.objectOn(4, 4), true, "an NPC's cell is occupied")
eq(EP.objectOn(5, 4), false, "...the next one is not")
ow.npcs = {}
eq(EP.playCry("PIDGEY"), nil, "playCry is safe headless")
eq(EP.fieldEffectSheet("exclamation_question_mark"), nil, "no emote sheet without love (code-drawn fallback)")
eq(EP.fieldEffectSheet("ground_impact_dust"), nil, "no dust sheet headless (the burst draws alone)")
eq(EP.fieldEffectSheet("long_grass"), nil, "other sheets stay absent")

-- encounters
local t = EP.tableFor("ROUTE_1")
check(t and t.land and not t.water, "Route 1's table has land, no water")
check(type(t.land) == "table" and type(t.land.slots) == "table", "...and carries its slot list for the ambient systems")
eq(t.land.slots[1].species, 16, "...slot species as national dex numbers (Pidgey 16)")
local sea = EP.tableFor("SEASIDE")
check(sea and sea.water and type(sea.water.slots) == "table", "a water table carries slots too")
eq(sea.water.slots[1].species, 72, "...Tentacool as dex 72")
check(type(sea.fishing) == "table" and type(sea.fishing.slots) == "table", "...and the rods' pools as `fishing`")
local fishDex = {}
for _, slot in ipairs(sea.fishing.slots) do fishDex[slot.species] = true end
check(fishDex[129] and fishDex[118], "the Old Rod's Magikarp and the Super Rod's Goldeen are in it")
local seen = {}
math.randomseed(7)
for _ = 1, 400 do
  local enc = EP.rollSweetScent("ROUTE_1", "land")
  if enc then seen[enc.species .. enc.level] = true end
end
check(seen.PIDGEY3 and seen.RATTATA2 and seen.PIKACHU5, "the slot buckets reach every slot (first, second, last)")
eq(EP.rollSweetScent("ROUTE_1", "water"), nil, "no water table, no water encounter")
Game1.save.repelSteps = 10
eq(EP.repelAllows(5), false, "REPEL keeps out a Pokemon weaker than the lead")
eq(EP.repelAllows(12), true, "...not a stronger one")
Game1.save.repelSteps = 0

-- the collision rule
local wildAt = function(x, y) return x == 4 and y == 2 and {} or nil end
local function verdict(mover)
  local ctx = { mover = mover, toX = 4, toY = 2 }
  return EP.collisionVerdict(true, ctx, wildAt), ctx.reason
end
eq(verdict(player), true, "the player may step onto a wild Pokemon (the contact)")
local v, reason = verdict({ cellX = 5, cellY = 2 })
eq(v, false, "an NPC may not")
eq(reason, "entity", "...the engine's own reason")
eq(verdict({ pikachuFollower = true }), true, "the follower may")
eq(EP.collisionVerdict(false, { mover = player, toX = 4, toY = 2 }, wildAt), false, "a refusal stays a refusal")
ow.scriptMoves = { {} }
eq(verdict({ cellX = 5, cellY = 2 }), true, "a scripted character walks through while the field is busy")
ow.scriptMoves = {}

-- ------- the talk seams (Tier 2: the follower menu, the portrait, friendship)
do
  -- the A press: our hook first; consumed = the engine's own interact never runs
  drawn.interacted, drawn.consumeInteract = 0, true
  OverworldState.interact(ow)
  eq(drawn.interacted, 0, "a consumed A press never reaches the engine's interact")
  check(drawn.interactGame == Game1, "...and the hook got the game")
  drawn.consumeInteract = false
  OverworldState.interact(ow)
  eq(drawn.interacted, 1, "an unconsumed one falls through")
  -- Yellow's own Pikachu talk passes through untouched
  isYellow = true
  Game1.save.pikachuHappiness = 90
  Game1.save.party = { { species = "PIKACHU", level = 9 } }
  ow.npcs = { { pikachuFollower = true, cellX = player.cellX, cellY = player.cellY + 1 } }
  player.facing = "down"
  drawn.consumeInteract = true
  OverworldState.interact(ow)
  eq(drawn.interacted, 2, "Yellow facing its starter Pikachu: the native talk runs, not our menu")
  Game1.save.pikachuHappiness = nil
  isYellow = false
  ow.npcs = {}

  -- messages: a stay box stays "open" under a menu, closeStay pops it
  eq(EP.isMessageOpen(), false, "no box: no message")
  check(EP.showMessage("HELLO", { stay = true }), "a stay message opens")
  check(EP.isMessageOpen(), "...and reads as open")
  check(EP.messageOnLastPage(), "...typed out (the fake types instantly)")
  local picked
  check(EP.showChoice({ "PET", "PLAY", "TALK" }, 0, function(i) picked = i end), "a choice menu opens over it")
  check(EP.choiceActive(), "...and reads as active")
  check(EP.isMessageOpen(), "...while the stay box under it still counts as open")
  local menu = Game1.stack:top()
  menu.onChoose(menu.items[2], menu)
  eq(picked, 1, "picking the second row answers 1 (0-based, like Gen 3's Choice)")
  eq(EP.choiceActive(), false, "...and the menu is gone")
  check(EP.closeStayMessage(), "the stay box closes on demand")
  eq(EP.isMessageOpen(), false, "...and nothing reads as open")
  local doneRan = false
  check(EP.showMessage("BYE", { done = function() doneRan = true end }), "a plain message opens")
  local box = Game1.stack:top()
  box.onDone()
  Game1.stack:pop()
  check(doneRan, "...and its done callback runs when it closes")

  -- the portrait hook rides the box draw
  drawn.portraits = 0
  fake["src.render.TextBox"].draw({})
  eq(drawn.portraits, 1, "the portrait hook runs after every box draw")

  -- the window, names, friendship, identity
  local win = EP.dialogueWindow()
  check(win and win.left == 0 and win.top == 12 and win.width == 20 and win.height == 6,
    "the dialogue window is the Gen 1 box (tiles 0,12 20x6)")
  eq(EP.displayName({ species = "PIKACHU" }), "PIKACHU", "no nickname: the species name")
  eq(EP.displayName({ species = "PIKACHU", nickname = "SPARKY" }), "SPARKY", "a nickname wins")
  local mon = { species = "PIKACHU", dvs = { attack = 15, defense = 10, speed = 9, special = 3 } }
  local FriendStore = (function()
    local V2 = { require = function(name) return assert(loadfile("lib/" .. name .. ".lua"))(V2) end }
    local G = assert(loadfile("lib/gb_friendship.lua"))(V2)
    local saved = {}
    local modFake = { save = { get = function(_, k) return saved[k] end, set = function(_, k, v) saved[k] = v end } }
    return G.new(modFake, function() return Game1.save end)
  end)()
  EP.setFriendshipStore(FriendStore)
  eq(EP.friendshipOf(mon), 70, "friendship seeds at 70")
  eq(EP.setFriendship(mon, 73), 73, "...and set writes through")
  eq(EP.friendshipOf(mon), 73, "...persisted")
  eq(mon.happiness, 73, "...and mirrored onto the mon for the moods")
  Game1.save.pikachuHappiness = 88
  local starter = { species = "PIKACHU" }
  eq(EP.friendshipOf(starter), 88, "Yellow's starter Pikachu reads the game's own happiness")
  EP.setFriendship(starter, 95)
  eq(Game1.save.pikachuHappiness, 95, "...and writes it back")
  Game1.save.pikachuHappiness = nil
  EP.setFriendshipStore(nil)
  local idA = EP.monIdentity(mon)
  local idB = EP.monIdentity({ species = "PIKACHU", dvs = { attack = 15, defense = 10, speed = 9, special = 4 } })
  check(idA and idB and idA ~= idB, "two mons with different DVs get different identities")
  eq(EP.monIdentity(mon), idA, "...and the same mon always the same one")

  -- the follower in the faced cell, free cells ahead
  ow.npcs = { { pikachuFollower = true, cellX = player.cellX - 1, cellY = player.cellY } }
  player.facing = "left"
  check(EP.followerInFacingCell() ~= nil, "the follower on the faced cell is found")
  player.facing = "right"
  eq(EP.followerInFacingCell(), nil, "...facing away, it is not")
  ow.npcs = {}
  check(EP.freeCellsAhead(2, 1, "right", 3) >= 1, "open ground ahead counts")
  eq(EP.freeCellsAhead(2, 3, "right", 3), 0, "water ahead does not")
  player.facing = "down"

  -- a Gen 1 cutscene (scripted moves) reads as leadingNpc: the companion steps aside
  eq(EP.leadingNpc(), false, "no script: no cutscene")
  ow.scriptMoves = { {} }
  eq(EP.leadingNpc(), true, "scripted moves read as a cutscene")
  ow.scriptMoves = {}
end

-- ------- the role seams (Tier 2b: the Battler's combat, the Forager's bag, level-ups)
do
  -- move ids are strings, interned to stable numbers for lib/ow_combat.lua
  local tackle = EP.moveNumber("TACKLE")
  check(type(tackle) == "number" and tackle > 0, "a string move id interns to a number")
  eq(EP.moveNumber({ id = "TACKLE" }), tackle, "...a move slot answers the same number")
  check(EP.moveNumber("GROWL") ~= tackle, "...and another move another one")
  local row = EP.moveRow(tackle)
  check(row and row.power == 40 and row.accuracy == 95 and row.pp == 35, "moveRow reads the Gen 1 move data")
  eq(EP.moveRow("GROWL").power, 0, "...a status move has no power (never picked)")

  -- the battler shape and the engine's damage formula
  local Pokemon = fake["src.pokemon.Pokemon"]
  local ally = Pokemon.new(Game1.data, "PIKACHU", 8) -- below THUNDER WAVE's level 9
  local att = EP.battlerOf(ally)
  check(att and att.mon == ally and att.curTypes[1] == "ELECTRIC" and att.def, "battlerOf carries the mon, its types and def")
  eq(ally.maxHp, ally.stats.hp, "...and mirrors maxHp onto the mon (health bars read it)")
  local wild = EP.buildWildFighter("PIDGEY", 5)
  check(wild and wild.species == "PIDGEY" and #wild.moves == 1 and wild.moves[1].id == "GUST",
    "buildWildFighter builds the engine's own wild mon (learnset moves)")
  eq(wild.hp, wild.maxHp, "...at full HP")
  local dfn = EP.battlerOf(wild)
  local dmg, info = EP.moveDamage(att, dfn, tackle, function(lo) return lo end, true)
  eq(dmg, 40, "moveDamage runs the engine's Damage.compute")
  check(info and info.critical == false and info.effectiveness == 2, "...translating crit and the x10 type multiplier")
  local call = damageCalls[#damageCalls]
  check(call.ruleset == Game1.data.rulesets.gen1_faithful, "...under the game's own ruleset")
  eq(call.opts.forceCrit, false, "...noCrit pins the crit roll")
  eq(call.move, Game1.data.moves.TACKLE, "...with the real move row")

  -- EXP: the engine's worth, applied by amount with the Growth curve
  eq(EP.expGain("PIDGEY", 7), 55, "expGain is the engine's formula (base 55 x 7 / 7)")
  local hpBefore = ally.hp
  local result = EP.expApply(ally, 1000 - ally.exp) -- exactly to level 10 on the cubic fake
  check(result and result.fromLevel == 8 and result.toLevel == 10, "expApply levels the mon up (8 -> 10)")
  eq(ally.level, 10, "...the level moved")
  eq(ally.stats.hp, 55, "...the stats were recalculated")
  eq(ally.hp, hpBefore + 4, "...and the HP delta was kept, not a full heal")
  eq(ally.maxHp, 55, "...maxHp follows")

  -- the level-up follow-through's questions
  local learned = EP.movesLearnedAt(ally, 9)
  check(#learned == 1 and learned[1] == "THUNDER_WAVE", "movesLearnedAt reads the learnset (string ids)")
  eq(EP.knowsMove(ally, "THUNDERSHOCK"), true, "knowsMove sees a known move")
  eq(EP.knowsMove(ally, "THUNDER_WAVE"), false, "...not an unknown one")
  local bird = Pokemon.new(Game1.data, "PIDGEY", 18)
  eq(EP.evolutionTarget(bird), "PIDGEOTTO", "a level evolution offers its target")
  eq(EP.evolutionTarget(Pokemon.new(Game1.data, "PIDGEY", 5)), nil, "...not before its level")
  local evoDone = false
  check(EP.startEvolution(bird, "PIDGEOTTO", function() evoDone = true end), "startEvolution opens the engine's movie")
  local req = evoRequests[#evoRequests]
  check(req and req.mon == bird and req.to == "PIDGEOTTO", "...for that mon and target")
  req.onDone()
  check(evoDone, "...and its close reaches our onDone")
  check(not EP.startEvolution(Pokemon.new(Game1.data, "PIDGEY", 5), "PIDGEOTTO", function() evoDone = "never" end),
    "nothing to evolve: false, onDone untouched")
  check(evoDone ~= "never", "...truly untouched")

  -- the learn flow: a free slot learns with the jingle box, a full moveset opens the forget screen
  local learnDone
  check(EP.startMoveLearn(ally, { "THUNDER_WAVE" }, function(any) learnDone = any end),
    "startMoveLearn starts on a mon with a free slot")
  local box = Game1.stack:top()
  check(box and box.isTextBox and box.text:find("THUNDER WAVE"), "...the learned box is up")
  eq(#ally.moves, 2, "...and the move is in the slot")
  check(learnedTold[#learnedTold] and learnedTold[#learnedTold].moveId == "THUNDER_WAVE",
    "...Yellow's Pikachu bookkeeping was told")
  Game1.stack:pop()
  box.onDone()
  eq(learnDone, true, "...the chain's end reaches onDone(true)")
  local fullMon = Pokemon.new(Game1.data, "PIKACHU", 16)
  fullMon.moves = { { id = "THUNDERSHOCK", pp = 30 }, { id = "THUNDER_WAVE", pp = 20 },
                    { id = "GROWL", pp = 40 }, { id = "TACKLE", pp = 35 } }
  local fullDone
  check(EP.startMoveLearn(fullMon, { "QUICK_ATTACK" }, function(any) fullDone = any end),
    "a full moveset starts too")
  local push = screenPushes[#screenPushes]
  check(push and push.name == "MoveLearnMenu" and push.moveId == "QUICK_ATTACK", "...through the engine's forget screen")
  push.cb(true)
  eq(fullDone, true, "...whose close reaches onDone")
  local neverDone
  check(not EP.startMoveLearn(ally, { "THUNDER_WAVE" }, function() neverDone = true end),
    "every move already known: false")
  check(not neverDone, "...and onDone never ran")

  -- the Forager's catalog and bag
  local catalog = EP.itemCatalog()
  local byId = {}
  for _, e in ipairs(catalog) do byId[e.id] = e end
  check(byId.POTION and byId.POTION.use == "heal" and byId.POTION.pocket == "ITEMS",
    "the catalog classifies a heal")
  eq(byId.POKE_BALL.pocket, "POKE_BALLS", "...a priced ball lands in the ball pocket")
  eq(byId.MASTER_BALL.pocket, "ITEMS", "...the priceless Master Ball does not (and is excluded by name)")
  eq(byId.BICYCLE.pocket, "KEY_ITEMS", "...a key item is marked")
  eq(byId.FIRE_STONE.isEvo, true, "...a stone is an evolution item")
  eq(byId.HM01.isHm, true, "...an HM is marked")
  eq(byId.TM01.isTm, true, "...and a TM")
  Game1.save.inventory, Game1.save.bagOrder = nil, nil
  check(EP.bagCanAdd("POTION", 1), "an empty bag takes a Potion")
  eq(Game1.save.inventory, nil, "...without touching the save (a dry run)")
  check(EP.bagAdd("POTION", 1), "bagAdd puts it in")
  check(EP.bagAdd("POKE_BALL", 1), "...and a ball (the fake bag holds two slots)")
  eq(EP.bagCanAdd("NUGGET", 1), false, "a full bag refuses a new item")
  eq(EP.bagCanAdd("POTION", 1), true, "...but stacks an existing one")
  eq(Game1.save.inventory.NUGGET, nil, "...and the dry runs never added anything")
  Game1.save.inventory, Game1.save.bagOrder = nil, nil

  -- where the Forager may set out
  local allowed = { [3] = true, [4] = true }
  eq(EP.forageAllowed(allowed), true, "a route allows foraging")
  ow.map.def.town = true
  eq(EP.forageAllowed(allowed), false, "...a town does not")
  ow.map.def.town = nil
  player.surfing = true
  eq(EP.forageAllowed(allowed), false, "...nor surfing")
  player.surfing = nil
  local wasX, wasY = player.cellX, player.cellY
  player.cellX, player.cellY = 2, 3 -- a water cell
  eq(EP.forageAllowed(allowed), false, "...nor standing in water")
  player.cellX, player.cellY = wasX, wasY

  -- sounds and the font (the popup labels)
  check(EP.playSelect(), "the menu click plays")
  eq(sounds[#sounds], "Press_AB", "...the engine's own Press_AB")
  check(EP.playSuccess(), "the found-it jingle plays")
  eq(sounds[#sounds], "Get_Item1", "...Get_Item1")
  eq(EP.fontLayout(), "gb", "the font layout reads \"gb\" (no Gen 3 pen codes or cell drop)")
  eq(EP.measureText("ROLE"), 16, "measureText is the engine font's width")
  eq(EP.drawText("ROLE", 5, 7), 16, "drawText draws and answers the width")
  check(fontDraws[#fontDraws] and fontDraws[#fontDraws].text == "ROLE", "...through the engine font")

  -- the party carries maxHp for the roles
  local saved = Game1.save.party
  Game1.save.party = { Pokemon.new(Game1.data, "PIKACHU", 9) }
  local got = EP.partyMons()
  eq(got[1].maxHp, got[1].stats.hp, "partyMons mirrors maxHp onto each mon")
  Game1.save.party = saved
end

-- busy / holding the player
eq(EP.fieldBusy(), false, "the field is free")
Game1.stack._top = { other = true }
eq(EP.fieldBusy(), true, "a screen over the overworld makes it busy")
Game1.stack._top = ow
EP.lockField("contact")
drawn.input = 0
OverworldState.handleInput(ow)
eq(drawn.input, 0, "held: no input reaches the overworld")
EP.unlockField("contact")
OverworldState.handleInput(ow)
eq(drawn.input, 1, "released: it does again")

-- the wild battle
local ended
local okW = EP.startWild(Game1, { species = "PIDGEY", level = 3 }, { done = function(r) ended = r end })
check(okW and ow.pushed and ow.pushed.species == "PIDGEY" and ow.pushed.level == 3, "startWild pushes the engine's wild battle for that Pokemon")
eq(EP.battleActive(), true, "...and the field knows a battle is on")
ow.pushed.onFinish("run")
eq(ow.after, "run", "the end of it runs the engine's afterBattle")
eq(ended, "run", "...and our done")
EP.noteBattle(false)

-- species
eq(EP.nationalFor("PIKACHU"), 25, "a species name -> its national dex number")
eq(EP.nationalFor("MISSINGNO"), nil, "an unknown name -> nil")
eq(EP.speciesForNational(16), "PIDGEY", "national dex number -> the species name")
eq(EP.isCaught("PIDGEY"), true, "owned in the Pokedex")
eq(EP.isCaught("RATTATA"), false, "not owned")
eq(EP.shinyDvs({ attack = 10, defense = 10, speed = 10, special = 10 }), false, "Gen 1 has no shinies")

-- the follower's sprite: ours drawn, everything else from the engine's own sprite
local base = { def = { image = "pika.png" } }
local npc = { pikachuFollower = true, sprite = base }
ow.npcs = { npc }
eq(EP.followerCurrent(), npc, "the engine's follower npc")
local rdraws = 0
local renderer = { draw = function() rdraws = rdraws + 1 end }
EP._pipeline = false
local s = EP.followerSprite(renderer, npc)
npc.sprite = s
eq(s.def and s.def.image, "pika.png", "a pipeline reading def gets the engine sprite's")
eq(EP.followerSprite(renderer, npc), s, "the same wrapper every tick")
s:draw(10, 20, 0, 0, "down", 0)
eq(rdraws, 1, "the wrapper draws our renderer")
s:draw(player.px, player.py, 0, 0, "down", 0)
eq(rdraws, 1, "...but not while it stands inside the player (a fresh map)")
EP._pipeline = true
eq(s.def, vsprite.def, "in a pipeline the follower's def is its voxel sheet's")
EP._pipeline = false
eq(s.def and s.def.image, "pika.png", "...outside one, the engine sprite's again")
eq(EP.followerSprite(nil, npc), base, "no renderer: the npc gets its own sprite back")

EP.uninstall()
eq(OverworldState.drawWorld ~= nil and EP._installed, false, "uninstall restores the engine")

-- ------- Gen 2 engine
generation = 2
local World = {}
function World.drawPeople(world)
  drawn.during = {}
  for _, e in ipairs(world.npcs) do drawn.during[#drawn.during + 1] = e end
  for _, e in ipairs(world.npcs) do if e.draw and e._wilds then e:draw(0, 0, 1, e.inGrass and "bottom" or nil) e:draw(0, 0, 1, "top") end end
end
function World.step(_world) end
function World.pollInput(world) world.heldDir = "down" end
function World.startBattle() end
fake["src.world.gen2.World"] = World
local unlocked = false
fake["src.core.gen2.Unown"] = { SPECIES = "UNOWN", anyUnlocked = function() return unlocked end,
  wildDVs = function() return { attack = 1, defense = 2, speed = 3, special = 4 } end }
fake["src.battle.gen2.Encounter"] = {
  grassSlot = function(t, mapId) local e = t.grass[mapId] return e and e.next end,
  waterSlot = function() return nil end,
}
fake["src.battle.gen2.Mon"] = {
  new = function(_d, sp, lv, o) return { species = sp, level = lv, dvs = o.dvs } end,
  randomDVs = function() return { attack = 10, defense = 10, speed = 10, special = 10 } end,
  isShiny = function(d) return d.speed == 10 and d.defense == 10 and d.special == 10 end,
}
fake["src.world.gen2.FieldMoves"] = {
  canEncounterWildMon = function(env, coll) return env == "CAVE" or coll == "g" or coll == "w" end,
  encounterTable = function(coll) return coll == "w" and "water" or "grass" end,
}
fake["src.world.gen2.Map"] = { isOutdoor = function() return true end }

local V2 = newEnv()
local EP2 = assert(loadfile("lib/engine_patch.lua"))(V2)
eq(EP2.layoutName(), "gen2", "layout gen2 on a Gen 2 boot")
local okP2, missing2 = EP2.probe()
check(okP2, "the Gen 2 probe passes on the fake engine (" .. table.concat(missing2 or {}, "; ") .. ")")
local p2 = { cellX = 1, cellY = 1, px = 16, py = 16 }
local tables = { grass = { ROUTE_29 = { slots = {}, next = { species = "SENTRET", level = 3 } } }, water = {} }
local game2 = { phase = "play", data = { pokemon = { SENTRET = { dex = 161 } } }, save = { pokedex = { caught = {} } },
  stack = { top = function() return nil end } }
local world = {
  map = fakeMap({ "#..g", ".ggg", "www." }), player = p2, camera = { x = 0, y = 0 }, npcs = {}, game = game2,
  busy = function() return false end, wildTables = function() return tables end, tod = "DAY",
  unownUnlockFlags = function() return {} end,
}
setmetatable(world, { __index = World })
world.map.def.environment = "ROUTE"
local gen2Draws = 0
check(EP2.install({ collectActors = function(actors)
  actors[1] = { kind = "wild_mon", x = 48, y = 16, sortY = 16, renderer = { draw = function() gen2Draws = gen2Draws + 1 end } }
end, followerTick = function() end }, nil), "install wraps the Gen 2 people pass, step and input")
World.step(world)
World.drawPeople(world)
eq(#drawn.during, 1, "while Gen 2 draws its people our actor is among them")
eq(gen2Draws, 1, "Crystal's grass split draws it once (whole on \"bottom\", nothing on \"top\")")
eq(#world.npcs, 0, "after the people pass world.npcs is the engine's again")

eq(EP2.terrainAt(1, 1), "land", "Gen 2 grass is land")
eq(EP2.terrainAt(0, 2), "water", "Gen 2 water is water")
eq(EP2.terrainAt(1, 0), nil, "a path outdoors is nothing")
world.map.def.environment = "CAVE"
eq(EP2.terrainAt(1, 0), "land", "a cave floor is land")
eq(EP2.terrainAt(0, 0), nil, "...a cave wall is not")
world.map.def.environment = "ROUTE"

local enc = EP2.rollSweetScent("ROUTE_29", "land")
check(enc and enc.species == "SENTRET" and enc.level == 3 and type(enc.dvs) == "table", "a Gen 2 roll carries its DVs")
eq(EP2.shinyDvs(enc.dvs), true, "...whose pattern decides the shiny")
tables.grass.ROUTE_29.next = { species = "UNOWN", level = 5 }
eq(EP2.rollSweetScent("ROUTE_29", "land"), nil, "an Unown slot with no puzzle solved is no encounter")
unlocked = true
local unown = EP2.rollSweetScent("ROUTE_29", "land")
check(unown and unown.dvs and unown.dvs.attack == 1, "with one solved it is an Unown of an unlocked letter")

local opts
World.startBattle = function(_w, o, done) opts = o; done("win") end
local doneWith
EP2.startWild(game2, { species = "SENTRET", level = 3, dvs = { attack = 10, defense = 10, speed = 10, special = 10 } },
  { done = function(r) doneWith = r end })
check(opts and opts.wild and opts.wild.species == "SENTRET" and opts.wild.dvs.speed == 10, "the battle Pokemon has the spawn's DVs")
eq(game2.save.pokedex.seen.SENTRET, true, "...and is seen in the Pokedex")
eq(doneWith, "win", "startBattle's onDone reaches our done")

-- the heal machine and Gen 2's `follow`
check(not EP2.healingActive(), "no heal machine running")
world.healAnim = {}
check(EP2.healingActive(), "Gen 2's heal animation: the follower goes into its ball")
world.healAnim = nil
check(not EP2.leadingNpc(), "nobody following")
world.followState = { leader = world.player, follower = { id = 3 } }
check(EP2.leadingNpc(), "an NPC following the player (follow)")
world.followState = { leader = { id = 2 }, follower = world.player }
check(EP2.leadingNpc(), "...or the player following one")
world.followState = { leader = { id = 2 }, follower = { id = 3 } }
check(not EP2.leadingNpc(), "two NPCs: not the player's business")
world.followState = nil

EP2.lockField("contact")
World.pollInput(world)
eq(world.heldDir, nil, "held: no direction is held on Gen 2")
EP2.unlockField("contact")
World.pollInput(world)
eq(world.heldDir, "down", "released: it is")
EP2.uninstall()

print("")
if failures > 0 then
  io.stderr:write(failures .. " failure(s)\n")
  os.exit(1)
end
print("engine_gb_unit_test: all passed")
