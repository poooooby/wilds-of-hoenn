-- Run: lua tests/forage_items_unit_test.lua
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

local ForageItems = assert(loadfile("lib/forage_items.lua"))()
local CFG = { maxTmPrice = 3000, blocklist = { "Nugget" } }

local function item(name, pocket, price, t)
  local e = { id = name, name = name, pocket = pocket or "ITEMS", price = price, use = "none" }
  for k, v in pairs(t or {}) do e[k] = v end
  return e
end
local function w(e) return ForageItems.weightOf(e, CFG) end

-- ------- hard excludes
check(w(item("HM03", "TM_CASE", 0, { isHm = true, isTm = true })) == 0, "an HM is never found")
check(w(item("HM05", "TM_CASE", 0)) == 0, "...even one the engine did not flag (by its name)")
check(w(item("Bicycle", "KEY_ITEMS", 0)) == 0, "key items are never found")
check(w(item("Master Ball", "POKE_BALLS", 0)) == 0, "the Master Ball is never found")
check(w(item("MASTER BALL", "POKE_BALLS", 0)) == 0, "...whatever its capitalisation")
check(w(item("Rare Candy", "ITEMS", 4800, { use = "level" })) == 0, "Rare Candy is never found")
check(w(item("Nugget", "ITEMS", 5000)) == 0, "the config blocklist is honoured")
for _, use in ipairs({ "bike", "map", "coin_case", "powder_jar", "itemfinder", "vs_seeker" }) do
  check(w(item("Gadget", "ITEMS", 200, { use = use })) == 0, "key-style use '" .. use .. "' is never found")
end
local ok, why = ForageItems.allowed(item("HM01", "TM_CASE", 0, { isHm = true }), CFG)
check(ok == false and why == "hm", "allowed() says why")
check(ForageItems.allowed(nil, CFG) == false, "no entry is not allowed")

-- ------- TMs: only the cheap ones
check(w(item("TM04 Calm Mind", "TM_CASE", 2000, { isTm = true })) > 0, "a low-tier TM can be found")
check(w(item("TM26 Earthquake", "TM_CASE", 5500, { isTm = true })) == 0, "a high-level (expensive) TM cannot")
check(w(item("TM00 Unsold", "TM_CASE", 0, { isTm = true })) == 0, "a TM with no shop price cannot")

-- ------- the kinds of find
local potion = item("Potion", "ITEMS", 300, { use = "heal" })
local superPotion = item("Super Potion", "ITEMS", 700, { use = "heal" })
local fullRestore = item("Full Restore", "ITEMS", 3000, { use = "heal" })
check(w(potion) > w(superPotion) and w(superPotion) > w(fullRestore) and w(fullRestore) > 0,
  "healing items get rarer as they get dearer, but all can be found")
check(w(item("Antidote", "ITEMS", 100, { use = "status" })) > 0, "status items can be found")
check(w(item("Revive", "ITEMS", 1500, { use = "revive" })) > 0, "revives can be found")
check(w(item("Sacred Ash", "ITEMS", 0, { use = "revive" })) == 0, "unsold special healing is not found")
check(w(item("Fire Stone", "ITEMS", 2100, { use = "evo", isEvo = true })) > 0, "an evolution stone can be found")
check(w(item("Dawn Stone", "ITEMS", 0, { use = "evo", extra = true })) > 0,
  "an item another mod registered (National Dex Gen 3's evolution items) can be found even with no price")
check(w(item("POKé BALL", "POKE_BALLS", 200)) > w(item("GREAT BALL", "POKE_BALLS", 600)), "Poke Balls beat Great Balls")
check(w(item("GREAT BALL", "POKE_BALLS", 600)) > w(item("ULTRA BALL", "POKE_BALLS", 1200)), "...and Great beat Ultra")
check(w(item("Luxury Ball", "POKE_BALLS", 1000)) > 0, "other balls can be found")
check(w(item("Oran Berry", "BERRY_POUCH", 20)) > 0, "berries can be found")
check(w(item("Repel", "ITEMS", 350)) > 0, "common items can be found")
check(w(item("Escape Rope", "ITEMS", 550)) > 0, "...by price")
check(w(item("Heart Scale", "ITEMS", 0)) == 0, "an item with no price and no other claim is not found")
check(w(item("Expensive Thing", "ITEMS", 9800)) == 0, "very dear items are not found")
check(w(item("HP Up", "ITEMS", 9800, { use = "vitamin" })) == 0, "vitamins are not found")

-- ------- the pool
local catalog = {
  potion, superPotion,
  item("HM01", "TM_CASE", 0, { isHm = true }),
  item("Master Ball", "POKE_BALLS", 0),
  item("Dawn Stone", "ITEMS", 0, { use = "evo", extra = true }),
  potion, -- a duplicate id
}
local pool = ForageItems.buildPool(catalog, CFG)
eq(#pool.entries, 3, "the pool keeps the allowed items, once each")
eq(#pool.weights, 3, "...with a weight per entry")
local sum = 0
for _, x in ipairs(pool.weights) do sum = sum + x end
eq(pool.total, sum, "...and its total")
local names = {}
for _, e in ipairs(pool.entries) do names[e.name] = true end
check(names["Potion"] and names["Super Potion"] and names["Dawn Stone"], "the right items are in")
check(not names["HM01"] and not names["Master Ball"], "the wrong ones are out")

-- ------- tiers: 1 common .. 4 very rare
local T = function(e) return ForageItems.tier(e, CFG) end
eq(T(item("POK959 BALL", "POKE_BALLS", 200)), 1, "a Poke Ball is common")
eq(T(item("GREAT BALL", "POKE_BALLS", 600)), 2, "a Great Ball is uncommon")
eq(T(item("ULTRA BALL", "POKE_BALLS", 1200)), 3, "an Ultra Ball is rare")
eq(T(item("Potion", "ITEMS", 300, { use = "heal" })), 1, "a 300 heal is common")
eq(T(item("Super Potion", "ITEMS", 700, { use = "heal" })), 2, "a 700 heal is uncommon")
eq(T(item("Hyper Potion", "ITEMS", 1200, { use = "heal" })), 3, "a 1200 heal is rare")
eq(T(item("Max Revive", "ITEMS", 4000, { use = "revive" })), 4, "a 4000 revive is very rare")
eq(T(item("Oran Berry", "BERRY_POUCH", 20)), 1, "berries are common")
eq(T(item("TM04 Calm Mind", "TM_CASE", 2000, { isTm = true })), 2, "a cheap TM is uncommon")
eq(T(item("TM26 Earthquake", "TM_CASE", 3500, { isTm = true })), nil, "an expensive TM has no tier (never found)")
eq(T(item("Fire Stone", "ITEMS", 2100, { use = "evo", isEvo = true })), 3, "an evolution stone is rare")
eq(T(item("Peat Block", "ITEMS", 1000, { use = "evo", extra = true })), 3, "a National Dex Gen 3 item at 1000 is rare")
eq(T(item("Dusk Stone", "ITEMS", 2100, { use = "evo", extra = true })), 3, "...at 2100 too")
eq(T(item("Ice Stone", "ITEMS", 3000, { use = "evo", extra = true })), 4, "...and at 3000 it is very rare")
eq(T(item("Dawn Stone", "ITEMS", 0, { use = "evo", extra = true })), 3, "...one with no price is rare")
eq(T(item("Repel", "ITEMS", 350)), 1, "a cheap other item is common")
eq(T(item("Escape Rope", "ITEMS", 550)), 2, "...a mid one uncommon")
eq(T(item("Nugget2", "ITEMS", 4000)), 3, "...a dear one rare")
eq(T(item("HM01", "TM_CASE", 0, { isHm = true })), nil, "an HM has no tier")

-- ------- friendship bands and gates
local MonMood = assert(loadfile("lib/mon_mood.lua"))({ require = function() return {} end })
local cfgBands = { 0, 30, 70, 130, 200, 255 }
for i, row in ipairs(MonMood.FRIENDSHIP_TIERS) do
  eq(cfgBands[i], row[1], "the forage bands are MonMood's friendship tiers (" .. row[2] .. ")")
end
local function tw(f) return ForageItems.tierWeights(f) end
eq(tw(129)[3], 0, "rare finds are gated below 130")
check(tw(130)[3] > 0, "...and open at 130")
eq(tw(199)[4], 0, "very rare finds are gated below 200")
check(tw(200)[4] > 0, "...and open at 200")
eq(tw(0)[3] + tw(0)[4], 0, "a friendship-0 Pokemon finds nothing rare")
check(tw(255)[3] > tw(200)[3] and tw(200)[3] > tw(130)[3], "rare finds grow with friendship above the gate")
check(tw(255)[4] > tw(200)[4], "...very rare too")
check(tw(255)[1] < tw(0)[1], "common finds fade as friendship grows")
eq(ForageItems.band(-5), 1, "friendship below 0 is the first band")
eq(ForageItems.band(300), 6, "...above 255 the last")
eq(ForageItems.band(nil), 1, "...and none at all is 0")
eq(ForageItems.band(29), 1, "29 is band 1") eq(ForageItems.band(30), 2, "30 band 2")
eq(ForageItems.band(69), 2, "69 band 2") eq(ForageItems.band(70), 3, "70 band 3")
eq(ForageItems.band(254), 5, "254 band 5") eq(ForageItems.band(255), 6, "255 band 6")

-- ------- the pool by tier
local evoTop = item("Ice Stone", "ITEMS", 3000, { use = "evo", extra = true })
local big = {
  item("POK959 BALL", "POKE_BALLS", 200), potion, item("Oran Berry", "BERRY_POUCH", 20),
  superPotion, item("GREAT BALL", "POKE_BALLS", 600),
  item("ULTRA BALL", "POKE_BALLS", 1200), item("Dawn Stone", "ITEMS", 2100, { use = "evo", extra = true }),
  evoTop, item("Max Revive", "ITEMS", 4000, { use = "revive" }),
}
local tpool = ForageItems.buildPool(big, CFG)
eq(#tpool.tiers[1].entries, 3, "three common finds")
eq(#tpool.tiers[2].entries, 2, "two uncommon")
eq(#tpool.tiers[3].entries, 2, "two rare (Ultra Ball, an NDex item)")
eq(#tpool.tiers[4].entries, 2, "two very rare (the 3000 NDex item, Max Revive)")

-- ------- rolling: the tier mix follows friendship, whatever the pool holds
local function lcg(seed)
  local x = seed
  return function() x = (x * 1103515245 + 12345) % 2147483648 return x / 2147483648 end
end
local function mix(friendship, n)
  local rng, c = lcg(7), { 0, 0, 0, 0 }
  for _ = 1, n do
    local _, t = ForageItems.roll(tpool, friendship, rng, nil, CFG)
    c[t] = c[t] + 1
  end
  for t = 1, 4 do c[t] = c[t] / n end
  return c
end
local function expect(f)
  local wts, sum = ForageItems.tierWeights(f), 0
  for t = 1, 4 do sum = sum + wts[t] end
  return { wts[1] / sum, wts[2] / sum, wts[3] / sum, wts[4] / sum }
end
for _, f in ipairs({ 0, 130, 255 }) do
  local got, want = mix(f, 20000), expect(f)
  local close = true
  for t = 1, 4 do if math.abs(got[t] - want[t]) > 0.015 then close = false end end
  check(close, string.format("friendship %d: tiers %.2f/%.2f/%.2f/%.2f vs %.2f/%.2f/%.2f/%.2f", f,
    got[1], got[2], got[3], got[4], want[1], want[2], want[3], want[4]))
end
local zero = mix(0, 4000)
eq(zero[3] + zero[4], 0, "friendship 0 never rolls a rare find")
local at129 = mix(129, 4000)
eq(at129[3], 0, "friendship 129 never rolls a rare find")
local at199 = mix(199, 4000)
eq(at199[4], 0, "friendship 199 never rolls a very rare find")
check(mix(255, 4000)[4] > 0, "friendship 255 does")

-- ------- the accept filter (the bag): a tier left empty shares its odds
local onlyRare = function(e) return e.name == "Dawn Stone" end
local e, t = ForageItems.roll(tpool, 255, lcg(3), onlyRare, CFG)
check(e and e.name == "Dawn Stone" and t == 3, "when only one item fits, that one is found")
eq(ForageItems.roll(tpool, 255, lcg(3), function() return false end, CFG), nil, "nothing fits: nothing is rolled")
eq(ForageItems.roll(tpool, 0, lcg(3), onlyRare, CFG), nil, "the only fitting item is gated: nothing is rolled")
eq(ForageItems.roll({ entries = {}, weights = {}, total = 0 }, 255, lcg(1)), nil, "an old-style pool with no tiers finds nothing")
eq(ForageItems.roll(nil, 255, lcg(1)), nil, "no pool finds nothing")
eq(ForageItems.roll(ForageItems.buildPool(nil, CFG), 255, lcg(1)), nil, "an empty pool finds nothing")
local heavy = ForageItems.buildPool({ potion, superPotion }, CFG)
local seen = {}
local r = lcg(11)
for _ = 1, 2000 do
  local x = ForageItems.roll(heavy, 0, r, nil, CFG)
  seen[x.name] = (seen[x.name] or 0) + 1
end
check(seen["Potion"] > 0 and seen["Super Potion"] > 0, "both tiers come up")

if failures > 0 then
  io.stderr:write(failures .. " failure(s)\n")
  os.exit(1)
end
print("forage_items_unit_test: all passed")
