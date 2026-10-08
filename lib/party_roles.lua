-- A ROLE row in the party menu, opening a submenu: Follow / Forage / Fight / Back.
--
-- Pressing A on a party Pokemon opens a small action list (SUMMARY, field
-- moves, SWITCH, ITEM, CANCEL). The engine has no mod hook for that list, so:
--   * EnginePatch wraps PartyMenu.update; right after it runs, `onMenuUpdate`
--     inserts our ROLE row into a freshly built overworld list, registers our
--     rows as field-move rows, and prebuilds their texts (the engine's own text
--     lookup asserts on a label it does not know);
--   * EnginePatch wraps PartyMenu.handleInput; `onInput` sees A / B first: A on
--     ROLE swaps the action list for the role submenu, and Back (A on BACK, or
--     B) swaps the primary list back. Every other press goes to the engine;
--   * EnginePatch wraps FieldMoves.fromMenu; `fromMenu` answers FOLLOW / FORAGE /
--     FIGHT by setting the companion and returning { ok = false, text = ... },
--     which the engine shows inside the menu before returning to the list.
-- Every other row, and every other menu (battle switch, item use ...), is left
-- completely alone.
local V = ...
local EnginePatch = V.require("engine_patch")

local PartyRoles = {}
PartyRoles.__index = PartyRoles

local ROLE_OF = { FOLLOW = "follow", FORAGE = "forage", FIGHT = "battle" }
local LINES = {
  recall = "%s returned to you.",
  follow = "%s will follow you.",
  battle = "%s will battle wild Pokemon for you.",
  forage = "%s will forage for items.",
}
PartyRoles.LINES = LINES

-- The rows' own labels carry the arrows, because Ruby / Sapphire / Emerald draw
-- the action list straight from the labels (rs/party_menu_data.lua's
-- drawActions), while FireRed / LeafGreen draw prebuilt texts: with the arrow in
-- the label both show it. The arrows are the font's glyphs (UTF-8), the right one
-- placed by the font's CLEARTO pen code at a fixed pixel in the action box.
local RIGHT = "\226\150\182"
local LEFT = "\226\151\128"
local ARROW_X = 46 -- px from the label's left edge (the box is 80px wide)
local ROLE = "ROLE" .. string.char(0xFC, 0x13, ARROW_X) .. RIGHT
local BACK = LEFT .. " BACK"
PartyRoles.ROLE, PartyRoles.BACK = ROLE, BACK

function PartyRoles.new(companion)
  return setmetatable({ companion = companion, primary = nil, sub = nil }, PartyRoles)
end

local function indexOf(list, label)
  for i, v in ipairs(list) do
    if v == label then return i end
  end
  return nil
end

-- the engine's own text lookup would assert on our labels: build a text for every
-- row (ours show their own, the engine's rows keep the engine's text)
local function setTexts(menu, list)
  local own = { [ROLE] = true, [BACK] = true, FOLLOW = true, FORAGE = true, FIGHT = true }
  local texts = {}
  for i, act in ipairs(list) do
    if own[act] then
      texts[i] = act
    else
      local ok, text = pcall(menu._cursorOptionText, act)
      texts[i] = ok and text or tostring(act)
    end
  end
  menu._actionTexts = { list = list, texts = texts }
end

--- Run after every PartyMenu.update.
function PartyRoles:onMenuUpdate(menu)
  if not (menu and menu.open and menu.mode == "action") then return end
  local list = menu.ACTIONS
  if type(list) ~= "table" or list == self.primary or list == self.sub then return end
  -- only the overworld list: it has SUMMARY, CANCEL and ITEM (or MAIL when the
  -- Pokemon holds mail); a battle's lists and an egg's never have an ITEM row.
  -- (Ruby / Sapphire / Emerald put the field moves BEFORE SUMMARY, FireRed /
  -- LeafGreen after it, so the position of SUMMARY is not checked.)
  if not indexOf(list, "SUMMARY") or not indexOf(list, "CANCEL") then return end
  if not (indexOf(list, "ITEM") or indexOf(list, "MAIL")) then return end
  if EnginePatch.battleActive() then return end
  local mon = menu._party and menu._party[menu.cursor]
  if type(mon) ~= "table" or mon.isEgg or mon.egg then return end

  local at = indexOf(list, "SWITCH") or indexOf(list, "ITEM") or indexOf(list, "MAIL") or indexOf(list, "CANCEL")
  table.insert(list, at, ROLE)
  self.primary, self.sub = list, nil

  menu._fieldMoveNames = menu._fieldMoveNames or {}
  for _, label in ipairs({ ROLE, "FOLLOW", "FORAGE", "FIGHT", BACK }) do menu._fieldMoveNames[label] = true end

  -- Ruby / Sapphire / Emerald draw each row through `actionText(action, fields)`
  -- every frame, which asserts that an action is a native one or listed in
  -- `fields.index`. Hand the menu a view of its field-move data that also knows
  -- our rows (everything else passes straight through to the real data).
  local fields = menu._fieldMoveData
  if type(fields) == "table" and type(fields.index) == "table" then
    local index = setmetatable({}, { __index = fields.index })
    for _, label in ipairs({ ROLE, "FOLLOW", "FORAGE", "FIGHT", BACK }) do index[label] = true end
    menu._fieldMoveData = setmetatable({ index = index }, { __index = fields })
  end

  setTexts(menu, list)
end

-- Swap the action list for the role submenu / back for the primary list.
function PartyRoles:openSub(menu)
  self.sub = { "FOLLOW", "FORAGE", "FIGHT", BACK }
  menu.ACTIONS = self.sub
  menu.actionCursor = 1
  setTexts(menu, self.sub)
end

function PartyRoles:closeSub(menu)
  menu.ACTIONS = self.primary
  menu.actionCursor = indexOf(self.primary, ROLE) or 1
  setTexts(menu, self.primary)
  self.sub = nil
end

--- Run BEFORE PartyMenu.handleInput. Returns true when the press was ours (the
--- engine must not also act on it): A on ROLE opens the submenu; A on BACK or B
--- in the submenu goes back. Everything else -- moving the cursor, A on FOLLOW /
--- FORAGE / FIGHT -- is the engine's own.
function PartyRoles:onInput(menu, input)
  if not (menu and menu.open and menu.mode == "action" and input and input.wasPressed) then return false end
  local list = menu.ACTIONS
  if list ~= self.primary and list ~= self.sub then return false end
  local act = list[menu.actionCursor]
  local a, b = input:wasPressed("a"), input:wasPressed("b")
  if list == self.primary then
    if a and act == ROLE then
      self:openSub(menu)
      EnginePatch.playSelect()
      return true
    end
    return false
  end
  if b or (a and act == BACK) then
    self:closeSub(menu)
    EnginePatch.playSelect()
    return true
  end
  return false
end

--- FieldMoves.fromMenu's first look: a result table for our rows, else nil.
function PartyRoles:fromMenu(label, ctx)
  local role = ROLE_OF[label]
  if not role then return nil end
  local mon = ctx and ctx.mon
  if not mon or not self.companion:set(mon, role) then
    return { ok = false, text = "Nothing happened." }
  end
  return { ok = false, text = string.format(LINES[role], EnginePatch.displayName(mon)) }
end

return PartyRoles
