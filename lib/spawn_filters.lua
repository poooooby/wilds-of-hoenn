-- Spawn filters: a public seam for mods that change WHICH species a wild
-- encounter turns out to be (version-exclusive swaps, "every game has every
-- exclusive" mods and the like).
--
-- Why it exists: such mods usually change the species when the battle starts
-- (BattleBridge.startWild). This mod rolls its visible Pokemon long before
-- that, from the engine's own tables, so without a seam you would see one
-- species walking in the grass and fight another one. A filter runs right when
-- a visible Pokemon is rolled, so the one you see is the one you fight.
--
-- Use (from another mod):
--
--   local woh = mod.find("wilds_of_hoenn")
--   if woh and woh.exports.addSpawnFilter then
--     woh.exports.addSpawnFilter("my_mod", function(enc, info)
--       -- enc:  the rolled encounter { species, level, personality, ivs, ... }
--       -- info: { mapId, terrain = "land" | "water", lured = true|false }
--       if enc.species == 37 and math.random() < 0.5 then enc.species = 58 end
--       return enc -- or nil to leave it as it was
--     end)
--   end
--
-- A battle started by touching a visible Pokemon passes
-- opts.wildsOfHoenn = true and opts.speciesLocked = true to
-- BattleBridge.startWild: its species is already decided, so a mod that swaps
-- species at battle time should leave those battles alone.
--
-- Filters run in the order they were added; adding the same id again replaces
-- it. A filter that errors is skipped (logged once), never a crash. Roaming
-- legendaries never go through filters.
local V = ...

local SpawnFilters = { list = {}, warned = {} }

function SpawnFilters.add(id, fn)
  if type(fn) ~= "function" then return false end
  id = tostring(id or ("filter" .. tostring(#SpawnFilters.list + 1)))
  for _, f in ipairs(SpawnFilters.list) do
    if f.id == id then f.fn = fn return true end
  end
  SpawnFilters.list[#SpawnFilters.list + 1] = { id = id, fn = fn }
  return true
end

function SpawnFilters.remove(id)
  id = tostring(id)
  for i, f in ipairs(SpawnFilters.list) do
    if f.id == id then table.remove(SpawnFilters.list, i) return true end
  end
  return false
end

--- `enc` after every filter (a new or the same table); `enc` unchanged when
--- there are none, it is a roamer, or every filter fails.
function SpawnFilters.apply(mapId, terrain, enc, lured)
  if type(enc) ~= "table" or enc.roamer or #SpawnFilters.list == 0 then return enc end
  local info = { mapId = mapId, terrain = terrain, lured = lured == true }
  for _, f in ipairs(SpawnFilters.list) do
    local before = enc.species
    local ok, out = pcall(f.fn, enc, info)
    if ok then
      if type(out) == "table" then enc = out end
      local sp = tonumber(enc.species) or tonumber(enc.speciesId)
      if sp then
        enc.species = sp
        if enc.speciesId ~= nil then enc.speciesId = sp end
      else
        enc.species = before -- a filter left no usable species: keep the rolled one
      end
    elseif not SpawnFilters.warned[f.id] then
      SpawnFilters.warned[f.id] = true
      local log = V.mod and V.mod.log
      if log then log:warn("[wilds_of_hoenn] spawn filter %s failed: %s", f.id, tostring(out)) end
    end
  end
  return enc
end

return SpawnFilters
