-- Rolls a Forager's find (by friendship, lib/forage_items.lua) and puts it in the bag.
--
-- The item pool is built lazily from the engine's item data the first time it
-- is needed (the data is only loaded once a game is running) and rebuilt after
-- a save is loaded -- a mod's registered items can differ between sessions.
local V = ...
local Config = V.require("config")
local EnginePatch = V.require("engine_patch")
local ForageItems = V.require("forage_items")

local ForageSource = {}
ForageSource.__index = ForageSource

function ForageSource.new(mod, opts)
  opts = opts or {}
  return setmetatable({ mod = mod, pool = nil, rng = opts.rng }, ForageSource)
end

function ForageSource:reset()
  self.pool = nil
end

--- The pool (built on first use).
function ForageSource:getPool()
  if not self.pool then
    self.pool = ForageItems.buildPool(EnginePatch.itemCatalog(self.mod), Config.FORAGE)
  end
  return self.pool
end

-- an entry the bag can take right now
local function fits(entry)
  return EnginePatch.bagCanAdd(entry.id, 1)
end

--- Rolls what a Pokemon with `friendship` will find, WITHOUT bagging it (the
--- Forager sets out only once it knows it will find something). Only items that
--- fit in the bag are considered. Returns { entry, name, tier }, or nil when
--- nothing at all can be found (empty pool, full bag).
function ForageSource:roll(friendship)
  local entry, tier = ForageItems.roll(self:getPool(), friendship, self.rng, fits, Config.FORAGE)
  if not entry then return nil end
  return { entry = entry, name = entry.name, tier = tier, friendship = friendship }
end

--- Puts a rolled find in the bag (at the end of the dig). If the bag filled up
--- while the Pokemon was out, one fresh roll that fits is tried instead. Returns
--- what was bagged ({ entry, name, tier }), or nil when nothing could be.
function ForageSource:commit(rolled)
  if type(rolled) ~= "table" or not rolled.entry then return nil end
  if EnginePatch.bagAdd(rolled.entry.id, 1) then return rolled end
  local again = self:roll(rolled.friendship)
  if again and EnginePatch.bagAdd(again.entry.id, 1) then return again end
  return nil
end

return ForageSource
