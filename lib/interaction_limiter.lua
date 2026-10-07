-- Rate limit and abuse cut-off for the follower interaction menu
-- (lib/follower_interaction.lua). Pure: time comes from an injected clock and
-- the saved state goes through an injected store, so it is directly
-- unit-testable and knows nothing about the engine.
--
-- Three layers, all measured in real seconds:
--   1. per-action COOLDOWN   -- Pet/Play/Talk each need a gap since the last
--      one that worked; asking early is refused ("not in the mood").
--   2. WINDOW budget         -- at most `maxGains` successful interactions in
--      a rolling `window`; past that the Pokemon is "tired of attention".
--   3. ABUSE lock-out        -- every action the player SELECTS counts as an
--      attempt, refused or not. `abuseAttempts` of them inside `abuseWindow`
--      locks the menu for `lockBase` seconds; each further offence doubles it
--      (up to `lockMax`), and the strike count only resets after
--      `strikeReset` quiet seconds. While locked, nothing is granted and the
--      menu is not even offered.
--
-- Anti-bypass: the clock is made monotonic (a clock set back never rewinds a
-- cooldown or a lock) and the state lives in a store the caller points at
-- storage that does not rewind with save states (see FollowerInteraction).
local Limiter = {}
Limiter.__index = Limiter

local function newState()
  return { gains = {}, attempts = {}, last = {}, lockUntil = 0, strikes = 0, strikeAt = 0, seen = 0 }
end

--- opts: cfg (see Config.INTERACT), clock (function -> seconds, default
--- os.time), store ({ load = fn -> table|nil, save = fn(table) }, optional).
function Limiter.new(opts)
  return setmetatable({
    cfg = opts.cfg, clock = opts.clock or os.time, store = opts.store,
    state = nil,
  }, Limiter)
end

local function sanitize(raw)
  local s = newState()
  if type(raw) ~= "table" then return s end
  local function list(v)
    local out = {}
    if type(v) == "table" then
      for _, t in ipairs(v) do if type(t) == "number" then out[#out + 1] = t end end
    end
    return out
  end
  s.gains, s.attempts = list(raw.gains), list(raw.attempts)
  for k, v in pairs(type(raw.last) == "table" and raw.last or {}) do
    if type(k) == "string" and type(v) == "number" then s.last[k] = v end
  end
  for _, k in ipairs({ "lockUntil", "strikes", "strikeAt", "seen" }) do
    if type(raw[k]) == "number" then s[k] = raw[k] end
  end
  return s
end

--- Loads the saved state once (lazily); safe to call repeatedly.
function Limiter:load()
  if self.state then return self.state end
  local raw
  if self.store and self.store.load then
    local ok, value = pcall(self.store.load)
    if ok then raw = value end
  end
  self.state = sanitize(raw)
  return self.state
end

function Limiter:_save()
  if self.store and self.store.save then pcall(self.store.save, self.state) end
end

--- Drops the in-memory copy so the next call re-reads the store (a save was
--- loaded, a checkpoint restored, ...).
function Limiter:reset()
  self.state = nil
end

-- Monotonic "now": never less than the latest time ever seen.
function Limiter:_now()
  local s = self:load()
  local now = tonumber(self.clock()) or 0
  if now < s.seen then now = s.seen end
  s.seen = now
  return now
end

local function prune(list, now, window)
  local keep = {}
  for _, t in ipairs(list) do
    if now - t < window then keep[#keep + 1] = t end
  end
  return keep
end

-- strikes fade after a long quiet spell
function Limiter:_decay(now)
  local s = self.state
  if s.strikes > 0 and now >= s.lockUntil and now - s.strikeAt >= self.cfg.strikeReset then
    s.strikes = 0
  end
end

--- { locked = bool, remaining = seconds, strikes = n }
function Limiter:status()
  local s = self:load()
  local now = self:_now()
  self:_decay(now)
  local remaining = math.max(0, s.lockUntil - now)
  return { locked = remaining > 0, remaining = remaining, strikes = s.strikes }
end

--- The player selected `action` ("pet" | "play" | "talk"). Returns a table:
---   { ok = true }                                    -- grant the happiness
---   { ok = false, reason = "cooldown", wait = secs } -- too soon for this action
---   { ok = false, reason = "tired" }                 -- window budget used up
---   { ok = false, reason = "locked", remaining = secs, newlyLocked = bool }
function Limiter:attempt(action)
  local s = self:load()
  local cfg = self.cfg
  local now = self:_now()
  self:_decay(now)

  if now < s.lockUntil then
    return { ok = false, reason = "locked", remaining = s.lockUntil - now, newlyLocked = false }
  end

  -- every selection counts toward abuse, whatever happens to it
  s.attempts = prune(s.attempts, now, cfg.abuseWindow)
  s.attempts[#s.attempts + 1] = now
  if #s.attempts >= cfg.abuseAttempts then
    s.strikes = s.strikes + 1
    s.strikeAt = now
    local length = math.min(cfg.lockMax, cfg.lockBase * (2 ^ (s.strikes - 1)))
    s.lockUntil = now + length
    s.attempts = {}
    self:_save()
    return { ok = false, reason = "locked", remaining = length, newlyLocked = true }
  end

  local cooldown = cfg.cooldown[action] or 0
  local last = s.last[action]
  if last and now - last < cooldown then
    self:_save()
    return { ok = false, reason = "cooldown", wait = cooldown - (now - last) }
  end

  s.gains = prune(s.gains, now, cfg.window)
  if #s.gains >= cfg.maxGains then
    self:_save()
    return { ok = false, reason = "tired" }
  end

  s.gains[#s.gains + 1] = now
  s.last[action] = now
  self:_save()
  return { ok = true }
end

return Limiter
