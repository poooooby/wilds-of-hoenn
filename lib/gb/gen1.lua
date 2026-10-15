-- Red / Blue / Yellow: the engine calls lib/engine_gb.lua needs, against Gen1Recomp's
-- Gen 1 overworld (src/world/OverworldController.lua, `ow` = the OverworldState). Every
-- call is guarded by the caller; nothing here keeps state.
local Gen1 = { generation = 1, layout = "gen1" }

-- the ambient systems main.lua may build on this generation (EnginePatch.supports)
Gen1.FEATURES = { sky = true, water_life = true, local_scenes = true, wild_reacts = true }

local load = function() return nil end
function Gen1.init(loadModule) load = loadModule end

local OW = "src.world.OverworldController"

-- wrapped (lib/engine_gb.lua install): the world pass, the per-frame update, the input poll
Gen1.TARGETS = {
  draw = { mod = OW, field = "drawWorld" },   -- draws ow.entities y-sorted (OverworldController.lua:6473)
  tick = { mod = OW, field = "update" },      -- the overworld's frame (OverworldController.lua:1408)
  input = { mod = OW, field = "handleInput" }, -- where a held direction starts a step (:1791)
}
-- read, never wrapped
Gen1.READONLY = {
  newWild = { mod = "src.battle.BattleState", field = "newWild" },
  indoor = { mod = OW, field = "rollsIndoorEncounters" },
  isOutdoor = { mod = "src.world.Map", field = "isOutdoor" },
}

function Gen1.game()
  return load("src.core.Game")
end

function Gen1.data()
  local Game = Gen1.game()
  return Game and Game.data
end

function Gen1.save()
  local Game = Gen1.game()
  return Game and Game.save
end

function Gen1.camera(ow)
  local cam = ow and ow.camera
  if not cam then return nil end
  return cam.x or 0, cam.y or 0
end

function Gen1.viewSize(_ow)
  local Game = Gen1.game()
  local r = Game and Game.renderer
  if r and r.worldViewSize then
    local ok, w, h = pcall(r.worldViewSize, r)
    if ok and tonumber(w) and tonumber(h) then return w, h end
  end
  return 160, 144
end

--- Is something other than the player's free walking in charge? The update's own
--- `scripted` gate (OverworldController.lua:1667), the animations that return early
--- before it, a warp, and any screen pushed over the overworld (text, menus, a battle).
function Gen1.busy(ow)
  if not ow then return true end
  local Game = Gen1.game()
  if Game and Game.stack and Game.stack.top then
    local ok, top = pcall(Game.stack.top, Game.stack)
    if ok and top ~= ow then return true end
  end
  local runner = ow.runner
  if runner and runner.isRunning then
    local ok, running = pcall(runner.isRunning, runner)
    if ok and running then return true end
  end
  if ow.scriptMoves and #ow.scriptMoves > 0 then return true end
  if (ow.hopLand or 0) > 0 or (ow.poisonFlash or 0) > 0 then return true end
  return (ow.engaging or ow.emote or ow.teleportOut or ow.flyAnim or ow.flyArrive or ow.flyFade
    or ow.spinArrive or ow.holeFall or ow.holeArrive or ow.cutAnim or ow.healAnim or ow.pikaHop
    or ow.transitioning or (ow.dustAnim and ow.dustAnim.boulder)) and true or false
end

--- Gen 1's wild-encounter tiles (OverworldController.lua:4920): tall grass, water, and
--- -- on an indoor map whose tileset is not FOREST (caves, towers, the Mansion) -- every
--- floor tile. Returns "land" | "water" | nil.
function Gen1.terrainAt(ow, x, y)
  local map = ow and ow.map
  if not (map and map.inBounds and map:inBounds(x, y)) then return nil end
  if map:isGrassCell(x, y) then return "land" end
  if map:isWaterCell(x, y) then return "water" end
  local O = load(OW)
  local data = Gen1.data()
  if O and O.rollsIndoorEncounters and data and data.field then
    local ok, indoor = pcall(O.rollsIndoorEncounters, map.def, data.field.indoorEncounters)
    if ok and indoor and map:isWalkableCell(x, y) then return "land" end
  end
  return nil
end

local function encDef(mapId)
  local data = Gen1.data()
  local all = data and data.encounters
  return type(all) == "table" and all[mapId] or nil
end

local function hasSlots(t)
  return type(t) == "table" and (tonumber(t.rate) or 0) > 0 and type(t.slots) == "table" and #t.slots > 0
end

--- The species def for a string key ("MAGIKARP") or a national dex number.
local dexToKey -- [dex] = key, built once
function Gen1.speciesDef(species)
  local data = Gen1.data()
  local mons = data and data.pokemon
  if type(mons) ~= "table" or species == nil then return nil, nil end
  if type(species) == "string" then return mons[species], species end
  local n = tonumber(species)
  if not n then return nil, nil end
  if not dexToKey then
    dexToKey = {}
    for key, def in pairs(mons) do
      local dex = type(def) == "table" and tonumber(def.dex)
      if dex and type(key) == "string" and dexToKey[dex] == nil then dexToKey[dex] = key end
    end
  end
  local key = dexToKey[n]
  return key and mons[key] or nil, key
end

-- a slot list with its species as NATIONAL DEX numbers (the ambient systems -- the sky,
-- the water -- collect species with tonumber(); the string keys stay for battles)
local function dexSlots(slots)
  local out
  for _, s in ipairs(slots or {}) do
    local def = type(s) == "table" and Gen1.speciesDef(s.species)
    local dex = def and tonumber(def.dex)
    if dex then
      out = out or {}
      out[#out + 1] = { species = dex, level = tonumber(s.level) or 5 }
    end
  end
  return out
end

--- The map's encounter areas, with slot lists for the ambient systems: `land` / `water`
--- = { slots = {{species = dex, level}, ...} } (true-ish, as the presence checks read it),
--- `fishing` = the rods' pools (Super Rod per map, Good Rod's pool, Old Rod's Magikarp).
function Gen1.tables(_ow, mapId)
  local def = encDef(mapId)
  local out = {}
  if hasSlots(def and def.grass) then out.land = { slots = dexSlots(def.grass.slots) } end
  if hasSlots(def and def.water) then out.water = { slots = dexSlots(def.water.slots) } end
  local data = Gen1.data()
  local FD = load("src.world.FieldDefaults")
  if data and FD and FD.field then
    -- the rods (OverworldController.lua fishingPool): Old always Magikarp, Good a fixed
    -- pool, Super the per-map groups under field[perMap]
    local okF, rods = pcall(FD.field, data, "fishing")
    local fish = {}
    for _, rod in pairs(okF and type(rods) == "table" and rods or {}) do
      if type(rod) == "table" then
        if type(rod.always) == "table" then fish[#fish + 1] = rod.always end
        for _, s in ipairs(type(rod.pool) == "table" and rod.pool or {}) do fish[#fish + 1] = s end
        local groups = rod.perMap and data.field and data.field[rod.perMap]
        local per = type(groups) == "table" and groups[mapId]
        for _, s in ipairs(type(per) == "table" and per or {}) do fish[#fish + 1] = s end
      end
    end
    local slots = dexSlots(fish)
    if slots then out.fishing = { slots = slots } end
  end
  return out
end

--- One encounter for `terrain` on `mapId`, picked with the game's own slot buckets
--- (Encounter.roll without its per-step rate gate): { species, level } or nil.
function Gen1.roll(_ow, mapId, terrain, rng)
  local def = encDef(mapId)
  if not def then return nil end
  local t
  if terrain == "water" then t = def.water else t = def.grass end
  if not hasSlots(t) then return nil end
  rng = rng or math.random
  local buckets = t.buckets
  if not buckets then
    local FD = load("src.world.FieldDefaults")
    local data = Gen1.data()
    if FD and FD.constant then
      local ok, b = pcall(FD.constant, data, "encounterBuckets")
      if ok and type(b) == "table" then buckets = b end
    end
    buckets = buckets or (FD and FD.CONSTANTS and FD.CONSTANTS.encounterBuckets)
  end
  if type(buckets) ~= "table" then return nil end
  local pick = rng(0, 255)
  for i, threshold in ipairs(buckets) do
    if pick < threshold then
      local slot = t.slots[i]
      if slot and slot.species then return { species = slot.species, level = tonumber(slot.level) or 5 } end
      return nil
    end
  end
  return nil
end

--- REPEL (OverworldController.lua:4935): no wild Pokemon weaker than the lead while it lasts.
function Gen1.repelAllows(_ow, level)
  local save = Gen1.save()
  if not (save and (tonumber(save.repelSteps) or 0) > 0) then return true end
  local lead = save.party and save.party[1]
  return not (lead and tonumber(level) and tonumber(lead.level) and level < lead.level)
end

--- The wild battle, built the way the engine's own step encounter builds it
--- (OverworldController.lua:4940): the ghost of the Pokemon Tower without the Silph
--- Scope, a Safari battle in the Safari Zone, afterBattle on the way out.
function Gen1.startWild(ow, enc, done)
  local Game = Gen1.game()
  local BattleState = load("src.battle.BattleState")
  if not (Game and ow and BattleState and BattleState.newWild and ow.pushBattle) then
    return nil, "Gen 1 battle unavailable"
  end
  local ok, battle = pcall(BattleState.newWild, Game, enc.species, tonumber(enc.level) or 5)
  if not ok or not battle then return nil, "newWild failed: " .. tostring(battle) end
  battle.checkpointOrigin = { kind = "wild_encounter", map = ow.map and ow.map.id }
  local Map = load("src.world.Map")
  local def = ow.map and ow.map.def
  if Map and def then
    local okG, ghost = pcall(Map.ghostBattles, def)
    local inv = Game.save and Game.save.inventory
    if okG and ghost and not (ghost.unlessItem and inv and inv[ghost.unlessItem]) and battle.makeGhost then
      pcall(battle.makeGhost, battle)
    end
    local okS, safari = pcall(Map.inRegion, def, "SAFARI", "SAFARI_ZONE")
    if Game.save and Game.save.safari and okS and safari and battle.makeSafari then
      pcall(battle.makeSafari, battle, Game.save.safari)
    end
  end
  battle.onFinish = function(result)
    if ow.afterBattle then ow:afterBattle(result, battle) end
    if done then done(result) end
  end
  local okP, err = pcall(ow.pushBattle, ow, battle)
  if not okP then return nil, "pushBattle failed: " .. tostring(err) end
  return true
end

function Gen1.isSurfing(ow)
  local p = ow and ow.player
  return p ~= nil and p.surfing == true
end

function Gen1.isBiking(ow)
  local save = Gen1.save()
  return (save and save.onBike == true) or (ow and ow.player and ow.player.onBike == true) or false
end

--- Owned in the Pokedex (BattleState.markOwned writes `owned`).
function Gen1.isCaught(species)
  local save = Gen1.save()
  local dex = save and save.pokedex
  if not (dex and species) then return false end
  return (type(dex.owned) == "table" and dex.owned[species] == true)
    or (type(dex.caught) == "table" and dex.caught[species] == true)
end

function Gen1.isShiny(_mon)
  return false -- Gen 1 has no shiny Pokemon
end

function Gen1.isOutdoor(ow)
  local Map = load("src.world.Map")
  local def = ow and ow.map and ow.map.def
  if not (Map and Map.isOutdoor and def) then return true end
  local ok, out = pcall(Map.isOutdoor, def)
  return not ok or out == true
end

--- A town or city (the maps the Fly list knows, Map.isFlyTown): where the sky's birds
--- may perch. 1 town, 3 route, 4 inside -- the Gen 3 map-type numbers the mod reads.
function Gen1.mapTypeOf(ow)
  if not Gen1.isOutdoor(ow) then return 4 end
  local Map = load("src.world.Map")
  local def = ow and ow.map and ow.map.def
  if Map and Map.isFlyTown and def then
    local ok, town = pcall(Map.isFlyTown, def)
    if ok and town then return 1 end
  end
  return 3
end

--- Does `species` (string key or national dex) have `wanted` among its types?
function Gen1.hasType(species, wanted)
  local def = Gen1.speciesDef(species)
  for _, t in ipairs(def and def.types or {}) do
    if t == wanted then return true end
  end
  return false
end

--- Pokedex height in decimetres (the dex entry's feet and inches).
function Gen1.heightDm(species)
  local def = Gen1.speciesDef(species)
  local e = def and def.dexEntry
  if not e then return nil end
  local ft, inch = tonumber(e.heightFt), tonumber(e.heightIn)
  if not (ft or inch) then return nil end
  local m = (ft or 0) * 0.3048 + (inch or 0) * 0.0254
  return math.floor(m * 10 + 0.5)
end

--- The sum of the base stats (Gen 1's five).
function Gen1.baseStatTotal(species)
  local def = Gen1.speciesDef(species)
  local b = def and def.baseStats
  if type(b) ~= "table" then return nil end
  local sum = 0
  for _, v in pairs(b) do sum = sum + (tonumber(v) or 0) end
  return sum > 0 and sum or nil
end

--- The ids of the maps joined to this one (the live neighbour list the engine draws).
function Gen1.neighbourIds(ow)
  local out = {}
  for _, n in ipairs(ow and ow.neighbors or {}) do
    local id = type(n) == "table" and type(n.map) == "table" and n.map.id
    if id then out[#out + 1] = id end
  end
  return out
end

--- Is an engine character (an NPC, the follower, a boulder) on cell (x, y)?
function Gen1.objectOn(ow, x, y)
  for _, npc in ipairs(ow and ow.npcs or {}) do
    if npc.cellX == x and npc.cellY == y then return true end
    if npc.moving and npc.targetX == x and npc.targetY == y then return true end
  end
  return false
end

--- The map's signposts, { {x, y}, ... } (map def signs).
function Gen1.signCells(ow)
  local out = {}
  for _, s in ipairs(ow and ow.map and ow.map.def and ow.map.def.signs or {}) do
    if tonumber(s.x) and tonumber(s.y) then out[#out + 1] = { x = s.x, y = s.y } end
  end
  return out
end

function Gen1.playCry(species)
  local data = Gen1.data()
  local Sound = load("src.core.Sound")
  local _, key = Gen1.speciesDef(species)
  if not (data and Sound and Sound.playCry and key) then return nil end
  pcall(Sound.playCry, data, key)
end

--- The engine's emote bubbles ("!" frame 0, "?" frame 1) as the sheet shape the mod reads
--- ({ image, quads }): the OBJ-palette art re-shaded the way the engine's own emote draw
--- does (OverworldController.lua obpEmoteImage), built once.
local emoteSheet
function Gen1.emoteSheet()
  if emoteSheet ~= nil then return emoteSheet or nil end
  emoteSheet = false
  local data = Gen1.data()
  local bubble = data and data.field and data.field.emotionBubbles
  if not (bubble and bubble.path and love and love.graphics) then return nil end
  local Assets = load("src.render.Assets")
  local ok, sheet = pcall(function()
    local img
    if love.image and love.image.newImageData and Assets and Assets.imageData then
      local id = Assets.imageData(bubble.path)
      id:mapPixel(function(_, _, r, _, _, a)
        local v = 0
        if r > 0.5 then v = 1
        elseif r > 0.17 then v = 170 / 255 end
        return v, v, v, a
      end)
      img = love.graphics.newImage(id)
    elseif Assets and Assets.resolve then
      img = love.graphics.newImage(Assets.resolve(bubble.path))
    end
    if not img then return nil end
    local quads = {}
    -- the mod reads frames 0 ("!") and 1 ("?"); the engine's crops are 1 EXCLAMATION,
    -- 2 QUESTION (emotion_bubbles.asm order)
    for i, rect in ipairs(bubble.bubbles or {}) do
      if i <= 2 and rect.w then
        quads[i - 1] = love.graphics.newQuad(rect.x, rect.y, rect.w, rect.h, img:getDimensions())
      end
    end
    return { image = img, quads = quads, fw = 16, fh = 16, frames = 2 }
  end)
  if ok and sheet then emoteSheet = sheet end
  return emoteSheet or nil
end

--- The input wrap: while `isHeld()` the overworld reads no input this frame, so a held
--- direction cannot start a step (handleInput is where it does, :1689).
function Gen1.inputWrapper(original, isHeld)
  return function(self, ...)
    if isHeld() then return end
    return original(self, ...)
  end
end

--- The per-frame wrap's world: OverworldState:update(dt)'s self.
function Gen1.tickWrapper(original, after)
  return function(self, ...)
    local a, b, c = original(self, ...)
    after(self, Gen1.game())
    return a, b, c
  end
end

--- The engine's party follower (Yellow's Pikachu; any mod's companion in Red / Blue):
--- PikachuFollower's npc, flagged `pikachuFollower`.
function Gen1.follower(ow)
  for _, npc in ipairs(ow and ow.npcs or {}) do
    if npc.pikachuFollower then return npc end
  end
  return nil
end

--- The overworld that has `map` loaded: the state on top of the game's stack (it is pushed
--- before it loads its map), else nil.
function Gen1.liveWorld(game, map)
  game = game or Gen1.game()
  local stack = game and game.stack
  if not (stack and stack.top) then return nil end
  local ok, top = pcall(stack.top, stack)
  if ok and type(top) == "table" and top.player and top.map and (map == nil or top.map == map) then return top end
  return nil
end

function Gen1.party()
  local save = Gen1.save()
  return save and save.party
end

return Gen1
