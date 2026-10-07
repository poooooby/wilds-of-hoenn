-- Rolls a Forager's find and puts it in the bag.
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

--- Rolls an item and bags it. Returns its display name, or nil when nothing
--- was found (empty pool, or the bag is full -- nothing is lost either way).
function ForageSource:pick()
  local entry = ForageItems.roll(self:getPool(), self.rng)
  if not entry then return nil end
  if EnginePatch.bagAdd(entry.id, 1) then return entry.name end
  return nil
end

return ForageSource
