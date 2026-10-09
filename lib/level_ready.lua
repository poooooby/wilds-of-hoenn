-- What a companion is waiting for after it levels up while out in the world.
--
-- A Battler that levels up (lib/overworld_battle.lua) cannot open the engine's
-- learn-a-move or evolution screens mid-walk, so it asks instead: the moves it
-- would have learned at the levels it crossed, and whether it can now evolve, are
-- remembered per Pokemon. lib/follower_adapter.lua floats "New move ready!" /
-- "Ready to evolve!" over its head; the follower menu then offers a row that opens
-- the engine's own screen (lib/follower_interaction.lua).
--
-- Moves are remembered (a level-up moment passes), but they are checked against
-- what the Pokemon knows now, so one it learned elsewhere stops asking. Evolution
-- is only remembered when the Battler's own level-up made it possible, and kept
-- (the species it was recorded for) until the Pokemon actually evolves; it only
-- SHOWS while the engine offers a target right now, so an Everstone hides it and
-- taking the stone off brings it back. Nothing here depends on the Pokemon being
-- out: the state is keyed by personality, so it survives a battle, a map change,
-- recalling the Pokemon, swapping it out for another, depositing it in the PC and
-- taking it out again, and a save / load (mod.save, like lib/companion.lua).
-- Pure: the engine questions are injected (EnginePatch.movesLearnedAt /
-- knowsMove / evolutionTarget).
local LevelReady = {}
LevelReady.__index = LevelReady

local KEY = "level_ready/state"
LevelReady.MOVE_TEXT = "New move ready!"
LevelReady.EVOLVE_TEXT = "Ready to evolve!"

function LevelReady.new(mod, deps)
  return setmetatable({ mod = mod, deps = deps or {}, state = nil }, LevelReady)
end

function LevelReady:_load()
  if self.state then return end
  self.state = {}
  local save = self.mod and self.mod.save
  if not save then return end
  local ok, value = pcall(save.get, save, KEY)
  if ok and type(value) == "table" then
    for k, v in pairs(value) do
      if type(v) == "table" then
        local moves = {}
        for _, id in ipairs(type(v.moves) == "table" and v.moves or {}) do
          if tonumber(id) then moves[#moves + 1] = tonumber(id) end
        end
        self.state[tostring(k)] = { moves = moves, evolveFrom = tonumber(v.evolveFrom) }
      end
    end
  end
end

function LevelReady:_persist()
  local save = self.mod and self.mod.save
  if save then pcall(save.set, save, KEY, self.state) end
end

--- Forget the cached state (a save was loaded / a checkpoint restored).
function LevelReady:reset() self.state = nil end

local function keyOf(mon)
  if type(mon) ~= "table" or mon.personality == nil then return nil end
  return tostring(tonumber(mon.personality) or mon.personality)
end

local function speciesOf(mon)
  return tonumber(mon.species or mon.speciesId)
end

local function has(list, id)
  for _, v in ipairs(list) do if v == id then return true end end
  return false
end

--- `mon` just went from `fromLevel` to `toLevel`: remember the moves it would
--- have learned on the way and whether it can now evolve.
function LevelReady:record(mon, fromLevel, toLevel)
  local key = keyOf(mon)
  local from, to = tonumber(fromLevel), tonumber(toLevel)
  if not (key and from and to and to > from) then return end
  self:_load()
  local entry = self.state[key] or { moves = {} }
  local changed = false
  for level = from + 1, to do
    for _, id in ipairs(self.deps.movesLearnedAt and self.deps.movesLearnedAt(mon, level) or {}) do
      id = tonumber(id)
      if id and not has(entry.moves, id) and not (self.deps.knowsMove and self.deps.knowsMove(mon, id)) then
        entry.moves[#entry.moves + 1] = id
        changed = true
      end
    end
  end
  if not entry.evolveFrom and self.deps.evolutionTarget and self.deps.evolutionTarget(mon) then
    entry.evolveFrom, changed = speciesOf(mon) or 0, true
  end
  if changed then
    self.state[key] = entry
    self:_persist()
  end
end

--- What `mon` is waiting for now: `{ moves = {ids}, evolve = bool }`, or nil.
--- Drops what is no longer true first (a move it learned meanwhile, an evolution
--- it has since made). `evolve` is only true while the engine offers a target
--- right now (an Everstone holder has none, so it neither shows nor freezes EXP).
function LevelReady:pending(mon)
  local key = keyOf(mon)
  if not key then return nil end
  self:_load()
  local entry = self.state[key]
  if not entry then return nil end
  local changed = false
  local kept = {}
  for _, id in ipairs(entry.moves) do
    if self.deps.knowsMove and self.deps.knowsMove(mon, id) then changed = true else kept[#kept + 1] = id end
  end
  entry.moves = kept
  -- it evolved (its species is not the one that was waiting): that is done
  if entry.evolveFrom and entry.evolveFrom ~= 0 and speciesOf(mon) and speciesOf(mon) ~= entry.evolveFrom then
    entry.evolveFrom, changed = nil, true
  end
  if #entry.moves == 0 and not entry.evolveFrom then
    self.state[key] = nil
    self:_persist()
    return nil
  end
  if changed then self:_persist() end
  local evolve = entry.evolveFrom ~= nil and self.deps.evolutionTarget ~= nil
    and self.deps.evolutionTarget(mon) ~= nil
  if #entry.moves == 0 and not evolve then return nil end -- kept, but nothing to ask right now
  return { moves = entry.moves, evolve = evolve }
end

--- The text floating over the Pokemon, or nil. With both waiting it alternates
--- every `period` ticks (default 150), so neither is hidden.
function LevelReady:label(mon, tick, period)
  return LevelReady.textFor(self:pending(mon), tick, period)
end

--- The label for an already fetched `pending` entry (nil -> nil).
function LevelReady.textFor(p, tick, period)
  if not p then return nil end
  local wantsMove, wantsEvolve = #p.moves > 0, p.evolve
  if wantsMove and wantsEvolve then
    period = tonumber(period) or 150
    return (math.floor((tonumber(tick) or 0) / period) % 2 == 0) and LevelReady.EVOLVE_TEXT or LevelReady.MOVE_TEXT
  end
  return wantsEvolve and LevelReady.EVOLVE_TEXT or LevelReady.MOVE_TEXT
end

return LevelReady
