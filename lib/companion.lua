-- Which party Pokemon is out in the overworld, and what it is doing.
--
-- Scarlet / Violet style: any party member can be sent out with a job --
--   follow  the standard follower (Pet / Play / Talk menu, scenes)
--   battle  fights wild overworld Pokemon near the player (lib/overworld_battle.lua)
--   forage  sniffs out items for the player while they walk (lib/forager.lua)
--   recall  not a job: the Pokemon is shrunk into the player and stays there
--           until a job is chosen again (from the party menu or by talking to it)
-- Only one companion is out at a time (the engine supports a single follower).
--
-- The choice is saved with the save file (mod.save), identified by the
-- Pokemon's personality value (stable across party reordering, box moves and
-- evolution). When nothing was chosen, or the chosen Pokemon is gone, fainted
-- or an egg, the lead healthy Pokemon follows -- exactly the old behaviour.
--
-- A new lead takes over: when a different Pokemon is put first in the party, it becomes
-- the follower (role follow), whatever was out before -- the way the lead walks behind
-- you in the games. The player can still pick another one (or another job) in the party
-- menu; that stands until the lead changes again. The lead is remembered in the save
-- (`lead`, its personality), so loading a save or reordering the rest of the party
-- changes nothing; moving the companion itself to the front keeps its job.
-- Pure: the party is passed in, nothing here touches the engine.
local Companion = {}
Companion.__index = Companion

Companion.ROLES = { "follow", "battle", "forage" } -- the jobs; "recall" is the absence of one
local VALID = { follow = true, battle = true, forage = true, recall = true }
local KEY = "companion/state"

local function healthy(mon)
  return type(mon) == "table" and not mon.isEgg and not mon.egg
    and (tonumber(mon.hp) or tonumber(mon.currentHp) or 1) > 0
end

function Companion.new(mod)
  return setmetatable({ mod = mod, state = nil, loaded = false }, Companion)
end

function Companion:_load()
  if self.loaded then return end
  self.loaded = true
  self.state = nil
  local save = self.mod and self.mod.save
  if not save then return end
  local ok, value = pcall(save.get, save, KEY)
  if ok and type(value) == "table" and VALID[value.role] and tonumber(value.personality) then
    self.state = { role = value.role, personality = tonumber(value.personality),
                   species = tonumber(value.species), lead = tonumber(value.lead) }
  end
end

function Companion:_persist()
  local save = self.mod and self.mod.save
  if save then pcall(save.set, save, KEY, self.state) end
end

--- Forget the cached state (a save was loaded / a checkpoint restored): the
--- next call re-reads it from the save.
function Companion:reset()
  self.loaded, self.state = false, nil
end

--- Make `mon` the companion with `role`. Returns false for a bad role / mon.
function Companion:set(mon, role)
  if not VALID[role] or type(mon) ~= "table" or mon.personality == nil then return false end
  self:_load()
  local lead = self.state and self.state.lead
  self.state = { role = role, personality = tonumber(mon.personality) or 0,
                 species = tonumber(mon.species), lead = lead }
  self:_persist()
  return true
end

-- A different Pokemon was put first in the party: it becomes the follower (see the
-- header). The first lead ever seen (an old save, a new game) is only remembered.
function Companion:_followLead(party)
  local lead = type(party) == "table" and party[1]
  local p = type(lead) == "table" and tonumber(lead.personality)
  if not p or not healthy(lead) then return end
  local s = self.state
  if s and s.lead == p then return end
  if not s then
    self.state = { role = "follow", personality = p, species = tonumber(lead.species), lead = p }
  elseif s.lead == nil or s.personality == p then
    s.lead = p -- first sight of a lead, or the companion itself moved to the front: its job stands
  else
    self.state = { role = "follow", personality = p, species = tonumber(lead.species), lead = p }
  end
  self:_persist()
end

--- The role the saved companion has (nil when none was ever chosen).
function Companion:savedRole(mon)
  self:_load()
  local s = self.state
  if s and mon and tonumber(mon.personality) == s.personality then return s.role end
  return nil
end

--- The companion in `party` (a plain list): `mon, role`. Falls back to the first
--- healthy non-egg Pokemon on `follow`.
function Companion:resolve(party)
  self:_load()
  self:_followLead(party)
  local s = self.state
  if s and type(party) == "table" then
    for _, mon in ipairs(party) do
      if healthy(mon) and tonumber(mon.personality) == s.personality then
        return mon, s.role
      end
    end
  end
  if type(party) == "table" then
    for _, mon in ipairs(party) do
      if healthy(mon) then return mon, "follow" end
    end
  end
  return nil, "follow"
end

return Companion
