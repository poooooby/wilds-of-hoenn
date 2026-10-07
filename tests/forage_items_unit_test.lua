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

-- ------- rolling
local seen = {}
for i = 0, 99 do
  local e = ForageItems.roll(pool, function() return i / 100 end)
  seen[e.name] = (seen[e.name] or 0) + 1
end
check(seen["Potion"] > seen["Super Potion"], "a heavier item is rolled more often")
check(seen["Dawn Stone"] > 0, "a rare one still turns up")
eq(ForageItems.roll(pool, function() return 0 end).name, "Potion", "a roll of 0 picks the first entry")
eq(ForageItems.roll(pool, function() return 0.999999 end).name, "Dawn Stone", "a roll near 1 picks the last")
eq(ForageItems.roll({ entries = {}, weights = {}, total = 0 }, nil), nil, "an empty pool finds nothing")
eq(ForageItems.roll(nil, nil), nil, "no pool finds nothing")
eq(ForageItems.buildPool(nil, CFG).total, 0, "no catalog is an empty pool")

if failures > 0 then
  io.stderr:write(failures .. " failure(s)\n")
  os.exit(1)
end
print("forage_items_unit_test: all passed")
