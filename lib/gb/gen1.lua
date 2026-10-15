-- Red / Blue / Yellow: the engine calls lib/engine_gb.lua needs, against Gen1Recomp's
-- Gen 1 overworld (src/world/OverworldController.lua, `ow` = the OverworldState). Every
-- call is guarded by the caller; nothing here keeps state.
local Gen1 = { generation = 1, layout = "gen1" }

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

--- { land = bool, water = bool } for the map's encounter table.
function Gen1.tables(_ow, mapId)
  local def = encDef(mapId)
  return { land = hasSlots(def and def.grass), water = hasSlots(def and def.water) }
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
