-- Modern Spawns bridge: visible spawns use the species Modern Spawns
-- generated for a map, when that mod is installed and active.
--
-- This mod gets its encounters from EnginePatch.rollSweetScent, which calls
-- the engine's rules directly -- the `encounter.roll` / `encounter.species`
-- hooks Modern Spawns uses for step encounters never run for it. Modern
-- Spawns never rewrites the game's tables either; it publishes them through
-- mod.exports (drawFor / legendaryFor / profileOf, apiVersion >= 1). So after
-- the engine rolls a slot, this module swaps that slot's species for the one
-- Modern Spawns generated in the same slot -- the same "keep the rolled slot,
-- level and personality, replace only the species" step Modern Spawns itself
-- applies on Gen 3 (adapter substituteAfterRoll).
--
-- Soft integration, same as Wilds of Kanto Revival: no dependency. Absent,
-- OFF, GEN 1, not a Gen 3 table shape, or no table for the map -> the engine's
-- own encounter passes through untouched.
local V = ...
local EnginePatch = V.require("engine_patch")

local Bridge = {}

-- Modern Spawns' exports when installed and active, else nil.
function Bridge.api()
  local mod = V.mod
  if not (mod and type(mod.find) == "function") then return nil end
  local ok, other = pcall(mod.find, mod, "modern_spawns")
  local api = ok and other and other.exports
  if type(api) ~= "table" or (tonumber(api.apiVersion) or 0) < 1 then return nil end
  if type(api.drawFor) ~= "function" or type(api.profileOf) ~= "function" then return nil end
  local okActive, active = pcall(api.isActive)
  if not (okActive and active) then return nil end
  -- Gen 3 table shape: { rate, slots = { { species, minLevel, maxLevel } } }
  local okGen, gen = pcall(api.generation)
  if not (okGen and gen == 3) then return nil end
  return api
end

local function kindOf(terrain)
  return terrain == "water" and "water" or "grass"
end

-- Modern Spawns' species id ("PIDGEY") -> this engine's internal species id,
-- through the national dex number its profile carries. nil for a species the
-- running engine has no slot for (the caller then keeps the engine's own).
local function internalFor(api, id)
  if type(id) ~= "string" then return nil end
  local ok, profile = pcall(api.profileOf, id)
  local dex = ok and type(profile) == "table" and tonumber(profile.dex) or nil
  return dex and EnginePatch.speciesForNational(dex) or nil
end

-- The slot of the engine's own table that `enc` was rolled from: same
-- species, level inside the slot's range. Slot order matches Modern Spawns'
-- generated table, which keeps the game's slot order. nil when it matches no
-- slot (an outbreak or other special encounter).
local function slotIndexOf(mapId, terrain, enc)
  local t = EnginePatch.tableFor(mapId)
  if type(t) ~= "table" then return nil end
  local area = terrain == "water" and t.water or (t.land or t.grass)
  local slots = type(area) == "table" and (area.slots or area.mons or area) or nil
  if type(slots) ~= "table" then return nil end
  local level = tonumber(enc.level)
  for i, s in ipairs(slots) do
    if type(s) == "table" and tonumber(s.species or s[1]) == tonumber(enc.species) then
      local lo = tonumber(s.minLevel or s.level or s[2])
      local hi = tonumber(s.maxLevel or s.level or s[2]) or lo
      if lo and hi and lo > hi then lo, hi = hi, lo end
      if not (level and lo) or (level >= lo and level <= hi) then return i end
    end
  end
  return nil
end

local function withSpecies(enc, species)
  local copy = {}
  for k, v in pairs(enc) do copy[k] = v end
  copy.species = species
  if copy.speciesId ~= nil then copy.speciesId = species end
  return copy
end

--- `enc` (from EnginePatch.rollSweetScent) with its species replaced by the
--- one Modern Spawns generated for that slot, or `enc` itself when there is
--- nothing to change. Roamers are never touched. Never throws.
function Bridge.apply(mapId, terrain, enc)
  if type(enc) ~= "table" or enc.roamer or mapId == nil then return enc end
  local api = Bridge.api()
  if not api then return enc end
  local kind = kindOf(terrain)

  -- the LEGENDARIES roll: a rare hosted legendary/mythical in place of the slot
  if type(api.legendaryFor) == "function" then
    local ok, id = pcall(api.legendaryFor, mapId, kind)
    local species = ok and internalFor(api, id) or nil
    if species then return withSpecies(enc, species) end
  end

  local ok, generated = pcall(api.drawFor, mapId, kind)
  if not (ok and type(generated) == "table" and type(generated.slots) == "table") then
    return enc
  end
  local index = slotIndexOf(mapId, terrain, enc)
  local slot = index and generated.slots[index]
  local species = slot and internalFor(api, slot.species)
  if not species then return enc end
  return withSpecies(enc, species)
end

return Bridge
