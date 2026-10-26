-- Run: lua tests/options_page_unit_test.lua
-- lib/options_page.lua: the WILDS OF HOENN entry on the game's OPTIONS page and its rows.
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

local sets = {}
local fakeEngine = {
  currentGame = function() return nil end,
  setModOption = function(game, modId, key, value) sets[#sets + 1] = { game, modId, key, value } return true end,
}
local V = { require = function(name) assert(name == "engine_patch") return fakeEngine end }
local OptionsPage = assert(loadfile("lib/options_page.lua"))(V)

local stored = {}
local mod = { id = "wilds_of_hoenn", options = { get = function(_, k) return stored[k] end } }
local schema = {
  { key = "enabled", type = "toggle", label = "Show Wild Mons", default = true },
  { key = "spawn_amount", type = "choice", label = "Spawn Amount", default = "normal",
    choices = { { "LOW", "low" }, { "NORMAL", "normal" }, { "HIGH", "high" } } },
  { key = "odd", type = "slider", label = "Odd" },
}
local game = { mods = { optionSchemas = { wilds_of_hoenn = schema } } }
local ctx = { game = game }

-- the entry opens a page of the schema's rows
local opened
local entry = OptionsPage.entry(mod, function(title, rows) opened = { title, rows } end)
eq(entry.label, "WILDS OF HOENN", "one entry on the top page")
eq(entry.value(), "", "...with no value of its own")
entry.activate(ctx)
eq(opened[1], "WILDS OF HOENN", "activating it opens the page")
local rows = opened[2]
eq(#rows, 2, "toggle + choice rows; a kind the page cannot show is left out")
eq(rows[1].label, "SHOW WILD MONS", "labels upper-cased, in the schema's order")

-- toggle: default shown, a step stores the flip through the Mod Manager's setter
eq(rows[1].value(), "ON", "a toggle at its default")
rows[1].step(ctx)
eq(sets[1][1], game, "set on the running game")
eq(sets[1][2], "wilds_of_hoenn", "...for this mod")
eq(sets[1][3], "enabled", "...the row's key")
eq(sets[1][4], false, "...flipped")
stored.enabled = false
eq(rows[1].value(), "OFF", "shows the stored value")

-- choice: cycles both ways, wrapping
eq(rows[2].value(), "NORMAL", "a choice at its default")
rows[2].step(ctx, 1)
eq(sets[2][4], "high", "right: the next choice")
stored.spawn_amount = "high"
rows[2].step(ctx, 1)
eq(sets[3][4], "low", "past the end: wraps to the first")
stored.spawn_amount = "low"
rows[2].step(ctx, -1)
eq(sets[4][4], "high", "left from the first: wraps to the last")
stored.spawn_amount = "gone"
eq(rows[2].value(), "NORMAL", "an unknown stored value shows the default")

-- no schema (no game): an empty page, no error
eq(#OptionsPage.rows(mod, nil), 0, "no game: no rows")

print("")
if failures > 0 then
  io.stderr:write(failures .. " failure(s)\n")
  os.exit(1)
end
print("options_page_unit_test: all passed")
