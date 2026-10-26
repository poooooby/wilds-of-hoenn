-- Every English text this mod translates (lib/i18n.lua), collected from the code itself
-- so the language files can be checked against it (tests/i18n_coverage_unit_test.lua) and
-- dumped for translating (lua tests/i18n_keys.lua). Returns { keys = { [key] = kind },
-- lists = { send = {...}, recall = {...} } }; a key is the English, or "<context>|<English>".
package.path = "./?.lua;./?/init.lua;" .. package.path

local keys, lists = {}, {}
local function add(key, kind) keys[key] = kind or keys[key] or "text" end

-- options.lua: labels ("option"), choice labels ("choice"; not the Language row's), and
-- descriptions (Sprite Style's in two parts, as Config.translateSchema splits it)
local schema = assert(loadfile("options.lua"))()
for _, row in ipairs(schema) do
  add("option|" .. row.label, "option label")
  if row.choices and row.key ~= "language" then
    for _, c in ipairs(row.choices) do add("choice|" .. c[1], "choice label") end
  end
  local d = row.description
  local head, tail = d:match("^(.-)%s+(PMDCollab uses.*)$")
  if head then add(head, "description") add(tail, "description") else add(d, "description") end
end

-- the dialogue tables (every string in them that is a line)
local Dialogue = assert(loadfile("lib/follower_dialogue.lua"))(nil)
local function walk(t)
  for _, v in pairs(t) do
    if type(v) == "string" and v:find("{name}") then add(v, "dialogue")
    elseif type(v) == "table" then walk(v) end
  end
end
for _, t in pairs(Dialogue) do if type(t) == "table" then walk(t) end end

-- a V that loads the real lib files over a stub engine
local stub = setmetatable({}, { __index = function() return function() end end })
local V = { mod = nil }
local loaded = {}
function V.require(name)
  if name == "engine_patch" then return stub end
  if loaded[name] == nil then loaded[name] = assert(loadfile("lib/" .. name .. ".lua"))(V) end
  return loaded[name]
end

-- the partner's menu rows ("menu"), the party menu's ("party"), the role lines
local FI = V.require("follower_interaction")
for _, rows in pairs(FI.MENUS) do for _, r in ipairs(rows) do add("menu|" .. r[1], "menu row") end end
add("menu|Evolve", "menu row") add("menu|Learn Move", "menu row")
for _, l in ipairs({ "ROLE", "BACK", "FOLLOW", "FORAGE", "FIGHT" }) do add("party|" .. l, "party row (80 px box)") end
local PartyRoles = V.require("party_roles")
for _, line in pairs(PartyRoles.LINES) do add(line, "message (%s = name)") end
local LevelReady = V.require("level_ready")
add(LevelReady.MOVE_TEXT, "label over the partner") add(LevelReady.EVOLVE_TEXT, "label over the partner")
add("toggle|ON", "options page value") add("toggle|OFF", "options page value")

-- literal tr("...") / trc("ctx", "...") calls in lib/
local BS = string.char(92)
for _, file in ipairs({ "follower_interaction", "party_roles", "role_hotkey", "forager", "overworld_battle",
                        "follower_adapter", "options_page", "follower_dialogue", "popup_text" }) do
  local src = assert(io.open("lib/" .. file .. ".lua")):read("*a")
  for s in src:gmatch('[^%w_]tr%("([^"]+)"') do add(s:gsub(BS .. "'", "'"), "text") end
  for c, s in src:gmatch('[^%w_]trc%("(%w+)", "([^"]+)"') do add(c .. "|" .. s, "text") end
end
add("Lv.%d!", "level-up label")

local RoleHotkey = V.require("role_hotkey")
lists.send, lists.recall = RoleHotkey.SEND, RoleHotkey.RECALL

local out = { keys = keys, lists = lists }

-- run directly: print every key (sorted) for translating
if arg and arg[0] and arg[0]:find("i18n_keys") then
  local sorted = {}
  for k, kind in pairs(keys) do sorted[#sorted + 1] = { k, kind } end
  table.sort(sorted, function(a, b) return a[1] < b[1] end)
  for _, e in ipairs(sorted) do print(("[%s] %q"):format(e[2], e[1])) end
  print(("-- %d keys; lists: send %d, recall %d"):format(#sorted, #lists.send, #lists.recall))
end
return out
