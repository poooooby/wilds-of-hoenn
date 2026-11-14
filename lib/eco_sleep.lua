-- Wild Ecology: asleep by day or by night (lib/eco.lua activity "sleep"). A Pokemon's
-- profile `activity` (lib/eco_profile.lua) says when it is about: a day one (birds, bugs,
-- plants ...) is often found asleep at night, a night one (Ghost, Dark, Zubat, Hoothoot ...)
-- by day, anything else now and then at night. Config.ECO.sleep has the hours and odds.
--
-- A sleeper stays put curled up (PMDCollab: its Sleep animation, else EventSleep, else
-- Idle's first frame; HGSS stands) with "z"s floating up (lib/wild_emote.lua). A player
-- walking right past it, or running / biking near, wakes it -- its Wake animation where it
-- has one -- and then it reacts by its temper at once: a territorial or aggressive one comes
-- at them angry, a skittish one runs (a burrower ducks underground). Sneak by and it sleeps
-- on. When the night (or the day) is over it wakes by itself. A group sleeps together
-- (lib/spawn_manager.lua riderPose).
local V = ...
local Config = V.require("config")
local EnginePatch = V.require("engine_patch")
local Eco = V.require("eco")
local WildReactions = V.require("wild_reactions")

local EcoSleep = {}

local function between(rng, r) return rng(r[1], r[2]) end

local function hasAnim(e, anim)
  local r = e.renderer
  return r and r.isPmd and r.info and r.info[anim] ~= nil or false
end

--- Is `hour` (0-23) night (Config.ECO.sleep.night = { from, to }, wrapping past midnight)?
--- Pure.
function EcoSleep.isNight(hour, cfg)
  cfg = cfg or Config.ECO.sleep
  hour = tonumber(hour)
  if not hour then return false end
  local a, b = cfg.night[1], cfg.night[2]
  if a > b then return hour >= a or hour < b end
  return hour >= a and hour < b
end

--- The % chance a Pokemon out by `activity` is asleep now. Pure.
function EcoSleep.chance(activity, night, cfg)
  cfg = cfg or Config.ECO.sleep
  local c = cfg.chance
  if activity == "day" then return night and c.dayAtNight or 0 end
  if activity == "night" then return night and 0 or c.nightByDay end
  return night and c.anyAtNight or 0
end

--- The animation a sleeper shows: Sleep (curled up), else EventSleep ("nap"), else nil.
function EcoSleep.animFor(e)
  if hasAnim(e, "sleep") then return "sleep" end
  if hasAnim(e, "nap") then return "nap" end
  return nil
end

--- How high over its tile's ground line a sleeper's head is (for the "z"s): its sleeping
--- pose lies low.
function EcoSleep.headOf(r, anim)
  if not r then return 12 end
  if r.isPmd and anim and r.info and r.info[anim] and r.headLift then return r:headLift({ anim }) end
  return ((r.headLift and r:headLift()) or 16) * 0.7
end

--- Is the player close enough to wake `e` (or keep it awake): within Config.ECO.sleep.wake
--- tiles (Chebyshev) for how they are moving -- a standing / walking one right beside it.
function EcoSleep.disturbed(e, ctx, cfg)
  cfg = cfg or Config.ECO.sleep
  local p = ctx and ctx.player
  if not p then return false end
  local d = math.max(math.abs(p.x - e.cellX), math.abs(p.y - e.cellY))
  local how = p.moving and WildReactions.playerHow() or "walk"
  return d <= (cfg.wake[how] or cfg.wake.walk)
end

local function canSleep(e)
  return e.terrain == "land" and not e.roamer and not e.lured and not e.react and not e.engaged
    and not e.fx and not e.moving and not e.rider and not e.runAway and not e.chaseHome
    and not e.charging and not e.defeated
end

--- The state a sleep starts with (`night`: the half of the day it fell asleep in).
function EcoSleep.state(e, night)
  local anim = EcoSleep.animFor(e)
  return { sleeping = true, night = night, anim = anim, groupAnim = anim, zzz = 0 }
end

-- it wakes: by itself (the night / day is over) or startled by the player (`byPlayer`)
local function wake(e, s, byPlayer)
  s.waking, s.wakeT, s.byPlayer = true, 0, byPlayer
  s.wakeAnim = hasAnim(e, "wake")
  s.anim = s.wakeAnim and "wake" or nil
  s.groupAnim = s.anim
end

--- A Pokemon just woken by the player reacts by its temper, with no roll: a territorial /
--- aggressive one (or a stronger one) comes at them, a skittish / weaker one runs.
function EcoSleep.react(e, ctx)
  local p = ctx and ctx.player
  if not p then return nil end
  local cfg = Config.REACT
  local lead = ctx.lead
  local cls, ratio = WildReactions.classify(e.level, ctx.bst and ctx.bst(e.species), lead and lead.level,
    lead and lead.bst, cfg)
  local what = WildReactions.decide(e.profile and e.profile.temper, cls, ratio, cfg)
  if not what then return nil end
  return WildReactions.begin(e, what, p.x, p.y, ctx)
end

Eco.register("sleep", {
  step = function(e, ctx, _sm, s)
    local cfg = Config.ECO.sleep
    local r = e.renderer
    local rng, now = ctx.rng or math.random, ctx.now or 0
    if not s.waking then
      if ctx.night ~= nil and ctx.night ~= s.night then
        wake(e, s, false) -- morning (or evening): up it gets
      elseif EcoSleep.disturbed(e, ctx, cfg) then
        wake(e, s, true)
      end
    end
    if s.waking then
      s.wakeT = s.wakeT + 1
      if s.wakeT >= (s.wakeAnim and cfg.wakeTicks or 1) then
        e.awakeUntil = now + between(rng, cfg.awake)
        -- (a burrower ducking under starts its own activity: Eco.step leaves that one be)
        if s.byPlayer then EcoSleep.react(e, ctx) end
        return true
      end
    else
      s.zzz = s.zzz + 1
    end
    if r and r.isPmd and s.anim and r.advanceAs then
      r:advanceAs(s.anim, 1, "idle")
    elseif r and r.isPmd and not s.waking and r.holdIdle then
      r:holdIdle() -- no sleeping art: it lies still
    elseif r and r.advance then
      r:advance(false)
    end
    return false
  end,
  abort = function(e)
    local r = e.renderer
    if r and r.isPmd and r.advance then r:advance(false) end
  end,
})

--- The chooser: a Pokemon out of its hours falls asleep (once per half day it decides
--- whether it is a sleeper, by Config.ECO.sleep.chance), unless the player is right there or
--- it was just woken. `ctx.night` (lib/spawn_manager.lua) is nil when the hour is unknown.
function EcoSleep.choose(e, ctx)
  if ctx.night == nil or not canSleep(e) then return nil end
  local prof = e.profile
  if not prof then return nil end
  local cfg = Config.ECO.sleep
  local period = ctx.night and "night" or "day"
  if e.sleepPeriod ~= period then
    e.sleepPeriod = period
    e.sleepy = (ctx.rng or math.random)(1, 100) <= EcoSleep.chance(prof.activity, ctx.night, cfg)
  end
  if not e.sleepy then return nil end
  if e.awakeUntil and (ctx.now or 0) < e.awakeUntil then return nil end
  if EcoSleep.disturbed(e, ctx, cfg) then return nil end
  return "sleep", EcoSleep.state(e, ctx.night)
end
Eco.addChooser(EcoSleep.choose, true)

return EcoSleep
