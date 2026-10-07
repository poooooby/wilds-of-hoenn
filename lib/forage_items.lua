-- What a Forager can find.
--
-- Pure: it is handed a catalog of item entries (lib/engine_patch.lua builds it
-- from the engine's own item data plus every item another mod registered, e.g.
-- the evolution items National Dex Gen 3 adds) and turns it into a weighted
-- pool. Nothing here knows an item NUMBER -- ids differ between Ruby/Sapphire/
-- Emerald and FireRed/LeafGreen -- so it works from the entry's pocket, name,
-- price and use kind instead.
--
-- entry = {
--   id        what Bag.add takes
--   name      display name ("Potion")
--   pocket    "ITEMS" | "POKE_BALLS" | "TM_CASE" | "BERRY_POUCH" | "KEY_ITEMS"
--   price     buy price (0 / nil = not a shop item)
--   use       engine field-use kind ("heal", "status", "revive", "evo", "tm", "level",
--             "vitamin", "bike", "map", ... or "none")
--   isHm, isTm, isEvo   booleans (isEvo: an evolution stone / evolution item)
--   extra     true for an item a mod registered (always an "evolution" style find)
-- }
local ForageItems = {}

-- Weights (higher = found more often). Everything is relative.
ForageItems.WEIGHTS = {
  ball = { ["POKE BALL"] = 10, ["GREAT BALL"] = 4, ["ULTRA BALL"] = 1, other = 2 },
  heal = { cheap = 10, mid = 5, dear = 2, rare = 1 }, -- by price, see healTier
  berry = 2,
  other = { cheap = 6, mid = 3, dear = 1 },
  evo = 5,
  tm = 2,
}

-- hard excludes, matched on the upper-cased display name
local NEVER_NAMES = {
  ["MASTER BALL"] = true,
  ["RARE CANDY"] = true,
}

-- "POKé BALL" -> "POKE BALL": the games spell it with an accent
local function upper(s)
  local t = tostring(s or ""):upper():gsub("\195\169", "E"):gsub("\195\137", "E")
  return t
end

--- Is this entry allowed at all? Returns false + a reason for the tests.
function ForageItems.allowed(entry, cfg)
  cfg = cfg or {}
  if type(entry) ~= "table" or entry.id == nil then return false, "no id" end
  local name = upper(entry.name)
  if entry.isHm or name:match("^HM%s*%d") then return false, "hm" end
  if entry.pocket == "KEY_ITEMS" then return false, "key item" end
  if NEVER_NAMES[name] then return false, "game breaking" end
  for _, blocked in ipairs(cfg.blocklist or {}) do
    if upper(blocked) == name then return false, "blocklisted" end
  end
  local use = entry.use or "none"
  if use == "bike" or use == "map" or use == "coin_case" or use == "powder_jar"
      or use == "itemfinder" or use == "vs_seeker" or use == "level" then
    return false, "key-style use"
  end
  if entry.isTm or entry.pocket == "TM_CASE" then
    local price = tonumber(entry.price) or 0
    if price <= 0 or price > (cfg.maxTmPrice or 3000) then return false, "high-level tm" end
    return true
  end
  return true
end

local function healTier(price)
  price = tonumber(price) or 0
  if price <= 300 then return "cheap" end
  if price <= 800 then return "mid" end
  if price <= 1500 then return "dear" end
  return "rare"
end

local function otherTier(price)
  price = tonumber(price) or 0
  if price <= 500 then return "cheap" end
  if price <= 2000 then return "mid" end
  return "dear"
end

--- The entry's weight (0 = never found).
function ForageItems.weightOf(entry, cfg)
  if not ForageItems.allowed(entry, cfg) then return 0 end
  local W = ForageItems.WEIGHTS
  local name = upper(entry.name)
  local price = tonumber(entry.price) or 0
  local use = entry.use or "none"

  if entry.extra or entry.isEvo or use == "evo" then return W.evo end
  if entry.isTm or entry.pocket == "TM_CASE" then return W.tm end
  if entry.pocket == "POKE_BALLS" then return W.ball[name] or W.ball.other end
  if entry.pocket == "BERRY_POUCH" then return W.berry end
  if use == "heal" or use == "status" or use == "revive" then
    if price <= 0 then return 0 end -- Sacred Ash and the like
    return W.heal[healTier(price)]
  end
  -- everything else in the item pocket: shop items by price; no price, no find
  if price <= 0 then return 0 end
  if price > 5000 then return 0 end
  if use == "vitamin" then return 0 end
  return W.other[otherTier(price)]
end

--- Weighted pool: { entries = {...}, weights = {...}, total = n }.
function ForageItems.buildPool(catalog, cfg)
  local pool = { entries = {}, weights = {}, total = 0 }
  local seen = {}
  for _, entry in ipairs(catalog or {}) do
    local key = tostring(entry.id)
    if not seen[key] then
      local w = ForageItems.weightOf(entry, cfg)
      if w > 0 then
        seen[key] = true
        pool.entries[#pool.entries + 1] = entry
        pool.weights[#pool.weights + 1] = w
        pool.total = pool.total + w
      end
    end
  end
  return pool
end

--- Picks one entry; `rng()` returns [0,1). nil on an empty pool.
function ForageItems.roll(pool, rng)
  if not pool or pool.total <= 0 or #pool.entries == 0 then return nil end
  local r = (rng and rng() or math.random()) * pool.total
  local acc = 0
  for i, w in ipairs(pool.weights) do
    acc = acc + w
    if r < acc then return pool.entries[i] end
  end
  return pool.entries[#pool.entries]
end

return ForageItems
