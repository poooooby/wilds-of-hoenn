-- National Dex Gen 3's items reach the Forager: loads national_dex_gen3 AND
-- wilds_of_hoenn through gen1recomp's REAL mod Loader (tests/modkit, like
-- modkit_boot_test.lua) and checks what the Forager can actually find.
--
-- Run from inside a gen1recomp checkout with both mods linked under mods/:
--   cd ../gen1recomp
--   luajit mods/wilds_of_hoenn/tests/forage_ndex_catalog_test.lua
--
-- ROM-free: the game's own items (Potion, Poke Ball ...) come from the imported
-- ROM's item pack, which this harness does not mount, so the pool here holds
-- just the items a mod registered -- exactly the part under test. For the same
-- reason the real Bag cannot be exercised offline (it needs that pack for every
-- item); bagging a National Dex Gen 3 find is on docs/MANUAL_TEST.md.
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

love = love or require("tests.love_stub")
local GameVersion = require("src.core.GameVersion")
local T = require("tests.modkit")

local function exists(path)
  local f = io.open(path, "rb")
  if f then f:close() return true end
  return false
end
if not exists("mods/national_dex_gen3/manifest.json") then
  print("skip: mods/national_dex_gen3 is not linked into this checkout")
  print("forage_ndex_catalog_test: skipped")
  return
end

for _, game in ipairs({ "emerald", "firered" }) do
  GameVersion.set(game)
  local r = T.sdk.loadMods({ "mods/national_dex_gen3", "mods/wilds_of_hoenn" },
    { data = T.fixtures.fresh(), generation = 3 })
  eq(#r.errors, 0, game .. ": both mods load with no Loader errors")
  eq(r.loader.mods.national_dex_gen3 and r.loader.mods.national_dex_gen3.state, "loaded", game .. ": national_dex_gen3 loaded")
  local ex = r.loader.exports and r.loader.exports.wilds_of_hoenn
  check(ex and ex.forageSource, game .. ": the Forager's item source is exported")

  local pool = ex.forageSource:getPool()
  local byId, extras = {}, 0
  for t = 1, 4 do
    for _, e in ipairs(pool.tiers[t].entries) do
      byId[tostring(e.id)] = t
      if e.extra then extras = extras + 1 end
    end
  end
  check(extras >= 30, game .. ": the Forager can find National Dex Gen 3's items (" .. extras .. " of them)")
  eq(byId.DUSK_STONE, 3, game .. ": Dusk Stone (2100) is a rare find")
  eq(byId.PEAT_BLOCK, 3, game .. ": Peat Block (1000) too")
  eq(byId.ICE_STONE, 4, game .. ": Ice Stone (3000) is very rare")
  eq(byId.METAL_ALLOY, 4, game .. ": ...and so is Metal Alloy")

  -- friendship gates them: never below 130, and the very rare ones never below 200
  local ForageItems = assert(loadfile("mods/wilds_of_hoenn/lib/forage_items.lua"))()
  local any = function() return true end
  eq(ForageItems.roll(pool, 129, function() return 0.5 end, any), nil, game .. ": below friendship 130 none of them can be found")
  local e, tier = ForageItems.roll(pool, 130, function() return 0.5 end, any)
  check(e and tier == 3, game .. ": at 130 a rare one can")
  local sawTop = false
  local x = 0
  local rng = function() x = (x * 37 + 11) % 97 return x / 97 end
  for _ = 1, 400 do
    local _, t = ForageItems.roll(pool, 199, rng, any)
    if t == 4 then sawTop = true end
  end
  check(not sawTop, game .. ": below 200 a very rare one never comes up")
  for _ = 1, 400 do
    local _, t = ForageItems.roll(pool, 255, rng, any)
    if t == 4 then sawTop = true end
  end
  check(sawTop, game .. ": at 255 it does")
  r.release()
end

print("")
if failures > 0 then
  io.stderr:write(failures .. " failure(s)\n")
  os.exit(1)
end
print("forage_ndex_catalog_test: all passed")
