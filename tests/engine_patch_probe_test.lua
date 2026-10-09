-- Checks EnginePatch's probe() against the REAL engine. Run from inside a
-- gen1recomp checkout, with luajit (matches Wilds of Kanto Revival's own
-- two harness tests):
--   cd ../gen1recomp   (or wherever this mod is linked in as mods/wilds_of_hoenn)
--   luajit mods/wilds_of_hoenn/tests/engine_patch_probe_test.lua
--
-- A failure here means an engine update moved one of the fields
-- lib/engine_patch.lua depends on -- fix the TARGETS/READONLY entry (and
-- the code that reads it) before anything else, since every other feature
-- in this mod is built on top of these exact touch points holding still.
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

-- Locate lib/engine_patch.lua whether this test runs from the mod's own
-- repo root or from inside a gen1recomp checkout with the mod linked under
-- mods/wilds_of_hoenn (same two-path probe Wilds' harness tests use).
local function loadEnginePatch()
  for _, rel in ipairs({ "lib/engine_patch.lua", "mods/wilds_of_hoenn/lib/engine_patch.lua" }) do
    local f = io.open(rel, "rb")
    if f then
      f:close()
      return assert(loadfile(rel))()
    end
  end
  error("could not find lib/engine_patch.lua from " .. tostring(io.popen and "cwd"))
end

local EnginePatch = loadEnginePatch()

local ok, missing = EnginePatch.probe()
check(ok, "EnginePatch.probe() passes against the real engine")
if not ok then
  for _, m in ipairs(missing) do
    io.stderr:write("  missing: " .. tostring(m) .. "\n")
  end
end

-- isRse() should at least run without erroring, whichever game is active
-- in this checkout (it may be false if the checkout's default version
-- isn't Ruby/Sapphire/Emerald -- that's not a failure by itself).
local okRse, _ = pcall(EnginePatch.isRse)
check(okRse, "EnginePatch.isRse() runs without error")

-- "Ready to evolve!" must never show for a Pokemon holding an Everstone: the label
-- is only set when the REAL engine offers an evolution, and the engine's own
-- rule (pokemon.c GetEvolutionTargetSpecies) refuses one for an Everstone holder.
-- No ROM here, so the species' evolution row is stubbed; the gate is the real code.
do
  local okMods, Pokemon = pcall(require, "src.core.game3.pokemon")
  local okEvo, Evolution = pcall(require, "src.core.game3.evolution")
  if okMods and okEvo and Pokemon and Evolution then
    local real = Pokemon.evolutions
    Pokemon.evolutions = function() return { { method = Evolution.EVO_LEVEL, param = 16, target = 278 } } end
    local ITEM_EVERSTONE = 195
    local mon = { species = 277, level = 30, personality = 1 }
    check((Evolution.targetSpecies(mon, Evolution.EVO_MODE_NORMAL)) == 278, "engine: a Pokemon past its evolution level has a target")
    mon.item = ITEM_EVERSTONE
    check((Evolution.targetSpecies(mon, Evolution.EVO_MODE_NORMAL)) == 0, "engine: holding an Everstone, it has none")
    mon.item = nil
    mon.level = 10
    check((Evolution.targetSpecies(mon, Evolution.EVO_MODE_NORMAL)) == 0, "engine: below the level, none")
    Pokemon.evolutions = real
  end
end

print("")
if failures > 0 then
  io.stderr:write(failures .. " failure(s)\n")
  os.exit(1)
end
print("engine_patch_probe_test: all passed")
