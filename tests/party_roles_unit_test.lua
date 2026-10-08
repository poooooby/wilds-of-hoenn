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

local E = { battle = false, selects = 0 }
E.battleActive = function() return E.battle end
E.displayName = function(mon) return mon.nickname or "TREECKO" end
E.playSelect = function() E.selects = E.selects + 1 end

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
  local menu = { open = true, mode = "action", cursor = 1, actionCursor = 1, ACTIONS = actions,
    _party = { mon or { personality = 1, species = 252, hp = 10, nickname = "BLAZE" } },
    _fieldMoveNames = {},
    _cursorOptionText = function(act)
      assert(({ SUMMARY = 1, SWITCH = 1, ITEM = 1, CANCEL = 1, CUT = 1 })[act], "engine asserts on " .. act)
      return act:lower()
    end,
  }
  return menu
end
-- the ROLE / BACK labels carry the arrows; show them by name
local function labels(menu)
  local out = {}
  for i, a in ipairs(menu.ACTIONS) do
    out[i] = a == PartyRoles.ROLE and "ROLE" or a == PartyRoles.BACK and "BACK" or a
  end
  return table.concat(out, ",")
end
-- a fake frame input: only the named buttons are pressed
local function press(...)
  local down = {}
  for _, k in ipairs({ ... }) do down[k] = true end
  return { wasPressed = function(_, k) return down[k] == true end }
end

-- ------- one ROLE row goes in before SWITCH, as a field-move row
do
  local roles = PartyRoles.new(Companion.new(mod))
  local menu = newMenu({ "SUMMARY", "SWITCH", "ITEM", "CANCEL" })
  roles:onMenuUpdate(menu)
  eq(labels(menu), "SUMMARY,ROLE,SWITCH,ITEM,CANCEL", "ROLE is added before SWITCH")
  for _, label in ipairs({ PartyRoles.ROLE, "FOLLOW", "FORAGE", "FIGHT", PartyRoles.BACK }) do
    check(menu._fieldMoveNames[label], label .. " is registered as a field-move row (so the engine accepts it)")
  end
  eq(menu._actionTexts.list, menu.ACTIONS, "the prebuilt texts belong to the list")
  eq(#menu._actionTexts.texts, 5, "...one per row")
  eq(menu._actionTexts.texts[2], PartyRoles.ROLE, "the ROLE row shows its own label, arrow included")
  check(menu._actionTexts.texts[2]:find("\226\150\182", 1, true), "...ending in a right arrow")
  check(menu._actionTexts.texts[2]:find(string.char(0xFC, 0x13), 1, true), "...placed by pixel (CLEARTO)")
  eq(menu._actionTexts.texts[1], "summary", "the engine's rows keep the engine's text")
  roles:onMenuUpdate(menu)
  eq(labels(menu), "SUMMARY,ROLE,SWITCH,ITEM,CANCEL", "a second update does not add it again")
  menu.ACTIONS = { "SUMMARY", "SWITCH", "ITEM", "CANCEL" } -- A pressed again: a fresh list
  roles:onMenuUpdate(menu)
  eq(labels(menu), "SUMMARY,ROLE,SWITCH,ITEM,CANCEL", "a freshly built list gets it again")
end

-- ------- Ruby / Sapphire / Emerald build the list with the field moves FIRST,
-- a SWITCH only with 2+ party members, and MAIL in place of ITEM for held mail
do
  local roles = PartyRoles.new(Companion.new(mod))
  local rs = newMenu({ "CUT", "SUMMARY", "SWITCH", "ITEM", "CANCEL" })
  rs._fieldMoveNames.CUT = true
  roles:onMenuUpdate(rs)
  eq(labels(rs), "CUT,SUMMARY,ROLE,SWITCH,ITEM,CANCEL", "RSE order: after SUMMARY, before SWITCH")
  local solo = newMenu({ "SUMMARY", "ITEM", "CANCEL" })
  roles:onMenuUpdate(solo)
  eq(labels(solo), "SUMMARY,ROLE,ITEM,CANCEL", "a lone Pokemon (no SWITCH): before ITEM")
  local mail = newMenu({ "SUMMARY", "SWITCH", "MAIL", "CANCEL" })
  roles:onMenuUpdate(mail)
  eq(labels(mail), "SUMMARY,ROLE,SWITCH,MAIL,CANCEL", "a Pokemon holding mail (MAIL row) still gets it")
  local crowded = newMenu({ "SUMMARY", "CUT", "CUT", "CUT", "CUT", "SWITCH", "ITEM", "CANCEL" })
  roles:onMenuUpdate(crowded)
  eq(#crowded.ACTIONS, 9, "one row always fits, even in a crowded list (9 rows is the box's limit)")
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
  for _, act in ipairs({ PartyRoles.ROLE, "FOLLOW", "FORAGE", "FIGHT", PartyRoles.BACK }) do
    local ok, text = pcall(rsActionText, act, menu._fieldMoveData)
    check(ok and text, "the RS text lookup accepts the row " .. act)
  end
  eq(menu._fieldMoveData.byMove, real.byMove, "the rest of the field-move data passes straight through")
  eq(menu._fieldMoveData.base, 7, "...including plain values")
  eq(menu._fieldMoveData.index.CUT, 0, "...and the real index entries")
  eq(real.index[PartyRoles.ROLE], nil, "the real field-move data itself is never modified")
end

-- ------- ROLE opens the submenu; Back and B return
do
  local roles = PartyRoles.new(Companion.new(mod))
  local menu = newMenu({ "SUMMARY", "SWITCH", "ITEM", "CANCEL" })
  roles:onMenuUpdate(menu)
  menu.actionCursor = 1
  eq(roles:onInput(menu, press("a")), false, "A on SUMMARY is the engine's")
  eq(roles:onInput(menu, press("b")), false, "B on the primary list is the engine's (it closes the menu)")
  eq(roles:onInput(menu, press("down")), false, "moving the cursor is the engine's")
  menu.actionCursor = 2 -- ROLE
  E.selects = 0
  eq(roles:onInput(menu, press("a")), true, "A on ROLE is ours")
  eq(labels(menu), "FOLLOW,FORAGE,FIGHT,BACK", "the action list is now the role submenu")
  eq(menu.actionCursor, 1, "the cursor starts on Follow")
  eq(menu._actionTexts.list, menu.ACTIONS, "its texts belong to the new list")
  eq(menu._actionTexts.texts[1], "FOLLOW", "the roles show their own names")
  check(menu._actionTexts.texts[4]:find("\226\151\128", 1, true), "Back has a left arrow")
  eq(E.selects, 1, "opening it clicks")
  roles:onMenuUpdate(menu)
  eq(labels(menu), "FOLLOW,FORAGE,FIGHT,BACK", "a menu update does not treat the submenu as a new list")
  eq(roles:onInput(menu, press("a")), false, "A on FOLLOW is the engine's (it asks fromMenu)")
  menu.actionCursor = 3
  eq(roles:onInput(menu, press("a")), false, "...so is A on FIGHT")
  menu.actionCursor = 4
  eq(roles:onInput(menu, press("a")), true, "A on BACK is ours")
  eq(labels(menu), "SUMMARY,ROLE,SWITCH,ITEM,CANCEL", "it returns to the primary list")
  eq(menu.actionCursor, 2, "...with the cursor back on ROLE")
  eq(menu._actionTexts.list, menu.ACTIONS, "...and its texts")
  roles:onInput(menu, press("a")) -- ROLE again (cursor is on it)
  eq(labels(menu), "FOLLOW,FORAGE,FIGHT,BACK", "ROLE opens it again")
  menu.actionCursor = 2
  eq(roles:onInput(menu, press("b")), true, "B in the submenu is ours")
  eq(labels(menu), "SUMMARY,ROLE,SWITCH,ITEM,CANCEL", "...and goes back, not out of the menu")
  -- a role chosen: the engine shows the message and later builds a fresh list
  roles:onInput(menu, press("a"))
  menu.ACTIONS = { "SUMMARY", "SWITCH", "ITEM", "CANCEL" }
  roles:onMenuUpdate(menu)
  eq(labels(menu), "SUMMARY,ROLE,SWITCH,ITEM,CANCEL", "the next menu starts on the primary list again")
  eq(roles:onInput(menu, press("b")), false, "...so B closes it as usual")
end

-- ------- other menus' input is never touched
do
  local roles = PartyRoles.new(Companion.new(mod))
  local menu = newMenu({ "SUMMARY", "SWITCH", "ITEM", "CANCEL" })
  roles:onMenuUpdate(menu)
  menu.actionCursor = 2
  local other = newMenu({ "SUMMARY", "SWITCH", "ITEM", "CANCEL" })
  other.actionCursor = 2
  eq(roles:onInput(other, press("a")), false, "a list we did not touch")
  local list = newMenu({ "SUMMARY", "SWITCH", "ITEM", "CANCEL" })
  roles:onMenuUpdate(list)
  list.actionCursor, list.mode = 2, "list"
  eq(roles:onInput(list, press("a")), false, "the party list itself")
  eq(roles:onInput(nil, press("a")), false, "no menu at all is harmless")
  eq(roles:onInput(menu, nil), false, "...and no input")
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

-- ------- choosing a role sets the companion and answers with a message
do
  store = {}
  local companion = Companion.new(mod)
  local roles = PartyRoles.new(companion)
  local mon = { personality = 77, species = 252, hp = 10, nickname = "BLAZE" }
  local res = roles:fromMenu("FIGHT", { mon = mon, party = { mon } })
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
  eq(roles:fromMenu("ROLE", { mon = mon }), nil, "ROLE and BACK never reach the engine as roles")
  res = roles:fromMenu("FIGHT", { mon = {} })
  check(res and res.ok == false, "a Pokemon that cannot be saved still answers (no crash)")
end

if failures > 0 then
  io.stderr:write(failures .. " failure(s)\n")
  os.exit(1)
end
print("party_roles_unit_test: all passed")
