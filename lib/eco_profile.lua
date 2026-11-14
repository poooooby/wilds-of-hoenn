-- How a species lives in the wild (lib/eco.lua acts it out): who it goes about with, what it
-- hunts, how it takes to the player, how it uses the water and when it is out.
--
-- A hand-written table (lib/eco_species.lua, by NATIONAL dex number) for the species that
-- matter, and for every other one -- National Dex additions included -- a profile derived from
-- what the game says about it: its types, egg groups, height and base stat total. The table
-- entry's fields win over the derived ones, so an entry only lists what it changes.
--
-- Profile:
--   social   "solo" | "pack" | "herd" | "school" | "swarm" | "pod" | "huddle"
--   group    { min, max } members, the Pokemon itself included ({1, 1} when solo)
--   diet     "predator" | "prey" | "neutral"
--   prey     type names a predator hunts (nil = any smaller, weaker Pokemon)
--   rival    { [dex] = true } species it fights on sight
--   temper   "skittish" | "calm" | "territorial" | "aggressive" | "placid" (never reacts to the
--            player; calm = Wild Reacts' plain rules: lib/wild_reactions.lua reach / decide)
--   water    "leaper" | "diver" | "whale" | "drifter" | "swimmer" (how a water spawn swims)
--   activity "day" | "night" | "any" (asleep the other half: lib/eco_sleep.lua)
--   burrower true: digs down and comes up elsewhere (lib/eco_burrow.lua; table only)
--   glow     { color = {r, g, b}, at = "top" | "body" | "tail", trail = true }: its light at night
--            (lib/eco_glow.lua; table only)
--   mimic    "tree": it stands stock-still passing for one until the player comes close, then
--            bolts (lib/eco_land.lua "mimic"; table only)
--   catch    national dex: a fishing bird comes up with one in its beak (lib/eco_air.lua; table only)
--   schoolForm  an art key ("746-school"): the school gathers into that big form under the water
--               now and then (lib/eco_water.lua "school"; table only)
--   source   "table" | "derived"
local V = ...

local EcoProfile = {}

-- Gen 3 egg groups (pokemon.lua speciesMeta eggGroup1 / 2)
EcoProfile.EGG = { MONSTER = 1, WATER1 = 2, BUG = 3, FLYING = 4, FIELD = 5, FAIRY = 6, GRASS = 7,
  HUMANLIKE = 8, WATER3 = 9, MINERAL = 10, AMORPHOUS = 11, WATER2 = 12, DITTO = 13, DRAGON = 14,
  UNDISCOVERED = 15 }
local EGG = EcoProfile.EGG

-- the derived rules' thresholds (heights in decimetres, as the Pokedex keeps them)
EcoProfile.RULES = {
  fishMaxHeight = 10,     -- a Water 2 Pokemon this short is a leaping fish, in a school
  schoolGroup = { 2, 3 },
  preyMaxBst = 330,       -- small and weak: something else's prey ...
  preyMaxHeight = 6,
  predatorMinBst = 300,   -- ... a hunter needs some size and strength
  predatorMinHeight = 4,
  skittishMaxBst = 300,
  territorialMinBst = 500,
}

local function has(list, v)
  for _, x in ipairs(list or {}) do if x == v then return true end end
  return false
end

--- The profile worked out from `facts` alone: { types = {"WATER", ...}, egg = {g1, g2},
--- height = dm, bst = n, flying = bool }, any of them possibly missing. `waterCfg` =
--- Config.WATER_LIFE (whales / notFish / fishExtra by national dex). Pure.
function EcoProfile.derive(dex, facts, waterCfg)
  facts = facts or {}
  local R = EcoProfile.RULES
  local types, egg = facts.types or {}, facts.egg or {}
  local height, bst = tonumber(facts.height), tonumber(facts.bst)
  local p = { social = "solo", group = { 1, 1 }, diet = "neutral", temper = "calm",
              water = "swimmer", activity = "any", source = "derived" }
  waterCfg = waterCfg or {}
  local whales, notFish, fishExtra = waterCfg.whales or {}, waterCfg.notFish or {}, waterCfg.fishExtra or {}

  -- legendaries, mythicals and babies (no eggs): alone, unbothered
  if has(egg, EGG.UNDISCOVERED) then return p end

  -- the water: whales, fish, the rest swimming
  if whales[dex] then
    p.water = "whale"
  elseif (has(egg, EGG.WATER2) or fishExtra[dex]) and not notFish[dex] then
    if height and height < R.fishMaxHeight then
      p.water, p.social, p.group = "leaper", "school", { R.schoolGroup[1], R.schoolGroup[2] }
    else
      p.water = "diver"
    end
  end

  -- who eats whom
  local dark = has(types, "DARK")
  local fieldHunter = has(egg, EGG.FIELD) and (has(types, "FIRE") or has(types, "ELECTRIC"))
  if (dark or fieldHunter) and (bst or 0) >= R.predatorMinBst and (height or 0) >= R.predatorMinHeight then
    p.diet, p.temper = "predator", "territorial"
  elseif bst and bst <= R.preyMaxBst and height and height <= R.preyMaxHeight then
    p.diet = "prey"
  end

  if p.temper ~= "territorial" then
    if bst and bst <= R.skittishMaxBst then
      p.temper = "skittish"
    elseif bst and bst >= R.territorialMinBst then
      p.temper = "territorial"
    end
  end

  -- Ghost and Dark are out at night; birds, bugs and plants by day (asleep at night)
  if has(types, "GHOST") or dark then
    p.activity = "night"
  elseif has(types, "FLYING") or has(types, "BUG") or has(types, "GRASS") then
    p.activity = "day"
  end
  return p
end

--- The derived profile with the hand table's entry laid over it. Pure.
function EcoProfile.merge(derived, entry)
  if not entry then return derived end
  local p = {}
  for k, v in pairs(derived) do p[k] = v end
  for k, v in pairs(entry) do p[k] = v end
  if p.social == "solo" then p.group = { 1, 1 } end
  if not p.group then p.group = { 2, 3 } end
  p.source = "table"
  return p
end

-- ------- the live game: facts read through the engine, cached per species

local cache = {}

--- Forget the cached profiles (a new boot, another game's species list).
function EcoProfile.reset() cache = {} end

local function factsFor(EnginePatch, species)
  local f = {}
  if EnginePatch.speciesTypes then
    local t1, t2 = EnginePatch.speciesTypes(species)
    local name = EnginePatch.typeName
    f.types = {}
    -- (type 0 is NORMAL, not "none": a pure Normal-type reads 0, 0)
    if name then
      f.types[1] = name(t1 or 0)
      if t2 and t2 ~= t1 then f.types[2] = name(t2) end
    end
  end
  if EnginePatch.eggGroups then
    local g1, g2 = EnginePatch.eggGroups(species)
    f.egg = { g1, g2 }
  end
  f.height = EnginePatch.heightDm and EnginePatch.heightDm(species) or nil
  f.bst = EnginePatch.baseStatTotal and EnginePatch.baseStatTotal(species) or nil
  f.flying = EnginePatch.isFlying and EnginePatch.isFlying(species) or false
  return f
end

--- The profile of engine species `species` (an internal id, or a string key on the GB
--- engines), cached. Never throws: anything unreadable gives the plain solo profile.
function EcoProfile.of(species)
  local key = species
  local hit = cache[key]
  if hit then return hit end
  local EnginePatch = V and V.require("engine_patch")
  local Config = V and V.require("config")
  local table_ = V and V.require("eco_species") or {}
  local p
  local ok = pcall(function()
    local dex = EnginePatch and EnginePatch.nationalFor and EnginePatch.nationalFor(species) or tonumber(species)
    p = EcoProfile.merge(EcoProfile.derive(dex, factsFor(EnginePatch, species), Config and Config.WATER_LIFE),
      dex and table_[dex])
    p.dex = dex
  end)
  if not ok or not p then p = EcoProfile.derive(nil, {}) end
  cache[key] = p
  return p
end

return EcoProfile
