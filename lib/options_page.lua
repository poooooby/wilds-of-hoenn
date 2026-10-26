-- WILDS OF HOENN in the game's own OPTIONS menu: one entry on the top page that opens a
-- page of this mod's options, so they can be changed while playing without going through
-- the Mods menu. (Idea and first version: the Project Highlander author.)
--
-- The rows are the schema options.lua registered (game.mods.optionSchemas), in the same
-- order, so an option the install leaves out (Sprite Style's PMDCollab choice without its
-- art, the Gen 3-only rows) is left out here too. A change goes through
-- EnginePatch.setModOption -- the Mod Manager's own setter -- so it is stored and announced
-- (`mod.options_changed`) exactly like a Mod Manager change and everything reacts the same.
-- The entry itself is added by EnginePatch's optional Rows.group wrap (hooks.optionsRow).
local V = ...
local EnginePatch = V.require("engine_patch")

local OptionsPage = {}

OptionsPage.TITLE = "WILDS OF HOENN"

local function gameOf(c)
  if type(c) == "table" and type(c.game) == "table" then return c.game end
  if type(c) == "table" and type(c.mods) == "table" then return c end -- a game itself
  return EnginePatch.currentGame()
end

local function schemaOf(mod, game)
  local loader = game and game.mods
  local s = loader and loader.optionSchemas and loader.optionSchemas[mod.id]
  return type(s) == "table" and s or nil
end

local function current(mod, row)
  local v = mod.options and mod.options:get(row.key)
  if v == nil then v = row.default end
  return v
end

local function choiceIndex(row, value)
  for i, c in ipairs(row.choices) do
    if c[2] == value then return i end
  end
  return nil
end

--- One page row for a schema row (toggle / choice), or nil for a kind this page cannot
--- show (Mods menu only).
function OptionsPage.rowFor(mod, row, set)
  local label = tostring(row.label or row.key):upper()
  if row.type == "toggle" then
    return {
      id = "woh_" .. row.key, label = label,
      value = function() return current(mod, row) == true and "ON" or "OFF" end,
      step = function(c)
        set(gameOf(c), row.key, current(mod, row) ~= true)
        return true
      end,
    }
  end
  if row.type == "choice" and type(row.choices) == "table" and #row.choices > 0 then
    return {
      id = "woh_" .. row.key, label = label,
      value = function()
        local i = choiceIndex(row, current(mod, row)) or choiceIndex(row, row.default) or 1
        return tostring(row.choices[i][1])
      end,
      step = function(c, dir)
        local n = #row.choices
        local i = choiceIndex(row, current(mod, row)) or choiceIndex(row, row.default) or 1
        i = ((i - 1 + ((dir and dir < 0) and -1 or 1)) % n) + 1
        set(gameOf(c), row.key, row.choices[i][2])
        return true
      end,
    }
  end
  return nil
end

--- The page's rows for `game`.
function OptionsPage.rows(mod, game, set)
  set = set or function(g, key, value) return EnginePatch.setModOption(g, mod.id, key, value) end
  local out = {}
  for _, row in ipairs(schemaOf(mod, game) or {}) do
    if type(row) == "table" and type(row.key) == "string" then
      local r = OptionsPage.rowFor(mod, row, set)
      if r then out[#out + 1] = r end
    end
  end
  return out
end

--- The entry on the top OPTIONS page (hooks.optionsRow): opens the page.
function OptionsPage.entry(mod, openPage)
  return {
    id = "woh_page", label = OptionsPage.TITLE, value = function() return "" end,
    activate = function(c) openPage(OptionsPage.TITLE, OptionsPage.rows(mod, gameOf(c))) end,
  }
end

return OptionsPage
