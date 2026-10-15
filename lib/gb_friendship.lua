-- Friendship on the Game Boy games, which keep no such stat (Gen 1; Gen 2's real
-- happiness byte is a later wiring). The mod keeps its own 0..255 per Pokemon in
-- mod.save, keyed by species and DVs (stable for a mon's whole life, no personality
-- exists), seeded at SEED like a Gen 2 wild catch. Pet / Play / Talk move it
-- (lib/follower_interaction.lua through EnginePatch.setFriendship), and walking with a
-- lead raises it slowly (onStep, +1 every STEP_EVERY steps, the Gen 2 pace).
--
-- Yellow's starter Pikachu is special: the game has a REAL happiness byte
-- (save.pikachuHappiness, seeded 90) driving its faces, so for a PIKACHU while that
-- byte exists, reads and writes go straight to it -- the mod never shadows the game's
-- own stat.
--
-- valueOf also mirrors the value onto the live mon table (`mon.happiness`), which is
-- the field lib/mon_mood.lua reads, so moods and portraits need no special casing.
local V = ...
local GbFriendship = {}
GbFriendship.__index = GbFriendship

GbFriendship.SEED = 70
GbFriendship.STEP_EVERY = 256
local KEY = "gb_friendship"
local MAX = 255

function GbFriendship.new(mod, saveFor)
  return setmetatable({
    mod = mod,
    -- saveFor() -> the game's save table (Yellow's pikachuHappiness lives there)
    saveFor = saveFor,
    store = nil, steps = 0,
  }, GbFriendship)
end

--- A mon's stable key: species and DVs (hex), e.g. "PIKACHU:fa93". No DVs -> species.
function GbFriendship.keyOf(mon)
  if type(mon) ~= "table" or mon.species == nil then return nil end
  local d = mon.dvs
  local dv = 0
  if type(d) == "table" then
    dv = (tonumber(d.attack) or 0) * 4096 + (tonumber(d.defense) or 0) * 256
      + (tonumber(d.speed) or 0) * 16 + (tonumber(d.special) or 0)
  elseif tonumber(d) then
    dv = tonumber(d)
  end
  return tostring(mon.species) .. ":" .. string.format("%04x", dv % 65536)
end

-- Yellow's own happiness byte stands in for its starter Pikachu
local function yellowSave(self, mon)
  if type(mon) ~= "table" or mon.species ~= "PIKACHU" then return nil end
  local save = self.saveFor and self.saveFor()
  if type(save) == "table" and tonumber(save.pikachuHappiness) then return save end
  return nil
end

function GbFriendship:_load()
  if self.store then return self.store end
  local save = self.mod and self.mod.save
  local ok, value = false, nil
  if save then ok, value = pcall(save.get, save, KEY) end -- (both returns: `a and f()` keeps one)
  self.store = (ok and type(value) == "table") and value or {}
  return self.store
end

function GbFriendship:_persist()
  local save = self.mod and self.mod.save
  if save then pcall(save.set, save, KEY, self.store) end
end

--- Forget the cached table (a save was loaded): the next read starts over.
function GbFriendship:reset()
  self.store, self.steps = nil, 0
end

--- The mon's friendship 0..255 (seeded SEED the first time it is asked about).
--- Mirrored onto `mon.happiness` for lib/mon_mood.lua.
function GbFriendship:valueOf(mon)
  local ys = yellowSave(self, mon)
  if ys then
    local v = math.max(0, math.min(MAX, tonumber(ys.pikachuHappiness) or GbFriendship.SEED))
    mon.happiness = v
    return v
  end
  local key = GbFriendship.keyOf(mon)
  if not key then return 0 end
  local store = self:_load()
  local v = tonumber(store[key])
  if v == nil then
    v = GbFriendship.SEED
    store[key] = v
    self:_persist()
  end
  v = math.max(0, math.min(MAX, v))
  mon.happiness = v
  return v
end

--- Sets it (clamped 0..255); returns the new value.
function GbFriendship:set(mon, value)
  local v = math.max(0, math.min(MAX, math.floor(tonumber(value) or 0)))
  local ys = yellowSave(self, mon)
  if ys then
    ys.pikachuHappiness = v
    mon.happiness = v
    return v
  end
  local key = GbFriendship.keyOf(mon)
  if not key then return 0 end
  local store = self:_load()
  store[key] = v
  mon.happiness = v
  self:_persist()
  return v
end

--- A step walked with `lead` out front: +1 every STEP_EVERY steps (Yellow's Pikachu has
--- the game's own walking gains; leave its byte to the engine).
function GbFriendship:onStep(lead)
  if type(lead) ~= "table" then return end
  if yellowSave(self, lead) then return end
  self.steps = self.steps + 1
  if self.steps < GbFriendship.STEP_EVERY then return end
  self.steps = 0
  local v = self:valueOf(lead)
  if v < MAX then self:set(lead, v + 1) end
end

return GbFriendship
