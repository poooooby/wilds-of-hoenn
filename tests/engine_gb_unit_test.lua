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
      PIKACHU = { dex = 25, types = { "ELECTRIC" }, dexEntry = { heightFt = 1, heightIn = 4 },
                  baseStats = { hp = 35, attack = 55, defense = 30, speed = 90, special = 50 } },
      PIDGEY = { dex = 16, types = { "NORMAL", "FLYING" }, dexEntry = { heightFt = 1, heightIn = 0 } },
      RATTATA = { dex = 19, types = { "NORMAL" } },
      GOLDEEN = { dex = 118, types = { "WATER" }, dexEntry = { heightFt = 2, heightIn = 0 } },
      MAGIKARP = { dex = 129, types = { "WATER" }, dexEntry = { heightFt = 2, heightIn = 11 } },
      TENTACOOL = { dex = 72, types = { "WATER", "POISON" }, dexEntry = { heightFt = 2, heightIn = 11 } },
    },
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
eq(EP.supports("roles"), false, "the partner roles are not carried yet")

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
eq(EP.fieldEffectSheet("ground_impact_dust"), nil, "other sheets stay absent")

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
