-- Wild Ecology: what visible wild Pokemon do on their own, by how their kind lives
-- (lib/eco_profile.lua) -- fish leaping and schooling, whales surfacing, packs moving
-- together, hunters chasing prey. Part of the Wild Reacts option: lib/spawn_manager.lua only
-- runs it while its reaction context exists (the option on, the field free, no battle, not
-- the Safari Zone); with it off every Pokemon wanders / idles / swims as before.
--
-- An ACTIVITY is a registered kind (Eco.register) a Pokemon is doing right now, kept as
-- `e.eco = { kind, t, ... }`. While it runs, lib/spawn_manager.lua calls Eco.step instead of
-- the plain Behavior.tick, and the Battler, Wild Reacts and the dive cycle leave it alone. An
-- activity may set `e.eco.untouchable` (in the air mid-leap, under the water): then the
-- player cannot meet it until it is back.
--
-- An activity: { step = function(e, ctx, sm) -> true when finished,
--                abort = function(e, sm) (optional: put the renderer / position back) }.
-- A CHOOSER (Eco.addChooser) is asked, for an idle Pokemon, whether to start something; it
-- runs on each Pokemon's own timer (`e.ecoNext`), never every tick.
local V = ...
local Config = V.require("config")

local Eco = {}
Eco.ACTIVITIES = {}
Eco.CHOOSERS = {}

--- Registers an activity under `kind`.
function Eco.register(kind, activity)
  Eco.ACTIVITIES[kind] = activity
end

--- Adds a chooser: fn(e, ctx, sm) -> kind, state (or nil to let it be). `first`: asked
--- before the others (sleep: a sleeper does nothing else).
function Eco.addChooser(fn, first)
  if first then table.insert(Eco.CHOOSERS, 1, fn) else Eco.CHOOSERS[#Eco.CHOOSERS + 1] = fn end
end

--- Starts activity `kind` on `e`, with `state` (a table, kept as `e.eco`). True when it began.
function Eco.start(e, kind, state)
  if not Eco.ACTIVITIES[kind] then return false end
  state = state or {}
  state.kind, state.t = kind, 0
  e.eco = state
  return true
end

--- Ends `e`'s activity at once (the player touched it, the Battler engaged it, the option
--- went off, it left): the activity puts back what it changed.
function Eco.abort(e, sm)
  local s = e.eco
  if not s then return end
  e.eco = nil
  local a = Eco.ACTIVITIES[s.kind]
  if a and a.abort then pcall(a.abort, e, sm, s) end
end

--- One tick of `e`'s activity (lib/spawn_manager.lua, instead of Behavior.tick).
function Eco.step(e, ctx, sm)
  local s = e.eco
  if not s then return end
  local a = Eco.ACTIVITIES[s.kind]
  if not a then e.eco = nil return end
  s.t = s.t + 1
  local ok, done = pcall(a.step, e, ctx, sm, s)
  if not ok then
    -- a broken activity never leaves a Pokemon stuck: it is dropped, cleanly
    Eco.abort(e, sm)
    if sm and sm.mod and sm.mod.log then sm.mod.log:warn("[wilds_of_hoenn] eco %s: %s", tostring(s.kind), tostring(done)) end
    return
  end
  if done and e.eco == s then
    e.eco = nil
    if a.abort then pcall(a.abort, e, sm, s) end
  end
end

--- Asks the choosers whether idle `e` (available, standing, nothing else going on) starts
--- an activity now. Each Pokemon is asked on its own timer (Config.ECO.chooseEvery ticks,
--- staggered), so a full map costs a few calls a tick. True when one started.
function Eco.consider(e, ctx, sm)
  if e.eco or e.moving or e.rider then return false end
  local now = ctx and ctx.now or 0
  local every = Config.ECO and Config.ECO.chooseEvery or 60
  if not e.ecoNext then
    local rng = ctx and ctx.rng or math.random
    e.ecoNext = now + rng(1, every)
    return false
  end
  if now < e.ecoNext then return false end
  e.ecoNext = now + every
  for _, choose in ipairs(Eco.CHOOSERS) do
    local ok, kind, state = pcall(choose, e, ctx, sm)
    if ok and kind and Eco.start(e, kind, state) then return true end
  end
  return false
end

--- Can the player meet `e` right now? (Not mid-leap, not under the water.)
function Eco.touchable(e)
  return not (e.eco and e.eco.untouchable)
end

return Eco
