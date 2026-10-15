-- Gold / Silver / Crystal: the engine calls lib/engine_gb.lua needs, against Gen1Recomp's
-- Gen 2 overworld (src/world/gen2/World.lua, `world` = the World). Every call is guarded
-- by the caller; nothing here keeps state.
local Gen2 = { generation = 2, layout = "gen2" }

local load = function() return nil end
function Gen2.init(loadModule) load = loadModule end

local WORLD = "src.world.gen2.World"

-- wrapped (lib/engine_gb.lua install): the people pass, the logic step, the input poll
Gen2.TARGETS = {
  draw = { mod = WORLD, field = "drawPeople" }, -- draws world.npcs y-sorted (World.lua:11727)
  tick = { mod = WORLD, field = "step" },       -- one logic frame (World.lua:11321)
  input = { mod = WORLD, field = "pollInput" }, -- the held direction (World.lua:11553)
}
-- optional: where a render pipeline mod (Stadium2) draws the world (World.lua:11864)
Gen2.PIPELINE = { mod = WORLD, field = "drawPipeline" }
-- read, never wrapped
Gen2.READONLY = {
  grassSlot = { mod = "src.battle.gen2.Encounter", field = "grassSlot" },
  waterSlot = { mod = "src.battle.gen2.Encounter", field = "waterSlot" },
  monNew = { mod = "src.battle.gen2.Mon", field = "new" },
  randomDVs = { mod = "src.battle.gen2.Mon", field = "randomDVs" },
  canEncounter = { mod = "src.world.gen2.FieldMoves", field = "canEncounterWildMon" },
  encounterTable = { mod = "src.world.gen2.FieldMoves", field = "encounterTable" },
  startBattle = { mod = WORLD, field = "startBattle" },
}

function Gen2.game(world)
  return world and world.game
end

function Gen2.data(world)
  local game = world and world.game
  return game and game.data
end

function Gen2.save(world)
  local game = world and world.game
  return game and game.save
end

function Gen2.camera(world)
  local cam = world and world.camera
  if not cam then return nil end
  return cam.x or 0, cam.y or 0
end

function Gen2.viewSize(world)
  return tonumber(world and world.viewW) or 160, tonumber(world and world.viewH) or 144
end

--- Is something other than the player's free walking in charge? World:busy() (a script,
--- text, a choice, a field move, Fly ...), a battle, or any screen on the game's stack:
--- Game2 only steps the world while the stack is empty (Game2.lua:1316).
function Gen2.busy(world)
  if not world then return true end
  local game = world.game
  if game then
    if game.phase ~= nil and game.phase ~= "play" then return true end
    local stack = game.stack
    if stack and stack.top then
      local ok, top = pcall(stack.top, stack)
      if ok and top ~= nil then return true end
    end
  end
  if world.battleActive or world.mapSetup ~= nil then return true end
  if world.busy then
    local ok, busy = pcall(world.busy, world)
    if ok and busy then return true end
  end
  return false
end

--- Gen 2's wild-encounter tiles (World:tryWildEncounter, World.lua:4498): the tile's
--- collision byte allows an encounter (grass and water; in a cave or dungeon any tile
--- but ice), and the table is water on a water tile. Returns "land" | "water" | nil.
function Gen2.terrainAt(world, x, y)
  local map = world and world.map
  if not (map and map.inBounds and map:inBounds(x, y)) then return nil end
  local FieldMoves = load("src.world.gen2.FieldMoves")
  if not (FieldMoves and FieldMoves.canEncounterWildMon and FieldMoves.encounterTable) then return nil end
  local coll = map:cellCollision(x, y)
  local env = map.def and map.def.environment
  local okE, can = pcall(FieldMoves.canEncounterWildMon, env, coll, world.noWildEncounters)
  if not (okE and can) then return nil end
  local okT, kind = pcall(FieldMoves.encounterTable, coll)
  if okT and kind == "water" then
    return map:isWaterCell(x, y) and "water" or nil
  end
  -- a cave allows every collision byte but ice: keep to the floor
  return map:isWalkableCell(x, y) and "land" or nil
end

local function wildTables(world)
  if not world then return nil end
  if world.wildTables then
    local ok, t = pcall(world.wildTables, world)
    if ok and type(t) == "table" then return t end
  end
  return world.encounters
end

--- { land = bool, water = bool } for the map's encounter table.
function Gen2.tables(world, mapId)
  local t = wildTables(world)
  local grass = t and t.grass and t.grass[mapId]
  local water = t and t.water and t.water[mapId]
  return { land = type(grass) == "table" and grass.slots ~= nil, water = type(water) == "table" and water.slots ~= nil }
end

--- One encounter for `terrain` on `mapId` with the engine's own slot pick (the time of
--- day's grass list, or the water list), DVs rolled now so the Pokemon shown -- shiny,
--- Unown letter -- is the one met: { species, level, dvs } or nil. An Unown slot with no
--- Ruins of Alph puzzle solved is no encounter, as on the cart.
function Gen2.roll(world, mapId, terrain, _rng)
  local Encounter = load("src.battle.gen2.Encounter")
  local Mon = load("src.battle.gen2.Mon")
  local t = wildTables(world)
  if not (Encounter and Mon and t) then return nil end
  local ok, hit
  if terrain == "water" then
    ok, hit = pcall(Encounter.waterSlot, t, mapId, nil)
  else
    ok, hit = pcall(Encounter.grassSlot, t, mapId, world.tod, nil)
  end
  if not (ok and type(hit) == "table" and hit.species) then return nil end
  local enc = { species = hit.species, level = tonumber(hit.level) or 5 }
  local Unown = load("src.core.gen2.Unown")
  if Unown and hit.species == Unown.SPECIES then
    local flags = world.unownUnlockFlags and select(2, pcall(world.unownUnlockFlags, world))
    if not (type(flags) == "table" and Unown.anyUnlocked(flags)) then return nil end
    local okD, dvs = pcall(Unown.wildDVs, flags, Mon.randomDVs)
    enc.dvs = okD and dvs or nil
  else
    local okD, dvs = pcall(Mon.randomDVs)
    enc.dvs = okD and dvs or nil
  end
  return enc
end

--- CheckRepelEffect (World:repelSuppresses).
function Gen2.repelAllows(world, level)
  if not (world and world.repelSuppresses) then return true end
  local ok, suppressed = pcall(world.repelSuppresses, world, level)
  return not (ok and suppressed)
end

--- The wild battle, the way World:tryWildEncounter starts one: Mon.new with the DVs the
--- spawn rolled, seen in the Pokedex, World:startBattle.
function Gen2.startWild(world, enc, done)
  local Mon = load("src.battle.gen2.Mon")
  local game = world and world.game
  if not (Mon and game and world.startBattle) then return nil, "Gen 2 battle unavailable" end
  local dvs
  if type(enc.dvs) == "table" then
    dvs = { attack = enc.dvs.attack, defense = enc.dvs.defense, speed = enc.dvs.speed, special = enc.dvs.special }
  end
  local ok, wild = pcall(Mon.new, game.data, enc.species, tonumber(enc.level) or 5, { wild = true, dvs = dvs })
  if not (ok and wild) then return nil, "Mon.new failed: " .. tostring(wild) end
  local save = game.save
  if save then
    save.pokedex = save.pokedex or { seen = {}, caught = {} }
    save.pokedex.seen = save.pokedex.seen or {}
    save.pokedex.seen[enc.species] = true
  end
  local okB, err = pcall(world.startBattle, world, { wild = wild }, function(result)
    if done then done(result) end
  end)
  if not okB then return nil, "startBattle failed: " .. tostring(err) end
  return true
end

local function playerState(world)
  local save = Gen2.save(world)
  return (world and world.playerState) or (save and save.playerState)
end

function Gen2.isSurfing(world)
  local FieldMoves = load("src.world.gen2.FieldMoves")
  local state = playerState(world)
  if FieldMoves and FieldMoves.isSurfing then
    local ok, yes = pcall(FieldMoves.isSurfing, state)
    if ok then return yes == true end
  end
  return state == "surf" or state == "surf_pika"
end

function Gen2.isBiking(world)
  local FieldMoves = load("src.world.gen2.FieldMoves")
  local state = playerState(world)
  if FieldMoves and FieldMoves.isBiking then
    local ok, yes = pcall(FieldMoves.isBiking, state)
    if ok then return yes == true end
  end
  return state == "bike"
end

function Gen2.isCaught(species, world)
  local save = Gen2.save(world)
  local dex = save and save.pokedex
  if not (dex and species) then return false end
  return (type(dex.caught) == "table" and dex.caught[species] == true)
    or (type(dex.owned) == "table" and dex.owned[species] == true)
end

--- Gen 2 shininess from DVs (Mon.isShiny: the classic pattern, or a mod's shiny.roll).
function Gen2.shinyDvs(dvs)
  local Mon = load("src.battle.gen2.Mon")
  if not (Mon and Mon.isShiny and type(dvs) == "table") then return false end
  local ok, yes = pcall(Mon.isShiny, dvs)
  return ok and yes == true
end

function Gen2.isShiny(mon)
  return type(mon) == "table" and Gen2.shinyDvs(mon.dvs)
end

function Gen2.isOutdoor(world)
  local Map = load("src.world.gen2.Map")
  local def = world and world.map and world.map.def
  if not (Map and Map.isOutdoor and def) then return true end
  local ok, out = pcall(Map.isOutdoor, def)
  return not ok or out == true
end

--- The input wrap: while `isHeld()` no direction is held this frame (the step reads
--- world.heldDir, which pollInput sets).
function Gen2.inputWrapper(original, isHeld)
  return function(self, ...)
    local a, b, c = original(self, ...)
    if isHeld() then self.heldDir = nil end
    return a, b, c
  end
end

--- The per-frame wrap's world: World:step()'s self.
function Gen2.tickWrapper(original, after)
  return function(self, ...)
    local a, b, c = original(self, ...)
    after(self, self.game)
    return a, b, c
  end
end

--- The engine's party follower (src/world/gen2/Follower.lua), flagged `pikachuFollower`.
function Gen2.follower(world)
  for _, npc in ipairs(world and world.npcs or {}) do
    if npc.pikachuFollower then return npc end
  end
  return nil
end

--- The world that has `map` loaded: Gold's one World (game.world).
function Gen2.liveWorld(game, map)
  local w = game and game.world
  if type(w) == "table" and w.map and (map == nil or w.map == map) then return w end
  return nil
end

function Gen2.party(world)
  local save = Gen2.save(world)
  return save and save.party
end

return Gen2
