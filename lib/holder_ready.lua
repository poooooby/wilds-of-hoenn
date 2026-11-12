-- Exp. Share holders' level-ups, followed through on the spot.
--
-- A party member holding an Exp. Share levels up from the Battler's overworld wins
-- (lib/overworld_battle.lua), but it is not out on the field: no "New move ready!" label
-- over it, no talk menu to open its screens from. So once the fight is over and the game
-- is free, this opens the same engine screens the partner's menu does
-- (lib/follower_interaction.lua openScreen) for it: its evolution scene first, then the
-- move relearner with the moves it skipped. What the player turns down is dismissed the
-- same way (LevelReady:dismiss), so its EXP flows again.
--
-- deps = { canOpen(), partyMons(), evolutionTarget(mon), startEvolution(mon, target, done),
--          startMoveLearn(mon, moveIds, done), screenBusy() }
local HolderReady = {}
HolderReady.__index = HolderReady

-- a screen that closed without calling back (the field running again this long) is done
HolderReady.STALE_TICKS = 30

function HolderReady.new(levelReady, deps)
  local self = setmetatable({ levelReady = levelReady, deps = deps or {} }, HolderReady)
  self:reset()
  return self
end

--- Drops the queue and any screen it waits on (a save loaded: the party is another one).
--- What each Pokemon waits for stays in LevelReady.
function HolderReady:reset()
  self.queue, self.current, self.step, self.waiting, self.stale = {}, nil, nil, false, 0
end

--- `mon` levelled up from its Exp. Share: look after it when the game is free.
function HolderReady:push(mon)
  if type(mon) ~= "table" then return end
  if self.current == mon then return end
  for _, m in ipairs(self.queue) do if m == mon then return end end
  self.queue[#self.queue + 1] = mon
end

--- Anything queued or open?
function HolderReady:busy()
  return self.current ~= nil or #self.queue > 0
end

local function inParty(deps, mon)
  local party = deps.partyMons and deps.partyMons()
  if type(party) ~= "table" then return true end -- cannot tell: assume it is
  for _, m in ipairs(party) do if m == mon then return true end end
  return false
end

-- Opens the next screen `self.current` is waiting for, from `self.step` on. True when one
-- opened (wait for it), false when there is nothing (more) to open for it.
function HolderReady:_openNext()
  local mon, deps, lr = self.current, self.deps, self.levelReady
  while self.step do
    local pending = lr:pending(mon)
    if not pending then return false end
    local kind = self.step
    self.step = (kind == "evolve") and "move" or nil
    local function done()
      lr:dismiss(mon, kind)
      self.waiting = false
    end
    local opened = false
    if kind == "evolve" then
      local target = pending.evolve and deps.evolutionTarget and deps.evolutionTarget(mon)
      if target and deps.startEvolution then opened = deps.startEvolution(mon, target, done) == true end
    elseif #pending.moves > 0 and deps.startMoveLearn then
      opened = deps.startMoveLearn(mon, pending.moves, done) == true
    end
    if opened then
      self.waiting, self.stale = true, 0
      return true
    end
  end
  return false
end

--- Once per field tick.
function HolderReady:tick()
  local deps = self.deps
  if self.waiting then
    -- the scene owns the screen; if it is gone without saying so, carry on
    if deps.screenBusy and deps.screenBusy() then
      self.stale = 0
    else
      self.stale = self.stale + 1
      if self.stale >= HolderReady.STALE_TICKS then self.waiting = false end
    end
    return
  end
  if not (deps.canOpen and deps.canOpen()) then return end
  if self.current then
    -- its next screen (the moves after an evolution), or it is finished
    if self.step and self:_openNext() then return end
    self.current, self.step = nil, nil
    return
  end
  while #self.queue > 0 do
    local mon = table.remove(self.queue, 1)
    if inParty(deps, mon) and self.levelReady:pending(mon) then
      self.current, self.step = mon, "evolve"
      if self:_openNext() then return end
      self.current, self.step = nil, nil
    end
  end
end

return HolderReady
