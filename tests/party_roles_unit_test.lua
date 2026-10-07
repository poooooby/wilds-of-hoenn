-- Run: lua tests/party_roles_unit_test.lua
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

local E = { battle = false }
E.battleActive = function() return E.battle end
E.displayName = function(mon) return mon.nickname or "TREECKO" end

local modules = {}
local V = { path = "." }
function V.require(name)
  if modules[name] ~= nil then return modules[name] end
  if name == "engine_patch" then modules[name] = E return E end
  local value = assert(loadfile("lib/" .. name .. ".lua"))(V)
  modules[name] = value
  return value
end
local Companion = V.require("companion")
local PartyRoles = V.require("party_roles")

local store = {}
local mod = { save = { get = function(_, k) return store[k] end, set = function(_, k, v) store[k] = v end } }

local function newMenu(actions, mon)
  local menu = { open = true, mode = "action", cursor = 1, ACTIONS = actions,
    _party = { mon or { personality = 1, species = 252, hp = 10, nickname = "BLAZE" } },
    _fieldMoveNames = {},
    _cursorOptionText = function(act)
      assert(({ SUMMARY = 1, SWITCH = 1, ITEM = 1, CANCEL = 1, CUT = 1 })[act], "engine asserts on " .. act)
      return act:lower()
    end,
  }
  return menu
end
local function labels(menu) return table.concat(menu.ACTIONS, ",") end

-- ------- the three rows go in before SWITCH, as field-move rows
do
  local companion = Companion.new(mod)
  local roles = PartyRoles.new(companion)
  local menu = newMenu({ "SUMMARY", "SWITCH", "ITEM", "CANCEL" })
  roles:onMenuUpdate(menu)
  eq(labels(menu), "SUMMARY,FOLLOW,BATTLE,FORAGE,SWITCH,ITEM,CANCEL", "Follow / Battle / Forage are added before SWITCH")
  check(menu._fieldMoveNames.FOLLOW and menu._fieldMoveNames.BATTLE and menu._fieldMoveNames.FORAGE,
    "they are registered as field-move rows (so the engine routes them to FieldMoves.fromMenu)")
  eq(menu._actionTexts.list, menu.ACTIONS, "the prebuilt texts belong to the list")
  eq(#menu._actionTexts.texts, 7, "...one per row")
  eq(menu._actionTexts.texts[2], "FOLLOW", "our rows show their own names")
  eq(menu._actionTexts.texts[1], "summary", "...and the engine's rows keep the engine's text")
  roles:onMenuUpdate(menu)
  eq(labels(menu), "SUMMARY,FOLLOW,BATTLE,FORAGE,SWITCH,ITEM,CANCEL", "a second update does not add them again")
  menu.ACTIONS = { "SUMMARY", "SWITCH", "ITEM", "CANCEL" } -- A pressed again: a fresh list
  roles:onMenuUpdate(menu)
  eq(labels(menu), "SUMMARY,FOLLOW,BATTLE,FORAGE,SWITCH,ITEM,CANCEL", "a freshly built list gets them again")
end

-- ------- Ruby / Sapphire / Emerald build the list with the field moves FIRST,
-- a SWITCH only with 2+ party members, and MAIL in place of ITEM for held mail
do
  local roles = PartyRoles.new(Companion.new(mod))
  local rs = newMenu({ "CUT", "SUMMARY", "SWITCH", "ITEM", "CANCEL" })
  rs._fieldMoveNames.CUT = true
  roles:onMenuUpdate(rs)
  eq(labels(rs), "CUT,SUMMARY,FOLLOW,BATTLE,FORAGE,SWITCH,ITEM,CANCEL", "RSE order: after SUMMARY, before SWITCH")
  local solo = newMenu({ "SUMMARY", "ITEM", "CANCEL" })
  roles:onMenuUpdate(solo)
  eq(labels(solo), "SUMMARY,FOLLOW,BATTLE,FORAGE,ITEM,CANCEL", "a lone Pokemon (no SWITCH): before ITEM")
  local mail = newMenu({ "SUMMARY", "SWITCH", "MAIL", "CANCEL" })
  roles:onMenuUpdate(mail)
  eq(labels(mail), "SUMMARY,FOLLOW,BATTLE,FORAGE,SWITCH,MAIL,CANCEL", "a Pokemon holding mail (MAIL row) still gets them")
end

-- ------- Ruby / Sapphire / Emerald's per-frame text lookup asserts on unknown rows
do
  local roles = PartyRoles.new(Companion.new(mod))
  local real = { index = { CUT = 0 }, byMove = { [15] = "CUT" }, base = 7 }
  local menu = newMenu({ "SUMMARY", "SWITCH", "ITEM", "CANCEL" })
  menu._fieldMoveData = real
  -- what rs/party_menu_data.lua's actionText does
  local function rsActionText(action, fields)
    local native = { SUMMARY = true, SWITCH = true, ITEM = true, CANCEL = true }
    if native[action] then return action:lower() end
    assert(fields and fields.index[action] ~= nil, "unknown native RS party action: " .. tostring(action))
    return action
  end
  roles:onMenuUpdate(menu)
  for _, act in ipairs(menu.ACTIONS) do
    local ok, text = pcall(rsActionText, act, menu._fieldMoveData)
    check(ok and text, "the RS text lookup accepts the row " .. act)
  end
  eq(menu._fieldMoveData.byMove, real.byMove, "the rest of the field-move data passes straight through")
  eq(menu._fieldMoveData.base, 7, "...including plain values")
  eq(menu._fieldMoveData.index.CUT, 0, "...and the real index entries")
  eq(real.index.FOLLOW, nil, "the real field-move data itself is never modified")
end

-- ------- with field moves the rows sit after them; a pike-style list without SWITCH still works
do
  local roles = PartyRoles.new(Companion.new(mod))
  local menu = newMenu({ "SUMMARY", "CUT", "SWITCH", "ITEM", "CANCEL" })
  menu._fieldMoveNames.CUT = true
  roles:onMenuUpdate(menu)
  eq(labels(menu), "SUMMARY,CUT,FOLLOW,BATTLE,FORAGE,SWITCH,ITEM,CANCEL", "field moves keep their place")
  local pike = newMenu({ "SUMMARY", "ITEM", "CANCEL" })
  roles:onMenuUpdate(pike)
  eq(labels(pike), "SUMMARY,FOLLOW,BATTLE,FORAGE,ITEM,CANCEL", "without SWITCH they go before ITEM")
end

-- ------- too many rows for the box: one COMPANION row that cycles the role
do
  local roles = PartyRoles.new(Companion.new(mod))
  local menu = newMenu({ "SUMMARY", "CUT", "CUT", "CUT", "CUT", "SWITCH", "ITEM", "CANCEL" })
  roles:onMenuUpdate(menu)
  eq(#menu.ACTIONS, 9, "a crowded list gets a single row (9 rows is the box's limit)")
  check(menu._fieldMoveNames.COMPANION, "...registered like the others")
end

-- ------- every other menu is left alone
do
  local roles = PartyRoles.new(Companion.new(mod))
  local function untouched(menu, why)
    local before = labels(menu)
    roles:onMenuUpdate(menu)
    eq(labels(menu), before, why)
  end
  untouched(newMenu({ "SEND OUT", "SUMMARY", "CANCEL" }), "a battle send-out list")
  untouched(newMenu({ "SUMMARY", "CANCEL" }), "a list without ITEM")
  local closed = newMenu({ "SUMMARY", "SWITCH", "ITEM", "CANCEL" })
  closed.open = false
  untouched(closed, "a closed menu")
  local listMode = newMenu({ "SUMMARY", "SWITCH", "ITEM", "CANCEL" })
  listMode.mode = "list"
  untouched(listMode, "the party list itself")
  E.battle = true
  untouched(newMenu({ "SUMMARY", "SWITCH", "ITEM", "CANCEL" }), "any menu during a battle")
  E.battle = false
  untouched(newMenu({ "SUMMARY", "SWITCH", "ITEM", "CANCEL" }, { personality = 2, isEgg = true }), "an egg")
  check(pcall(roles.onMenuUpdate, roles, nil), "no menu at all is harmless")
end

-- ------- choosing a row sets the companion and answers with a message
do
  store = {}
  local companion = Companion.new(mod)
  local roles = PartyRoles.new(companion)
  local mon = { personality = 77, species = 252, hp = 10, nickname = "BLAZE" }
  local res = roles:fromMenu("BATTLE", { mon = mon, party = { mon } })
  check(res and res.ok == false, "the engine is told to show a message (ok = false)")
  check(res.text:find("BLAZE", 1, true) and res.text:lower():find("battle", 1, true), "the message names the Pokemon and the job")
  eq(select(2, companion:resolve({ mon })), "battle", "the companion is now a Battler")
  res = roles:fromMenu("FORAGE", { mon = mon })
  eq(select(2, companion:resolve({ mon })), "forage", "Forage works")
  res = roles:fromMenu("FOLLOW", { mon = mon })
  eq(select(2, companion:resolve({ mon })), "follow", "and so does Follow")
  check(res.text:lower():find("follow", 1, true), "with its own line")
  eq(roles:fromMenu("CUT", { mon = mon }), nil, "a real field move is left to the engine")
  eq(roles:fromMenu("SURF", nil), nil, "...with or without a context")
  -- the compact row cycles
  roles:fromMenu("FOLLOW", { mon = mon })
  roles:fromMenu("COMPANION", { mon = mon })
  eq(select(2, companion:resolve({ mon })), "battle", "COMPANION: follow -> battle")
  roles:fromMenu("COMPANION", { mon = mon })
  eq(select(2, companion:resolve({ mon })), "forage", "...-> forage")
  roles:fromMenu("COMPANION", { mon = mon })
  eq(select(2, companion:resolve({ mon })), "follow", "...-> follow")
  res = roles:fromMenu("BATTLE", { mon = {} })
  check(res and res.ok == false, "a Pokemon that cannot be saved still answers (no crash)")
end

if failures > 0 then
  io.stderr:write(failures .. " failure(s)\n")
  os.exit(1)
end
print("party_roles_unit_test: all passed")
