-- The partner going into or coming out of its Poke Ball on purpose (the party switch, the
-- Follower option, a Battler resting): a ball drops behind the player.
--
--   out  the ball falls onto the partner's spot, bounces once, pops (the Ball Poof sound, a
--        white ring) and the Pokemon grows out of it as the ball fades
--   in   the ball falls onto the Pokemon, pops, the Pokemon shrinks into it as the ball
--        settles on the ground, rests a moment and fades
--
-- Pure: a tick-driven timeline (Config.BALL). lib/follower_adapter.lua copies each tick's
-- state onto the renderer (`recall`: 0 inside .. 1 out, scaled about its feet, which is where
-- the ball lands) and draws the ball (lib/follower_actions.lua ballActor).
--
--   local run = BallDrop.new("out")
--   local s = run:step()  -- once per tick; nil when it is over
--
-- `s` (one table per run, refilled every tick: read it, never keep it) = {
--   recall  the Pokemon's size, 0 = inside .. 1 = out
--   ball    { x, y, z, alpha, burst }: px from the centre of the partner's tile (y 8 = its
--           feet), the height above the ground, 0..1 opacity, and the pop ring's 0..1 age
--           (nil: no ring)
--   poof    true on the tick the ball pops (play the sound)
-- }
local V = ...
local Config = V.require("config")
local RecallMath = V.require("recall_math")

local BallDrop = {}
BallDrop.__index = BallDrop

local function cfgOf(cfg) return cfg or Config.BALL end

--- How many ticks a run lasts.
function BallDrop.length(dir, cfg)
  local c = cfgOf(cfg)
  if dir == "in" then return c.fallIn + c.shrink + c.rest + c.fade end
  return c.fall + c.bounce + c.grow
end

--- The tick the ball pops (the sound; for "out", the Pokemon's first frame out).
function BallDrop.popAt(dir, cfg)
  local c = cfgOf(cfg)
  if dir == "in" then return c.fallIn + 1 end
  return c.fall + c.bounce + 1
end

function BallDrop.new(dir, cfg)
  local self = setmetatable({ dir = dir == "in" and "in" or "out", cfg = cfgOf(cfg), t = 0 }, BallDrop)
  self.len = BallDrop.length(self.dir, self.cfg)
  self.ball = { x = 0, y = 8, z = 0, alpha = 1, burst = nil }
  self.state = { recall = self.dir == "in" and 1 or 0, ball = self.ball, poof = false }
  return self
end

function BallDrop:isFinished() return self.t >= self.len end

-- the pop ring's age at `since` ticks after the pop (1 = the pop tick), nil once it is gone
local function burstAt(c, since)
  local age = (since - 1) / math.max(1, c.burst)
  return age < 1 and age or nil
end

function BallDrop:step()
  if self.t >= self.len then return nil end
  self.t = self.t + 1
  local t, c, s, b = self.t, self.cfg, self.state, self.ball
  s.poof, b.z, b.alpha, b.burst = false, 0, 1, nil
  if self.dir == "out" then
    s.recall = 0
    if t <= c.fall then
      local u = t / c.fall
      b.z = c.dropZ * (1 - u * u) -- falling faster and faster onto the ground
    elseif t <= c.fall + c.bounce then
      b.z = c.bounceH * math.sin(math.pi * (t - c.fall) / c.bounce)
    else
      local g = t - c.fall - c.bounce
      s.poof = g == 1
      s.recall = RecallMath.ease(g / c.grow)
      b.alpha = 1 - g / c.grow
      b.burst = burstAt(c, g)
    end
  else
    s.recall = 1
    if t <= c.fallIn then
      local u = t / c.fallIn
      b.z = c.dropZIn - (c.dropZIn - c.hitZ) * u * u
    elseif t <= c.fallIn + c.shrink then
      local k = t - c.fallIn
      s.poof = k == 1
      s.recall = 1 - RecallMath.ease(k / c.shrink)
      b.z = c.hitZ * (1 - RecallMath.ease(k / c.shrink))
      b.burst = burstAt(c, k)
    else
      s.recall = 0
      local f = t - c.fallIn - c.shrink - c.rest
      if f > 0 then b.alpha = 1 - f / c.fade end
      local k = t - c.fallIn
      b.burst = burstAt(c, k)
    end
  end
  return s
end

return BallDrop
