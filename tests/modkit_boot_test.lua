-- Boots wilds_of_hoenn through gen1recomp's REAL mod-SDK harness
-- (tests/modkit): the real src.mods.Loader, real manifest validation, and
-- -- critically -- EnginePatch.install() patching the REAL
-- src.core.game3.* modules (no fakes anywhere in this file). This is the
-- one test in this repo that proves main.lua actually boots end to end
-- against gen1recomp, short of a real ROM session.
--
-- Run from inside a gen1recomp checkout with this mod linked at
-- mods/wilds_of_hoenn (scripts/bootstrap.sh does that symlink), with
-- luajit:
--   cd ../gen1recomp
--   luajit mods/wilds_of_hoenn/tests/modkit_boot_test.lua
--
-- The modkit fixture dataset (tests/modkit/fixtures.lua) is Gen 1-only,
-- so this forces `generation = 3` and a Gen 3 GameVersion explicitly
-- rather than relying on the fixture data's own (Gen 1) default. No real
-- Emerald ROM cache is mounted this way, so spawnManager legitimately
-- places zero wild Pokemon here (Encounters logs "no extract") -- that is
-- the correct, graceful outcome for THIS test, not a bug. Real spawn
-- placement is covered by the standalone spawn_manager_unit_test.lua
-- (fully faked engine) and ultimately by docs/MANUAL_TEST.md (a real ROM
-- session).
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
local Runtime = require("src.mods.Runtime")
local T = require("tests.modkit")

local function loadWildsOfHoenn(gameVersion)
  GameVersion.set(gameVersion)
  local data = T.fixtures.fresh()
  return T.sdk.loadMod("mods/wilds_of_hoenn", { data = data, generation = 3 })
end

-- ------- Emerald: loads clean, installs fully, survives real map events
local r = loadWildsOfHoenn("emerald")
eq(#r.errors, 0, "wilds_of_hoenn loads with no Loader errors on Emerald")
local m = r.loader.mods.wilds_of_hoenn
check(m ~= nil, "Loader discovered wilds_of_hoenn by manifest id")
eq(m and m.state, "loaded", "mod reached the loaded state (not wrong_generation)")

local exports = r.loader.exports and r.loader.exports.wilds_of_hoenn
check(exports ~= nil, "exports table published")
eq(exports and exports.engineReady, true, "engineReady true: EnginePatch.install succeeded for real")
check(exports and exports.spawnManager ~= nil, "spawnManager exported")
check(exports and exports.battleTrigger ~= nil, "battleTrigger exported")
check(exports and exports.followerAdapter ~= nil, "followerAdapter exported")

local okEnter, errEnter = pcall(Runtime.emit, "map.entered", { mapId = "ROUTE_101" })
check(okEnter, "a real map.entered through Runtime.emit does not throw (" .. tostring(errEnter) .. ")")
eq(exports.spawnManager.mapId, "ROUTE_101", "the real event reached spawnManager:onMapEntered")
-- No real Emerald ROM cache is mounted in this harness -- see header.
eq(exports.spawnManager:count(), 0, "no spawns without a mounted encounter cache (expected here)")

local okExit, errExit = pcall(Runtime.emit, "map.exited", { mapId = "ROUTE_101" })
check(okExit, "a real map.exited through Runtime.emit does not throw (" .. tostring(errExit) .. ")")

r.release()

-- ------- FireRed: this mod targets RSE only, so it must install nothing
-- even though generation is forced to 3 the same way
local rFr = loadWildsOfHoenn("firered")
eq(#rFr.errors, 0, "wilds_of_hoenn loads with no Loader errors on FireRed")
local mFr = rFr.loader.mods.wilds_of_hoenn
eq(mFr and mFr.state, "loaded", "FireRed: mod still reaches loaded (it's a valid Gen 3 target)")
local exportsFr = rFr.loader.exports and rFr.loader.exports.wilds_of_hoenn
eq(exportsFr and exportsFr.engineReady, false, "FireRed: engineReady stays false (RSE-only mod)")
check(exportsFr and exportsFr.spawnManager == nil, "FireRed: no spawnManager exported")
rFr.release()

print("")
if failures > 0 then
  io.stderr:write(failures .. " failure(s)\n")
  os.exit(1)
end
print("modkit_boot_test: all passed")
