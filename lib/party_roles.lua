-- Follow / Battle / Forage rows in the party menu.
--
-- Pressing A on a party Pokemon opens a small action list (SUMMARY, field
-- moves, SWITCH, ITEM, CANCEL). The engine has no mod hook for that list, so:
--   * EnginePatch wraps PartyMenu.update; right after it runs, `onMenuUpdate`
--     inserts our rows into a freshly built overworld list, registers them as
--     field-move rows, and prebuilds their texts (the engine's own text lookup
--     asserts on a label it does not know);
--   * EnginePatch wraps FieldMoves.fromMenu; `fromMenu` answers our rows by
--     setting the companion and returning { ok = false, text = ... }, which the
--     engine shows inside the menu before returning to the list.
-- Every other row, and every other menu (battle switch, item use ...), is left
-- completely alone.
local V = ...
local EnginePatch = V.require("engine_patch")

local PartyRoles = {}
PartyRoles.__index = PartyRoles

-- the engine's action box is `rows * 2` tiles tall in a 20-tile screen
local MAX_ROWS = 9
local ROWS = { "FOLLOW", "BATTLE", "FORAGE" }
local ROLE_OF = { FOLLOW = "follow", BATTLE = "battle", FORAGE = "forage" }
local COMPACT = "COMPANION" -- one row that cycles the role, when three would not fit
local NEXT = { follow = "battle", battle = "forage", forage = "follow", recall = "follow" }
local LINES = {
  recall = "%s returned to you.",
  follow = "%s will follow you.",
  battle = "%s will battle wild Pokemon for you.",
  forage = "%s will forage for items.",
}

PartyRoles.LINES = LINES

function PartyRoles.new(companion)
  return setmetatable({ companion = companion, injected = nil }, PartyRoles)
end

local function indexOf(list, label)
  for i, v in ipairs(list) do
    if v == label then return i end
  end
  return nil
end

--- Run after every PartyMenu.update.
function PartyRoles:onMenuUpdate(menu)
  if not (menu and menu.open and menu.mode == "action") then return end
  local list = menu.ACTIONS
  if type(list) ~= "table" or list == self.injected then return end
  -- only the overworld list: it has SUMMARY, CANCEL and ITEM (or MAIL when the
  -- Pokemon holds mail); a battle's lists and an egg's never have an ITEM row.
  -- (Ruby / Sapphire / Emerald put the field moves BEFORE SUMMARY, FireRed /
  -- LeafGreen after it, so the position of SUMMARY is not checked.)
  if not indexOf(list, "SUMMARY") or not indexOf(list, "CANCEL") then return end
  if not (indexOf(list, "ITEM") or indexOf(list, "MAIL")) then return end
  if EnginePatch.battleActive() then return end
  local mon = menu._party and menu._party[menu.cursor]
  if type(mon) ~= "table" or mon.isEgg or mon.egg then return end

  local labels = ROWS
  if #list + #ROWS > MAX_ROWS then labels = { COMPACT } end
  local at = indexOf(list, "SWITCH") or indexOf(list, "ITEM") or indexOf(list, "MAIL") or indexOf(list, "CANCEL")
  for i, label in ipairs(labels) do table.insert(list, at + i - 1, label) end
  self.injected = list

  menu._fieldMoveNames = menu._fieldMoveNames or {}
  for _, label in ipairs(labels) do menu._fieldMoveNames[label] = true end

  -- Ruby / Sapphire / Emerald draw each row through `actionText(action, fields)`
  -- every frame, which asserts that an action is a native one or listed in
  -- `fields.index`. Hand the menu a view of its field-move data that also knows
  -- our rows (everything else passes straight through to the real data).
  local fields = menu._fieldMoveData
  if type(fields) == "table" and type(fields.index) == "table" then
    local index = setmetatable({}, { __index = fields.index })
    for _, label in ipairs(labels) do index[label] = true end
    menu._fieldMoveData = setmetatable({ index = index }, { __index = fields })
  end

  -- the engine's own text lookup would assert on our labels: build the texts
  local own = {}
  for _, label in ipairs(labels) do own[label] = true end
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

--- FieldMoves.fromMenu's first look: a result table for our rows, else nil.
function PartyRoles:fromMenu(label, ctx)
  local role = ROLE_OF[label]
  if label == COMPACT then
    local current = self.companion:savedRole(ctx and ctx.mon) or "follow"
    role = NEXT[current]
  end
  if not role then return nil end
  local mon = ctx and ctx.mon
  if not mon or not self.companion:set(mon, role) then
    return { ok = false, text = "Nothing happened." }
  end
  return { ok = false, text = string.format(LINES[role], EnginePatch.displayName(mon)) }
end

return PartyRoles
