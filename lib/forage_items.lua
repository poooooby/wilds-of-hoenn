-- What a Forager can find.
--
-- A find is rolled in two steps: first a TIER (1 common .. 4 very rare) by the
-- Pokemon's friendship -- the rare tiers are gated (tier 3 needs 130, tier 4 200)
-- and grow with friendship above their gate -- then an item inside that tier by
-- its own weight. Rolling the tier first keeps the odds the same however many
-- items are installed (National Dex Gen 3's extra items do not shift them).
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

--- The rarity tier of an allowed entry: 1 common, 2 uncommon, 3 rare, 4 very rare
--- (nil when it can never be found). From the same pocket / price / use data as
--- weightOf, so it works for any item, including the ones a mod registered.
function ForageItems.tier(entry, cfg)
  if ForageItems.weightOf(entry, cfg) <= 0 then return nil end
  cfg = cfg or {}
  local name = upper(entry.name)
  local price = tonumber(entry.price) or 0
  local use = entry.use or "none"
  if entry.extra or entry.isEvo or use == "evo" then
    return price >= (cfg.evoTop or 3000) and 4 or 3
  end
  if entry.isTm or entry.pocket == "TM_CASE" then return 2 end
  if entry.pocket == "POKE_BALLS" then
    if name == "POKE BALL" then return 1 end
    if name == "GREAT BALL" then return 2 end
    if name == "ULTRA BALL" then return 3 end
    if price <= 500 then return 1 end
    return price <= 2000 and 2 or 3
  end
  if entry.pocket == "BERRY_POUCH" then return 1 end
  if use == "heal" or use == "status" or use == "revive" then
    if price <= 300 then return 1 end
    if price <= 800 then return 2 end
    if price <= 1500 then return 3 end
    return 4
  end
  if price <= 500 then return 1 end
  if price <= 2000 then return 2 end
  return 3
end

--- Weighted pool: { entries, weights, total } (every find) plus
--- `tiers[1..4] = { entries, weights, total }`.
function ForageItems.buildPool(catalog, cfg)
  local pool = { entries = {}, weights = {}, total = 0, tiers = {} }
  for t = 1, 4 do pool.tiers[t] = { entries = {}, weights = {}, total = 0 } end
  local seen = {}
  for _, entry in ipairs(catalog or {}) do
    local key = tostring(entry.id)
    if not seen[key] then
      local w = ForageItems.weightOf(entry, cfg)
      local t = w > 0 and ForageItems.tier(entry, cfg) or nil
      if t then
        seen[key] = true
        pool.entries[#pool.entries + 1] = entry
        pool.weights[#pool.weights + 1] = w
        pool.total = pool.total + w
        local bucket = pool.tiers[t]
        bucket.entries[#bucket.entries + 1] = entry
        bucket.weights[#bucket.weights + 1] = w
        bucket.total = bucket.total + w
      end
    end
  end
  return pool
end

local DEFAULT_TIERS = {
  bands = { 0, 30, 70, 130, 200, 255 },
  tierBase = { 100, 35, 12, 3 },
  tierGate = { 0, 0, 130, 200 },
  tierMult = {
    { 1.00, 1.00, 0, 0 }, { 0.95, 1.10, 0, 0 }, { 0.90, 1.25, 0, 0 },
    { 0.80, 1.35, 1.0, 0 }, { 0.70, 1.40, 1.6, 1.0 }, { 0.60, 1.40, 2.6, 2.5 },
  },
}

--- The friendship band (1-based) for 0-255 friendship.
function ForageItems.band(friendship, cfg)
  local bands = (cfg and cfg.bands) or DEFAULT_TIERS.bands
  local f = math.max(0, math.min(255, tonumber(friendship) or 0))
  local band = 1
  for i, lo in ipairs(bands) do
    if f >= lo then band = i end
  end
  return band
end

--- The weight of each tier { w1, w2, w3, w4 } at this friendship: base x the
--- band's multiplier, 0 below the tier's gate.
function ForageItems.tierWeights(friendship, cfg)
  cfg = cfg or {}
  local base = cfg.tierBase or DEFAULT_TIERS.tierBase
  local gate = cfg.tierGate or DEFAULT_TIERS.tierGate
  local mult = (cfg.tierMult or DEFAULT_TIERS.tierMult)[ForageItems.band(friendship, cfg)]
  local f = math.max(0, math.min(255, tonumber(friendship) or 0))
  local out = {}
  for t = 1, 4 do
    out[t] = (f >= (gate[t] or 0)) and (base[t] or 0) * ((mult and mult[t]) or 0) or 0
  end
  return out
end

local function pick(entries, weights, total, r)
  local acc = 0
  for i, w in ipairs(weights) do
    acc = acc + w
    if r < acc then return entries[i] end
  end
  return entries[#entries]
end

--- Rolls a find for a Pokemon with `friendship`: a tier first, then an item in
--- it. `accept(entry)` (optional, e.g. "fits in the bag") rules entries out for
--- this roll; a tier left empty is dropped and the others share its odds. Returns
--- `entry, tier`, or nil when nothing at all can be found. `rng()` returns [0,1).
function ForageItems.roll(pool, friendship, rng, accept, cfg)
  if not pool or not pool.tiers then return nil end
  rng = rng or math.random
  local tw = ForageItems.tierWeights(friendship, cfg)
  -- per tier, the entries this roll may use
  local usable, total = {}, 0
  for t = 1, 4 do
    local bucket = pool.tiers[t]
    local entries, weights, sum = {}, {}, 0
    if tw[t] > 0 and bucket then
      for i, e in ipairs(bucket.entries) do
        if not accept or accept(e) then
          entries[#entries + 1] = e
          weights[#weights + 1] = bucket.weights[i]
          sum = sum + bucket.weights[i]
        end
      end
    end
    if sum > 0 then
      usable[t] = { entries = entries, weights = weights, total = sum }
      total = total + tw[t]
    end
  end
  if total <= 0 then return nil end
  local r, acc, tier = rng() * total, 0, nil
  for t = 1, 4 do
    if usable[t] then
      acc = acc + tw[t]
      if r < acc then tier = t break end
      tier = t
    end
  end
  local u = usable[tier]
  return pick(u.entries, u.weights, u.total, rng() * u.total), tier
end

return ForageItems
