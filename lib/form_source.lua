-- Which sprite a Pokemon's SPECIES SLOT draws: the plain national dex number
-- for a base species, "%03d-<form>" for an alternate form.
--
-- National Dex Gen 3 registers every alternate form (Wormadam-Sandy, Rotom-Heat,
-- Galarian Darumaka, Flabebe's colours ...) as a species of its own in the
-- engine, and the engine reports a form's BASE dex number for it
-- (EnginePatch.nationalFor), so the number alone cannot tell a form from its
-- base. The mod's exports (apiVersion >= 2) can: idOfSlot(slot) gives the
-- species id registered at that slot and listForms() the forms, each carrying
-- `baseSpecies` (nil on a base species) and `form` (its name, lower-cased here
-- into the art key: "WORMADAM_SANDY" is form "SANDY" of dex 413 -> "413-sandy").
-- A form is recognised by `baseSpecies`, never by comparing dex numbers (a form
-- and its base collide on purpose).
--
-- Soft integration: the mod absent, inactive, older than apiVersion 2 or
-- erroring -> the plain dex number, exactly as before.
local V = ...
local EnginePatch = V.require("engine_patch")

local FormSource = {}

local cache = {} -- [mod] = { byId = { [id] = form row } } | false

local function formsFor(mod)
  local hit = cache[mod]
  if hit ~= nil then return hit or nil end
  local state = false
  if mod and type(mod.find) == "function" then
    local ok, other = pcall(mod.find, mod, "national_dex_gen3")
    local api = ok and other and other.exports
    if type(api) == "table" and (tonumber(api.apiVersion) or 0) >= 2
        and type(api.idOfSlot) == "function" and type(api.listForms) == "function" then
      local okList, list = pcall(api.listForms)
      if okList and type(list) == "table" then
        local byId = {}
        for _, row in ipairs(list) do
          if type(row) == "table" and row.id and row.baseSpecies ~= nil and row.form ~= nil then
            byId[row.id] = row
          end
        end
        state = { api = api, byId = byId }
      end
    end
  end
  cache[mod] = state
  return state or nil
end

--- "%03d-<form>" for a form's base dex + name; the name keeps its underscores
--- ("POM_POM" -> "741-pom_pom").
function FormSource.keyOf(baseDex, form)
  return string.format("%03d-%s", baseDex, tostring(form):lower())
end

--- The art key for an engine species id (slot): a form key when the slot is a
--- registered alternate form, else the national dex number. nil when the engine
--- has no dex number for the slot (egg placeholder ...).
function FormSource.artKeyFor(mod, slot)
  local dex = EnginePatch.nationalFor(slot)
  if not dex then return nil end
  local state = formsFor(mod)
  if not state then return dex end
  local okId, id = pcall(state.api.idOfSlot, slot)
  local row = okId and id and state.byId[id] or nil
  if row then return FormSource.keyOf(tonumber(row.baseDex or row.dex) or dex, row.form) end
  return dex
end

function FormSource._reset() cache = {} end

return FormSource
