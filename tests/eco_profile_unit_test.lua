-- Run: lua tests/eco_profile_unit_test.lua
package.path = "./?.lua;./?/init.lua;" .. package.path

local failures = 0
local function check(cond, msg)
  if not cond then
    failures = failures + 1
    io.stderr:write("FAIL: " .. tostring(msg) .. "\n")
  else
    print("ok  " .. tostring(msg))
  end
end
local function eq(a, b, msg)
  check(a == b, string.format("%s (got %s expected %s)", msg, tostring(a), tostring(b)))
end

-- a fake engine: internal species id = national dex + 1000
local DATA = {
  [129] = { types = { 11, 0 }, egg = { 12, 14 }, height = 9, bst = 200 },    -- Magikarp
  [261] = { types = { 17, 0 }, egg = { 5 }, height = 5, bst = 220 },         -- Poochyena
  [320] = { types = { 11, 0 }, egg = { 5, 2 }, height = 20, bst = 400 },     -- Wailmer
  [150] = { types = { 14, 0 }, egg = { 15 }, height = 20, bst = 680 },       -- Mewtwo
  [999] = { types = { 17, 10 }, egg = { 5 }, height = 9, bst = 480 },        -- a made-up Dark / Fire hunter
  [998] = { types = { 0, 0 }, egg = { 6 }, height = 3, bst = 250 },          -- a made-up small Normal
  [997] = { types = { 7, 0 }, egg = { 12 }, height = 16, bst = 470 },        -- a made-up big Water 2 fish
  [996] = { types = { 7, 0 }, egg = { 11 }, height = 12, bst = 420 },        -- a made-up Ghost
}
local TYPE = { [0] = "NORMAL", [7] = "GHOST", [10] = "FIRE", [11] = "WATER", [14] = "PSYCHIC", [17] = "DARK" }
local reads = 0
local E = {
  nationalFor = function(s) return s - 1000 end,
  speciesTypes = function(s) reads = reads + 1 local d = DATA[s - 1000] return d.types[1], d.types[2] end,
  typeName = function(t) return TYPE[t] or "NORMAL" end,
  eggGroups = function(s) local d = DATA[s - 1000] return d.egg[1], d.egg[2] end,
  heightDm = function(s) return DATA[s - 1000].height end,
  baseStatTotal = function(s) return DATA[s - 1000].bst end,
  isFlying = function() return false end,
}
local V = {}
local modules = { engine_patch = E }
function V.require(name)
  if modules[name] == nil then modules[name] = assert(loadfile("lib/" .. name .. ".lua"))(V) end
  return modules[name]
end
local EcoProfile = V.require("eco_profile")
local Species = V.require("eco_species")

-- ------- derived rules
do
  local wl = { whales = { [320] = true }, notFish = {}, fishExtra = {} }
  local fish = EcoProfile.derive(500, { types = { "WATER" }, egg = { 12 }, height = 6, bst = 250 }, wl)
  eq(fish.water, "leaper", "a short Water 2 fish leaps")
  eq(fish.social, "school", "...in a school")
  eq(fish.group[1], 2, "...of at least two")
  local big = EcoProfile.derive(500, { types = { "WATER" }, egg = { 12 }, height = 16, bst = 470 }, wl)
  eq(big.water, "diver", "a big Water 2 fish dives instead")
  eq(big.social, "solo", "...alone")
  eq(EcoProfile.derive(320, { egg = { 5, 2 }, height = 20 }, wl).water, "whale", "a listed whale is a whale")
  local nf = EcoProfile.derive(116, { egg = { 12 }, height = 4 }, { notFish = { [116] = true } })
  eq(nf.water, "swimmer", "a notFish Water 2 Pokemon just swims")
  local hunter = EcoProfile.derive(500, { types = { "DARK", "FIRE" }, egg = { 5 }, height = 9, bst = 480 })
  eq(hunter.diet, "predator", "a Dark Pokemon of some size hunts")
  eq(hunter.temper, "territorial", "...and holds its ground")
  eq(hunter.activity, "night", "...at night")
  eq(EcoProfile.derive(500, { types = { "BUG", "FLYING" }, egg = { 3 }, height = 3, bst = 250 }).activity, "day",
    "a bug / bird is out by day (asleep at night)")
  eq(EcoProfile.derive(500, { types = { "GHOST", "FLYING" }, egg = { 11 }, height = 3, bst = 250 }).activity, "night",
    "...but a Ghost bird by night")
  eq(EcoProfile.derive(500, { types = { "NORMAL" }, egg = { 5 }, height = 3, bst = 250 }).activity, "any",
    "anything else whenever")
  local small = EcoProfile.derive(500, { types = { "NORMAL" }, egg = { 6 }, height = 3, bst = 250 })
  eq(small.diet, "prey", "a small weak Pokemon is prey")
  eq(small.temper, "skittish", "...and skittish")
  local legend = EcoProfile.derive(150, { types = { "PSYCHIC" }, egg = { 15 }, height = 20, bst = 680 })
  check(legend.social == "solo" and legend.temper == "calm" and legend.diet == "neutral",
    "an Undiscovered-egg Pokemon (legendary / baby) keeps to itself, calm")
  eq(EcoProfile.derive(500, {}).social, "solo", "nothing known: solo")
end

-- ------- the table overrides, field by field
do
  local m = EcoProfile.merge({ social = "solo", group = { 1, 1 }, diet = "prey", temper = "skittish",
    water = "swimmer", activity = "any" }, { social = "pack", group = { 2, 3 }, diet = "predator" })
  eq(m.social, "pack", "the table's social wins")
  eq(m.diet, "predator", "...and its diet")
  eq(m.temper, "skittish", "...fields it leaves out stay derived")
  eq(m.source, "table", "...marked as from the table")
  local solo = EcoProfile.merge({ social = "school", group = { 2, 3 } }, { social = "solo" })
  eq(solo.group[2], 1, "a table solo is a group of one")
end

-- ------- through the engine, cached
do
  EcoProfile.reset()
  local karp = EcoProfile.of(1129)
  eq(karp.social, "school", "Magikarp: a school (table)")
  eq(karp.water, "leaper", "...of leapers")
  eq(karp.dex, 129, "...by national dex")
  local pooch = EcoProfile.of(1261)
  eq(pooch.social, "pack", "Poochyena: a pack")
  eq(pooch.diet, "predator", "...hunting")
  check(EcoProfile.of(1150).social == "solo", "Mewtwo: solo")
  eq(EcoProfile.of(1996).activity, "night", "a Ghost is out at night (derived)")
  local before = reads
  EcoProfile.of(1129)
  eq(reads, before, "a second look is cached")
  local bad = EcoProfile.of("nonsense")
  eq(bad.social, "solo", "an unreadable species: the plain solo profile, never an error")
end

-- ------- every table entry is well formed
do
  local SOCIAL = { solo = 1, pack = 1, herd = 1, school = 1, swarm = 1, pod = 1, huddle = 1 }
  local DIET = { predator = 1, prey = 1, neutral = 1 }
  local TEMPER = { skittish = 1, calm = 1, territorial = 1, aggressive = 1, placid = 1 }
  local WATER = { leaper = 1, diver = 1, whale = 1, drifter = 1, swimmer = 1 }
  local ACT = { day = 1, night = 1, any = 1 }
  local bad, n = {}, 0
  for dex, e in pairs(Species) do
    n = n + 1
    local okEntry = type(dex) == "number"
      and (e.social == nil or SOCIAL[e.social]) and (e.diet == nil or DIET[e.diet])
      and (e.temper == nil or TEMPER[e.temper]) and (e.water == nil or WATER[e.water])
      and (e.activity == nil or ACT[e.activity])
      and (e.burrower == nil or e.burrower == true)
      and (e.catch == nil or (type(e.catch) == "number" and e.catch >= 1 and e.catch <= 1025))
      and (e.schoolForm == nil or (type(e.schoolForm) == "string" and e.schoolForm:match("^%d%d%d%-%l")))
      and (e.group == nil or (type(e.group) == "table" and e.group[1] >= 1 and e.group[2] >= e.group[1] and e.group[2] <= 4))
      and (e.social == nil or e.social == "solo" or e.group ~= nil)
    if not okEntry then bad[#bad + 1] = tostring(dex) end
    for other in pairs(e.rival or {}) do
      if not (Species[other] and Species[other].rival and Species[other].rival[dex]) then
        bad[#bad + 1] = dex .. " rival " .. other .. " not mutual"
      end
    end
  end
  check(n >= 150, "the table covers the Hoenn species (" .. n .. " entries)")
  check(#bad == 0, "every entry is well formed" .. (#bad > 0 and (": " .. table.concat(bad, ", ")) or ""))
end

if failures > 0 then
  io.stderr:write(failures .. " failure(s)\n")
  os.exit(1)
end
print("eco_profile_unit_test: all passed")
