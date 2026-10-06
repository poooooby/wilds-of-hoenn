-- Run: lua tests/engine_patch_unit_test.lua
-- Exercises EnginePatch's probe/install/uninstall against FAKE
-- src.core.game3.* modules stuffed into package.loaded -- this never
-- touches a real gen1recomp checkout. tests/engine_patch_probe_test.lua
-- (luajit, inside a gen1recomp checkout) is the one that checks the real
-- engine still has the shape this file assumes.
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

-- ------- fake engine modules, one per EnginePatch target/readonly entry
local fake = {}
fake["src.core.game3.field_effects"] = { collectActors = function(_actors) end }
fake["src.core.game3.objects"] = { blocks = function(_tx, _ty, _except, _elev) return false end }
fake["src.world.game3.Follower"] = {
  update = function(_game) end,
  current = function() return nil end,
}
fake["src.core.game3.battle_bridge"] = {
  startWild = function(_mod, _game, _enc, _opts) return true end,
}
fake["src.core.game3.encounters"] = {
  rollSweetScent = function(_mapId, _terrain) return nil end,
  terrainAt = function(_x, _y) return nil end,
  ensureLoaded = function() return true end,
  tableFor = function(_mapId) return nil end,
  rules = function() return {} end,
  _h = { wild_level_allowed_by_repel = function(_level) return true end },
}
fake["src.core.game3.collision"] = {
  isWater = function() return false end,
  isGrass = function() return false end,
  canEnter = function() return true end,
  inBounds = function() return true end,
  _widthCells = 10, _heightCells = 10,
}
fake["src.core.game3.pokemon"] = {
  national = function(id) return id end,
  speciesFromNational = function(nat) return nat end,
  speciesMeta = function() return {} end,
  isShiny = function(_mon) return false end,
  gender = function() return 0 end,
}
fake["src.core.game3.runtime"] = {
  getSession = function() return { trainerId = 1234, secretId = 5678, party = {} } end,
}
fake["src.core.game3.dex"] = { isCaught = function() return false end }
fake["src.core.GameVersion"] = {
  layout = function() return "rse" end,
  get = function() return "emerald" end,
}

local realRequire = require
_G.require = function(name)
  if fake[name] ~= nil then return fake[name] end
  return realRequire(name)
end

local EnginePatch = assert(loadfile("lib/engine_patch.lua"))(nil)

-- ------- probe passes against the full fake set
local ok, missing = EnginePatch.probe()
check(ok, "probe passes against a complete fake engine")
eq(#missing, 0, "no missing targets reported")

-- ------- isRse reads the fake GameVersion
check(EnginePatch.isRse(), "isRse true for the fake emerald/rse version")

-- ------- install/uninstall wraps and restores exactly the TARGETS
local originalBlocks = fake["src.core.game3.objects"].blocks
local calls = { collectActors = 0, blocks = 0, followerTick = 0 }
local installed = EnginePatch.install({
  collectActors = function(_actors) calls.collectActors = calls.collectActors + 1 end,
  blocks = function(_tx, _ty, _except, _elev) calls.blocks = calls.blocks + 1 return true end,
  followerTick = function(_game) calls.followerTick = calls.followerTick + 1 end,
}, { warn = function() end, info = function() end })
check(installed, "install succeeds against the fake engine")

fake["src.core.game3.field_effects"].collectActors({})
eq(calls.collectActors, 1, "collectActors hook ran after the wrap")

local blocked = fake["src.core.game3.objects"].blocks(1, 2, nil, 3)
check(blocked == true, "blocks wrap returns true when our hook says blocked")
eq(calls.blocks, 1, "blocks hook ran")

fake["src.world.game3.Follower"].update({})
eq(calls.followerTick, 1, "followerTick hook ran after the real update")

-- A second install() call while already installed is a no-op, not a
-- double-wrap (idempotent on hot reload).
local installedAgain = EnginePatch.install({
  collectActors = function() calls.collectActors = calls.collectActors + 100 end,
}, { warn = function() end, info = function() end })
check(installedAgain, "install() returns true when already installed")
fake["src.core.game3.field_effects"].collectActors({})
eq(calls.collectActors, 2, "second install() did not double-wrap collectActors")

EnginePatch.uninstall()
eq(fake["src.core.game3.objects"].blocks, originalBlocks, "uninstall restores the original blocks function")

local blockedAfterUninstall = fake["src.core.game3.objects"].blocks(1, 2, nil, 3)
check(blockedAfterUninstall == false, "blocks is back to vanilla (always false) after uninstall")

-- ------- probe fails loudly when a target goes missing (simulates an
-- engine update that renamed/removed a field this mod depends on)
local savedBlocks = fake["src.core.game3.objects"].blocks
fake["src.core.game3.objects"].blocks = nil
local ok2, missing2 = EnginePatch.probe()
check(not ok2, "probe fails when objects.blocks is missing")
local sawBlocks = false
for _, m in ipairs(missing2) do
  if m:find("blocks", 1, true) then sawBlocks = true end
end
check(sawBlocks, "the failure list names the missing target")

local installedAfterBreak, missing3 = EnginePatch.install({}, { warn = function() end, info = function() end })
check(not installedAfterBreak, "install() refuses when probe() fails")
check(type(missing3) == "table" and #missing3 > 0, "install() hands back the missing list")

fake["src.core.game3.objects"].blocks = savedBlocks

-- ------- read-only accessors
eq(EnginePatch.nationalFor(252), 252, "nationalFor delegates to pokemon.national")
eq(EnginePatch.speciesForNational(252), 252, "speciesForNational delegates to pokemon.speciesFromNational")
local w, h = EnginePatch.mapBounds()
eq(w, 10, "mapBounds width from Collision._widthCells")
eq(h, 10, "mapBounds height from Collision._heightCells")

local ids = EnginePatch.trainerIds()
check(ids ~= nil and ids.otId == 1234 and ids.otSecretId == 5678, "trainerIds reads the live session")

_G.require = realRequire

print("")
if failures > 0 then
  io.stderr:write(failures .. " failure(s)\n")
  os.exit(1)
end
print("engine_patch_unit_test: all passed")
