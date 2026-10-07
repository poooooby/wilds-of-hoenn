-- Per-map eligible-cell listing and wild table presence, read entirely from
-- the engine (EnginePatch): no reimplemented terrain/encounter rules.
local V = ...
local EnginePatch = V.require("engine_patch")
local Reachability = V.require("reachability")

local EncounterSource = {}
EncounterSource.__index = EncounterSource

function EncounterSource.new(mod)
  return setmetatable({
    mod = mod,
    mapId = nil,
    skip = true,
    hasLand = false,
    hasWater = false,
    cells = { land = {}, water = {} },
  }, EncounterSource)
end

--- Rescans the current map: cell terrain classification (land/water, from
--- the ROM's metatile encounter type) and whether its wild table has a
--- land/water area at all. Called on map.entered.
function EncounterSource:loadMap(mapId)
  self.mapId = mapId
  self.reachable = nil
  self.cells = { land = {}, water = {} }
  self.hasLand, self.hasWater = false, false

  -- Battle Pike / Battle Pyramid: wild generation there is special-cased
  -- (facilityEncounter in encounter_rules/rse.lua) and this mod adds no
  -- visible spawns on those maps -- see docs/ARCHITECTURE.md "What v1
  -- deliberately leaves out".
  if EnginePatch.isSweetScentFacility(mapId) then
    self.skip = true
    return
  end
  -- Safari Zone (Ruby / Sapphire / Emerald and FireRed / LeafGreen): the
  -- engine runs those battles itself, with balls and bait.
  if EnginePatch.safariActive() then
    self.skip = true
    return
  end
  self.skip = false

  EnginePatch.ensureEncountersLoaded()
  local t = EnginePatch.tableFor(mapId)
  self.hasLand = type(t) == "table" and (t.land ~= nil or t.grass ~= nil)
  self.hasWater = type(t) == "table" and t.water ~= nil
  if not (self.hasLand or self.hasWater) then return end

  local w, h = EnginePatch.mapBounds()
  for y = 0, h - 1 do
    for x = 0, w - 1 do
      local terrain = EnginePatch.terrainAt(x, y)
      if terrain == "land" and self.hasLand then
        self.cells.land[#self.cells.land + 1] = { x = x, y = y }
      elseif terrain == "water" and self.hasWater then
        self.cells.water[#self.cells.water + 1] = { x = x, y = y }
      end
    end
  end
end

--- The current map's eligible cells for `terrain` ("land" | "water"), a
--- fresh array of {x, y} tables (copy-on-read, same contract as
--- Gen1Recomp's own ow.entities facade -- callers must not mutate it
--- across calls and expect the mutation to persist).
function EncounterSource:eligibleCells(terrain)
  local list = self.cells[terrain]
  if not list then return {} end
  local reachable = self.reachable
  local out = {}
  for i = 1, #list do
    local c = list[i]
    if not reachable or Reachability.has(reachable, c.x, c.y) then
      out[#out + 1] = { x = c.x, y = c.y }
    end
  end
  return out
end

--- Restricts eligibleCells to a reachable set (lib/reachability.lua build()),
--- or lifts the restriction with nil. Reachability is a view over the cells
--- loadMap found, so it can be swapped without rescanning the map.
function EncounterSource:setReachable(set)
  self.reachable = set
end

function EncounterSource:isEligible()
  return not self.skip and (self.hasLand or self.hasWater)
end

return EncounterSource
