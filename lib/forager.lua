-- The Forager role: the companion roams around the player and finds items.
--
-- Only while the player is ACTIVELY MOVING, and only where foraging is allowed
-- (outside on a route, or in a cave -- never in a building, a town or a city, on
-- the water or in the Safari Zone: the adapter says so in `env.forageOk`):
--   near     trotting along within a tile of the player; after a short wait ->
--   out      runs to a spot 5-10 tiles from the player (an open cell, walked
--            cell by cell) ->
--   linger   sniffs about there a moment -> back
--   back     runs back to within a tile of the player -> near ...
-- Every 10-30 seconds of that walking the trip is a FORAGE instead of a wander:
-- at the spot the Pokemon digs (its animation) and has a 20% chance to turn up an
-- item: only THEN does it cry, to tell the player (the item goes into the bag with
-- a "Found X!" label). A dig that finds nothing is silent. Then it runs back to the
-- player quickly.
-- A standing player keeps it close: wanderers hurry back and nothing new starts
-- (a forage already under way is finished first -- it is only a few seconds). The
-- forage timer survives map changes; only the trip in progress is cancelled.
--
-- All motion is the same cosmetic draw-time offset the follower scenes and the
-- Battler use (the engine owns the follower's real position). The Forager keeps
-- its WORLD pixel position (`wx`, `wy`) and reports it as an offset from where
-- the follower is drawn, in the shared state shape:
--   { dx, dy, facing, moving, walkMul, bounce, idleSpeed, popup = { text, age } }
-- Pure: every engine fact (open cells, the cry, how an item is picked) is
-- injected through `deps`.
local V = ...
local Config = V.require("config")
local CellPath = V.require("cell_path")

local Forager = {}
Forager.__index = Forager

local CELL = 16

--- deps = {
---   cellFree(x, y) -> bool       a creature can stand there (dry, walkable, empty)
---   occupied(x, y) -> bool       optional: something of ours is there (a wild Pokemon)
---   rng() -> [0,1)               optional
---   pickItem() -> name | nil     roll, bag it, and return the name to announce
---   playCry(species)             optional: the cry when it finds something
---   playFound()                  optional sound
---   cfg                          optional (Config.FORAGE)
--- }
function Forager.new(deps)
  local self = setmetatable({ deps = deps or {} }, Forager)
  self.cfg = self.deps.cfg or Config.FORAGE
  self:reset()
  return self
end

function Forager:_rand(lo, hi)
  local r = self.deps.rng and self.deps.rng() or math.random()
  return lo + (hi - lo) * r
end

function Forager:_randInt(lo, hi)
  return math.floor(self:_rand(lo, hi + 1))
end

--- Back to trotting beside the player (map change, role change, save load).
function Forager:reset()
  self.mode, self.t = "near", 0
  self.wx, self.wy, self.dx, self.dy = nil, nil, 0, 0
  self.facing = nil
  self.path, self.idx = nil, 0
  self.purpose = nil
  self.forageTimer, self.forageGoal = 0, self:_randInt(self.cfg.forageMin, self.cfg.forageMax)
  self.wait = self:_randInt(self.cfg.wanderWaitMin, self.cfg.wanderWaitMax)
  self.popup, self.popupAge = nil, 0
end

--- A new map: the trip in progress is cancelled (the places it knew are gone) but
--- the forage timer carries on.
function Forager:mapChanged()
  self.mode, self.t = "near", 0
  self.wx, self.wy, self.dx, self.dy = nil, nil, 0, 0
  self.facing, self.path, self.idx, self.purpose = nil, nil, 0, nil
  self.popup, self.popupAge = nil, 0
end

--- Away from the player's side (the follower menu must not open on it then)?
function Forager:isBusy()
  return self.mode ~= "near" or self.dx ~= 0 or self.dy ~= 0
end

-- ------------------------------------------------------------ helpers

local function cheb(ax, ay, bx, by)
  return math.max(math.abs(ax - bx), math.abs(ay - by))
end

local function cellOf(w) return math.floor(w / CELL + 0.5) end

-- Moves (wx, wy) toward (tx, ty) by at most `speed` px, one axis at a time.
-- Returns true on arrival.
function Forager:_moveTo(tx, ty, speed)
  local ddx, ddy = tx - self.wx, ty - self.wy
  if ddx == 0 and ddy == 0 then return true end
  if ddx ~= 0 then
    self.wx = self.wx + math.max(-speed, math.min(speed, ddx))
    self.facing = ddx > 0 and "right" or "left"
  else
    self.wy = self.wy + math.max(-speed, math.min(speed, ddy))
    self.facing = ddy > 0 and "down" or "up"
  end
  return self.wx == tx and self.wy == ty
end

local function state(self, env, t)
  t.dx, t.dy = self.wx - env.fpx, self.wy - env.fpy
  self.dx, self.dy = t.dx, t.dy
  t.facing = t.facing or self.facing
  if self.popup then t.popup = { text = self.popup, age = self.popupAge } end
  return t
end

-- ------------------------------------------------------------ planning

-- Picks an open spot `minSpread`..`maxSpread` cells from the player (Chebyshev)
-- that can be walked to from where the Pokemon is, and starts out for it.
function Forager:_plan(env, purpose)
  local cfg, deps = self.cfg, self.deps
  local sx, sy = cellOf(self.wx), cellOf(self.wy)
  local res = CellPath.search(sx, sy, {
    maxDepth = cfg.maxWalk,
    free = function(x, y)
      return deps.cellFree(x, y) and not (deps.occupied and deps.occupied(x, y))
    end,
    within = function(x, y) return cheb(x, y, env.px, env.py) <= cfg.maxSpread + 1 end,
  })
  local spots = {}
  for _, c in ipairs(res.order) do
    local d = cheb(c[1], c[2], env.px, env.py)
    if d >= cfg.minSpread and d <= cfg.maxSpread then spots[#spots + 1] = c end
  end
  if #spots == 0 then return false end
  local pick = spots[self:_randInt(1, #spots)] or spots[#spots]
  local path = CellPath.pathTo(res, pick[1], pick[2])
  if not path or #path == 0 then return false end
  self.path, self.idx, self.purpose = path, 1, purpose
  self.mode, self.t = "out", 0
  return true
end

-- A way back to the player's side: the open cells from where it stands to the
-- follower's own cell (the last leg is a straight run).
function Forager:_planBack(env)
  local deps = self.deps
  local res = CellPath.search(cellOf(self.wx), cellOf(self.wy), {
    maxDepth = self.cfg.maxWalk * 2,
    free = function(x, y)
      return (x == env.fx and y == env.fy)
        or (deps.cellFree(x, y) and not (deps.occupied and deps.occupied(x, y)))
    end,
  })
  local path = CellPath.pathTo(res, env.fx, env.fy)
  self.path, self.idx = path or {}, 1
end

function Forager:_goBack(env)
  self.mode, self.t = "back", 0
  self:_planBack(env)
end

-- ------------------------------------------------------------ the tick

--- One field tick. `env` = { still = player and follower standing still, fx, fy =
--- the follower's cell, fpx, fpy = where it is drawn (px), px, py = the player's
--- cell, mon = the Pokemon }. Returns the state to draw, or nil while it simply
--- trots beside the player.
function Forager:step(env)
  env = env or {}
  local cfg = self.cfg
  if not (env.fpx and env.px) then return nil end
  local allowed = env.forageOk ~= false
  local active = not env.still and allowed -- walking, somewhere it may work
  if not self.wx then self.wx, self.wy = env.fpx, env.fpy end
  self.t = self.t + 1
  if active then self.forageTimer = self.forageTimer + 1 end

  if self.popup then
    self.popupAge = self.popupAge + 1
    if self.popupAge >= cfg.popupTicks then self.popup = nil end
  end

  local handler = self["_mode_" .. self.mode]
  return handler(self, env, active)
end

function Forager:_mode_near(env, active)
  local cfg = self.cfg
  self.wx, self.wy = env.fpx, env.fpy
  self.dx, self.dy, self.facing = 0, 0, nil
  if active then
    if self.forageTimer >= self.forageGoal then
      if self:_plan(env, "forage") then
        self.forageTimer = 0
        self.forageGoal = self:_randInt(cfg.forageMin, cfg.forageMax)
        return self:_mode_out(env, active)
      end
      self.forageTimer = self.forageGoal - 60 -- nowhere to go yet: look again in a second
    end
    self.wait = self.wait - 1
    if self.wait <= 0 then
      if self:_plan(env, "wander") then return self:_mode_out(env, active) end
      self.wait = self:_randInt(cfg.wanderWaitMin, cfg.wanderWaitMax)
    end
  end
  if self.popup then return state(self, env, { moving = false }) end
  return nil
end

function Forager:_mode_out(env, active)
  local cfg = self.cfg
  -- a wander is dropped the moment the player stops; a forage is finished
  if self.purpose == "wander" and not active then
    self:_goBack(env)
    return self:_mode_back(env, active)
  end
  local forage = self.purpose == "forage"
  local c = self.path[self.idx]
  if self:_moveTo(c[1] * CELL, c[2] * CELL, forage and cfg.forageSpeed or cfg.walkSpeed) then
    if self.idx >= #self.path then
      if forage then
        self.mode, self.t = "dig", 0
      else
        self.mode, self.t = "linger", 0
        self.lingerFor = self:_randInt(cfg.lingerMin, cfg.lingerMax)
      end
    else
      self.idx = self.idx + 1
    end
  end
  return state(self, env, { moving = true, walkMul = forage and 2 or 1 })
end

function Forager:_mode_linger(env, active)
  if not active or self.t >= self.lingerFor then
    self:_goBack(env)
    return self:_mode_back(env, active)
  end
  return state(self, env, { moving = false })
end

-- it found something: the cry (to tell the player), a moment, then back
function Forager:_mode_cry(env)
  local cfg = self.cfg
  if self.t >= cfg.cryPause then
    self:_goBack(env)
    return self:_mode_back(env, true)
  end
  return state(self, env, { moving = false })
end

function Forager:_mode_dig(env)
  local cfg = self.cfg
  if self.t >= cfg.digTicks then
    local roll = self.deps.rng and self.deps.rng() or math.random()
    local name = (roll < cfg.findChance and self.deps.pickItem) and self.deps.pickItem() or nil
    if name then
      self.popup, self.popupAge = "Found " .. tostring(name) .. "!", 0
      if self.deps.playFound then self.deps.playFound() end
      if self.deps.playCry and env.mon then self.deps.playCry(env.mon.species) end
      self.mode, self.t = "cry", 0
      return state(self, env, { moving = false })
    end
    self:_goBack(env) -- nothing here: no cry, just back
    return self:_mode_back(env, true)
  end
  return state(self, env, { moving = false, bounce = true, idleSpeed = 1.5 })
end

-- run back to within a tile of the player
function Forager:_mode_back(env)
  local cfg = self.cfg
  local path = self.path
  -- along the open cells first, then straight at the follower
  if path and self.idx <= #path then
    local c = path[self.idx]
    if self:_moveTo(c[1] * CELL, c[2] * CELL, cfg.runSpeed) then self.idx = self.idx + 1 end
  else
    if self:_moveTo(env.fpx, env.fpy, cfg.runSpeed) then
      self.mode, self.t = "near", 0
      self.wait = self:_randInt(cfg.wanderWaitMin, cfg.wanderWaitMax)
      self.dx, self.dy, self.facing, self.path = 0, 0, nil, nil
      return state(self, env, { moving = false })
    end
    -- the player keeps walking: keep the run aimed at them
    if (math.abs(env.fpx - self.wx) > CELL * 2 or math.abs(env.fpy - self.wy) > CELL * 2)
        and (self.t % 30) == 0 then
      self:_planBack(env)
    end
  end
  return state(self, env, { moving = true, walkMul = 2 })
end

return Forager
