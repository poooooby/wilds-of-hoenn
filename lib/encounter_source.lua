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
    view = { land = {}, water = {} }, -- cells after the reachable filter (_rebuildView)
  }, EncounterSource)
end

--- Whether a swimmer may stand on water cell (x, y): the cell south of it is water too.
--- A swimmer is drawn a little below its tile (its waterline, for perspective), so on the
--- last row before a bank it would sit on the bank and look like it bobs on the ground.
function EncounterSource.openWater(x, y)
  return not EnginePatch.isWater or EnginePatch.isWater(x, y + 1)
end

--- Rescans the current map: cell terrain classification (land/water, from
--- the ROM's metatile encounter type) and whether its wild table has a
--- land/water area at all. Called on map.entered.
function EncounterSource:loadMap(mapId)
  self.mapId = mapId
  self.reachable = nil
  self.cells = { land = {}, water = {} }
  self.view = { land = {}, water = {} }
  self.hasLand, self.hasWater = false, false

  -- Battle Pike / Battle Pyramid: wild generation there is special-cased
  -- (facilityEncounter in encounter_rules/rse.lua) and this mod adds no
  -- visible spawns on those maps -- see docs/ARCHITECTURE.md "What v1
  -- deliberately leaves out".
  if EnginePatch.isSweetScentFacility(mapId) then
    self.skip = true
    return
  end
  -- The Safari Zone (Ruby / Sapphire / Emerald and FireRed / LeafGreen) gets visible
  -- spawns like anywhere else: touching one starts the engine's own Safari battle (balls
  -- and bait), since BattleBridge.startWild makes a plain wild battle a Safari one while a
  -- visit runs (battle_bridge.lua safari_mode_active).
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
      elseif terrain == "water" and self.hasWater and EncounterSource.openWater(x, y) then
        self.cells.water[#self.cells.water + 1] = { x = x, y = y }
      end
    end
  end
  self:_rebuildView()
end

--- Re-filters the scanned cells into `self.view`, once per map load / reach change --
--- not per tick: the spawn refill reads it every tick, and copying a few thousand cells
--- each time was ~0.3 ms and ~18 MB of garbage a second on a big route. Land is limited
--- to the reachable area; water never is: water Pokemon fill every lake and sea for
--- atmosphere, Surf or not (a Battler swims out to them, a surfer can meet them).
function EncounterSource:_rebuildView()
  local reachable = self.reachable
  local view = {}
  for terrain, list in pairs(self.cells) do
    if terrain == "water" or not reachable then
      view[terrain] = list
    else
      local out = {}
      for i = 1, #list do
        local c = list[i]
        if Reachability.has(reachable, c.x, c.y) then out[#out + 1] = c end
      end
      view[terrain] = out
    end
  end
  self.view = view
end
--- How many cells of `terrain` are eligible right now (no copy).
function EncounterSource:eligibleCount(terrain)
  local list = self.view and self.view[terrain]
  return list and #list or 0
end

--- One eligible cell of `terrain` picked with `rng(1, n)` (default math.random), or
--- nil. The cell is shared: read it, never change it.
function EncounterSource:randomCell(terrain, rng)
  local list = self.view and self.view[terrain]
  local n = list and #list or 0
  if n == 0 then return nil end
  return list[(rng or math.random)(1, n)]
end

--- The current map's eligible cells for `terrain` ("land" | "water"), a
--- fresh array of {x, y} tables (copy-on-read, same contract as
--- Gen1Recomp's own ow.entities facade -- callers must not mutate it
--- across calls and expect the mutation to persist).
function EncounterSource:eligibleCells(terrain)
  local list = self.view and self.view[terrain]
  if not list then return {} end
  local out = {}
  for i = 1, #list do
    out[i] = { x = list[i].x, y = list[i].y }
  end
  return out
end

--- Whether a wild Pokemon of `terrain` may stay on (x, y): water always, land while it
--- is reachable.
function EncounterSource:canStay(x, y, terrain)
  if terrain == "water" or not self.reachable then return true end
  return Reachability.has(self.reachable, x, y)
end

--- Restricts the land cells to a reachable set (lib/reachability.lua build()), or
--- lifts the restriction with nil. Water is never restricted. Reachability is a view
--- over the cells loadMap found, so it can be swapped without rescanning the map.
function EncounterSource:setReachable(set)
  self.reachable = set
  self:_rebuildView()
end
function EncounterSource:isEligible()
  return not self.skip and (self.hasLand or self.hasWater)
end

return EncounterSource
