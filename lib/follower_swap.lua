-- The "trainer swaps Pokemon" scene: when the companion changes (another
-- Pokemon, another job, or a recall), the player raises a Poke Ball in one
-- hand, the old companion shrinks into them, and -- unless it was a recall --
-- raises the ball again and the new one grows out.
--
--   recall phase  ball up; after `recallDelay` ticks the old companion shrinks
--   send phase    ball up again; after `sendDelay` ticks the new one grows out
--                 (and cries)
--
-- Pure: a tick-driven timeline. The adapter (lib/follower_adapter.lua) mirrors
-- each tick's state onto the player pose, the ball actor and the renderer.
--
--   local swap = FollowerSwap.new({ hasOld = true, hasNew = true })
--   local s = swap:step()   -- once per tick; nil when the scene is over
--
-- `s` = {
--   phase   "recall" | "send"
--   pose    true on the first tick of a phase: raise the player's arm now
--   ball    { x, y, z } px relative to the centre of the player's tile (y 8 sorts
--           it in front of them), or nil
--   want    1 = the displayed companion should be out, 0 = inside the player
--   switch  true on the tick the displayed companion becomes the new one
--   cry     true on the tick the new companion appears
-- }
local V = ...
local Config = V.require("config")

local FollowerSwap = {}
FollowerSwap.__index = FollowerSwap

function FollowerSwap.new(ctx)
  ctx = ctx or {}
  local cfg = ctx.cfg or Config.SWAP
  local self = setmetatable({ cfg = cfg, t = 0, finished = false, phases = {} }, FollowerSwap)
  local len = math.max(cfg.poseTicks, cfg.recallDelay + Config.PMD_RECALL_TICKS + 2)
  local lenIn = math.max(cfg.poseTicks, cfg.sendDelay + Config.PMD_RECALL_TICKS + 2)
  if ctx.hasOld then self.phases[#self.phases + 1] = { name = "recall", len = len } end
  if ctx.hasNew then self.phases[#self.phases + 1] = { name = "send", len = lenIn } end
  self.index, self.phaseT = 1, 0
  if #self.phases == 0 then self.finished = true end
  return self
end

function FollowerSwap:isFinished()
  return self.finished
end

--- True when the run has a send phase (the new companion grows out).
function FollowerSwap:hasSend()
  for _, p in ipairs(self.phases) do
    if p.name == "send" then return true end
  end
  return false
end

function FollowerSwap:step()
  if self.finished then return nil end
  self.t = self.t + 1
  if self.t > self.cfg.maxTicks then
    self.finished = true
    return nil
  end
  local phase = self.phases[self.index]
  if self.phaseT >= phase.len then
    self.index, self.phaseT = self.index + 1, 0
    phase = self.phases[self.index]
    if not phase then
      self.finished = true
      return nil
    end
  end
  local first = self.phaseT == 0
  self.phaseT = self.phaseT + 1
  local pt = self.phaseT
  local state = {
    phase = phase.name, pose = first,
    ball = { x = self.cfg.ballX, y = 8, z = self.cfg.ballLift },
  }
  if phase.name == "recall" then
    state.want = pt <= self.cfg.recallDelay and 1 or 0
  else
    state.want = pt <= self.cfg.sendDelay and 0 or 1
    state.switch = first
    state.cry = pt == self.cfg.sendDelay + 1
  end
  -- the ball drops out of the hand once the shrink / grow has begun
  local delay = phase.name == "recall" and self.cfg.recallDelay or self.cfg.sendDelay
  if pt > delay + 4 then state.ball = nil end
  return state
end

return FollowerSwap
