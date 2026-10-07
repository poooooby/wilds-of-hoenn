-- The little scene a follower plays for each menu action, before the result
-- message and portrait:
--
--   play  the player throws a ball, the follower runs to it, spins in a circle
--         and runs back
--   pet   the follower plays its Idle animation, then its cry
--   talk  the follower cries twice in a row
--
-- Pure: a tick-driven timeline with no engine access (the cry and the "has it
-- finished" test are injected), so it is testable on its own. Everything it
-- produces is COSMETIC -- a pixel offset, a facing and an animation request for
-- the follower's renderer, plus the ball's position -- because the engine owns
-- the follower's real position (see lib/follower_adapter.lua).
--
--   local act = FollowerActions.new("play", { facing = "down", cellsAhead = 2,
--                 playCry = ..., cryFinished = ... })
--   local state = act:step()   -- once per tick; nil when the scene is over
--
-- `state` = {
--   dx, dy      follower offset in px from its own tile
--   facing      facing to draw instead of the engine's (nil = leave it)
--   moving      play the Walk animation (true) or stand (false)
--   bounce      stand-in Idle for art without one (HGSS): the idle-flap cycle
--   idleSpeed   Idle clock rate while `bounce`/idle is wanted
--   ball        { x, y, z } px relative to the follower's tile, or nil
-- }
local V = ...
local Config = V.require("config")

local FollowerActions = {}
FollowerActions.__index = FollowerActions

local CELL = 16
local DELTA = { up = { 0, -1 }, down = { 0, 1 }, left = { -1, 0 }, right = { 1, 0 } }
local OPPOSITE = { up = "down", down = "up", left = "right", right = "left" }
-- one full turn on the spot, in the order a person would turn
local TURN = { "down", "left", "up", "right" }

local function turnIndex(facing)
  for i, f in ipairs(TURN) do
    if f == facing then return i end
  end
  return 1
end

function FollowerActions.new(kind, ctx)
  ctx = ctx or {}
  local cfg = ctx.cfg or Config.ACTIONS
  local self = setmetatable({
    kind = kind, ctx = ctx, cfg = cfg, t = 0, finished = false,
  }, FollowerActions)
  if kind == "play" then
    self:_planPlay()
  elseif kind == "pet" then
    self:_planPet()
  elseif kind == "talk" then
    self:_planTalk()
  else
    self.finished = true
  end
  return self
end

function FollowerActions:isFinished()
  return self.finished
end

-- ------------------------------------------------------------------- play

function FollowerActions:_planPlay()
  local c = self.cfg.play
  local facing = DELTA[self.ctx.facing] and self.ctx.facing or "down"
  local ahead = math.max(0, math.floor(tonumber(self.ctx.cellsAhead) or 0))
  ahead = math.min(ahead, math.max(0, (c.ballDist or 3) - 1))
  -- no room beyond the follower: the ball drops just past it
  local landPx = ahead >= 1 and ahead * CELL or CELL / 2
  local run = math.max(1, math.ceil(landPx / c.runSpeed))
  local spt = math.max(1, c.spinTicksPerFacing)
  local spin = math.max(1, math.floor((c.spins or 1) * 4 * spt))
  self.play = {
    facing = facing, d = DELTA[facing], landPx = landPx,
    throw = c.throwTicks, run = run, spin = spin, spt = spt,
    startTurn = turnIndex(facing),
  }
  self.play.total = c.throwTicks + run + spin + run
end

local function lerp(a, b, u) return a + (b - a) * u end

function FollowerActions:_stepPlay(t)
  local p, c = self.play, self.cfg.play
  local d = p.d
  if t > p.total then return nil end
  local state = { moving = false }

  local t1 = p.throw
  local t2 = t1 + p.run
  local t3 = t2 + p.spin
  if t <= t1 then
    -- throw: the ball leaves the player's tile (one tile behind the follower)
    -- and arcs out to where it lands
    local u = t / t1
    local x0, x1 = -CELL * d[1], p.landPx * d[1]
    local y0, y1 = -CELL * d[2], p.landPx * d[2]
    state.ball = {
      x = lerp(x0, x1, u), y = lerp(y0, y1, u),
      z = lerp(10, 0, u) + c.arcHeight * 4 * u * (1 - u),
    }
  elseif t <= t2 then
    local i = t - t1
    local dist = math.min(p.landPx, i * c.runSpeed)
    state.dx, state.dy = d[1] * dist, d[2] * dist
    state.facing, state.moving = p.facing, true
    if i < p.run then state.ball = { x = d[1] * p.landPx, y = d[2] * p.landPx, z = 0 } end
  elseif t <= t3 then
    local i = t - t2 - 1
    state.dx, state.dy = d[1] * p.landPx, d[2] * p.landPx
    state.facing = TURN[(p.startTurn - 1 + math.floor(i / p.spt)) % 4 + 1]
    state.moving = true
  else
    local i = t - t3
    local dist = math.max(0, p.landPx - i * c.runSpeed)
    state.dx, state.dy = d[1] * dist, d[2] * dist
    state.facing, state.moving = OPPOSITE[p.facing], true
  end
  return state
end

-- -------------------------------------------------------------------- pet

function FollowerActions:_planPet()
  local c = self.cfg.pet
  local idle = tonumber(self.ctx.idleTicks) or c.maxIdleTicks
  local speed = c.idleSpeed or 1
  -- one Idle loop at its sped-up rate, never too brief to see or too long
  local ticks = math.floor(idle / speed)
  ticks = math.max(c.minIdleTicks or 1, math.min(c.maxIdleTicks or ticks, ticks))
  self.pet = { idleTicks = ticks, speed = speed, cried = false, waited = 0 }
end

function FollowerActions:_stepPet(_t)
  local p = self.pet
  if p.idleTicks > 0 then
    p.idleTicks = p.idleTicks - 1
    return { moving = false, bounce = true, idleSpeed = p.speed }
  end
  if not p.cried then
    p.cried = true
    if self.ctx.playCry then self.ctx.playCry() end
    return { moving = false, bounce = true, idleSpeed = p.speed }
  end
  p.waited = p.waited + 1
  local done = self.ctx.cryFinished and self.ctx.cryFinished()
  if done ~= false or p.waited >= self.cfg.talk.cryTimeout then return nil end
  return { moving = false }
end

-- ------------------------------------------------------------------- talk

function FollowerActions:_planTalk()
  self.talk = { n = 0, phase = "start", waited = 0, gap = 0 }
end

function FollowerActions:_stepTalk(_t)
  local s, c = self.talk, self.cfg.talk
  local state = { moving = false }
  if s.phase == "start" then
    if s.n >= (c.cries or 3) then return nil end
    s.n = s.n + 1
    s.waited = 0
    s.phase = "cry"
    if self.ctx.playCry then self.ctx.playCry() end
    return state
  elseif s.phase == "cry" then
    s.waited = s.waited + 1
    local done = self.ctx.cryFinished and self.ctx.cryFinished()
    if done ~= false or s.waited >= c.cryTimeout then
      s.phase, s.gap = "gap", c.gap or 0
    end
    return state
  end
  -- gap before the next cry
  if s.gap > 0 then
    s.gap = s.gap - 1
    return state
  end
  s.phase = "start"
  return self:_stepTalk(_t)
end

-- ------------------------------------------------------------------- tick

--- One field tick. Returns the state to draw this tick, or nil once over.
function FollowerActions:step()
  if self.finished then return nil end
  self.t = self.t + 1
  local state
  if self.t > (self.cfg.maxTicks or 900) then
    state = nil
  elseif self.kind == "play" then
    state = self:_stepPlay(self.t)
  elseif self.kind == "pet" then
    state = self:_stepPet(self.t)
  elseif self.kind == "talk" then
    state = self:_stepTalk(self.t)
  end
  if state == nil then self.finished = true end
  return state
end

-- -------------------------------------------------------------------- ball

--- The ball as a field actor, positioned from the follower's own tile pixel
--- (`ox`, `oy`) -- the same shape lib/grass_cover.lua appends.
function FollowerActions.ballActor(ball, ox, oy, elevation)
  if not ball then return nil end
  local gx, gy = ox + CELL / 2 + ball.x, oy + CELL / 2 + ball.y
  return {
    kind = "follower_action_ball",
    elevation = elevation or 3,
    sortY = gy + 0.5,
    x = gx, y = gy,
    i = 90500,
    draw = function(_, camX, camY)
      FollowerActions.drawBall(gx - camX, gy - camY, ball.z)
    end,
  }
end

--- A small Poke Ball: ground shadow, red top, white bottom, dark outline.
--- (sx, sy) is the point on the ground under it; `z` the height in px.
function FollowerActions.drawBall(sx, sy, z)
  if not (love and love.graphics and love.graphics.circle) then return end
  local g = love.graphics
  sx, sy = math.floor(sx + 0.5), math.floor(sy + 0.5)
  local lift = math.floor((z or 0) + 0.5)
  local r = 3
  local cy = sy - lift - r
  g.setColor(0, 0, 0, math.max(0.12, 0.35 - lift * 0.01))
  g.ellipse("fill", sx, sy, 3, 1.5)
  g.setColor(0.86, 0.12, 0.12, 1)
  g.arc("fill", "closed", sx, cy, r, math.pi, 2 * math.pi)
  g.setColor(1, 1, 1, 1)
  g.arc("fill", "closed", sx, cy, r, 0, math.pi)
  g.setColor(0.1, 0.1, 0.12, 1)
  g.circle("line", sx, cy, r)
  g.line(sx - r, cy, sx + r, cy)
  g.setColor(1, 1, 1, 1)
end

return FollowerActions
