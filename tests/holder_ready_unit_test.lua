-- Run: lua tests/holder_ready_unit_test.lua
package.path = "./?.lua;./?/init.lua;" .. package.path

local failures = 0
local function check(cond, msg)
  if not cond then
    failures = failures + 1
    io.stderr:write("FAIL: " .. tostring(msg) .. "\n")
  else
    print("ok  " .. tostring(msg))
  end
end
local function eq(a, b, msg)
  check(a == b, string.format("%s (got %s expected %s)", msg, tostring(a), tostring(b)))
end

local V = {}
function V.require(name) return assert(loadfile("lib/" .. name .. ".lua"))(V) end
local LevelReady = V.require("level_ready")
local HolderReady = V.require("holder_ready")

-- a LevelReady over a plain save table: species 10 learns move 7 at level 6 and evolves
-- into 11 from level 7
local function newLevelReady()
  local mod = { save = {} }
  function mod.save.get(_, k) return mod.save[k] end
  function mod.save.set(_, k, v) mod.save[k] = v end
  return LevelReady.new(mod, {
    movesLearnedAt = function(_, level) return level == 6 and { 7 } or {} end,
    knowsMove = function(mon, id)
      for _, m in ipairs(mon.moves or {}) do if m == id then return true end end
      return false
    end,
    evolutionTarget = function(mon) return (mon.species == 10 and mon.level >= 7) and 11 or nil end,
  })
end

local function setup(t)
  t = t or {}
  local lr = newLevelReady()
  local log = { evo = {}, moves = {} }
  local free = t.free ~= false
  local open = false
  local deps = {
    canOpen = function() return free end,
    partyMons = function() return t.party end,
    evolutionTarget = function(mon) return (mon.species == 10 and mon.level >= 7) and 11 or nil end,
    startEvolution = function(mon, target, done)
      log.evo[#log.evo + 1] = { mon, target }
      log.doneEvo, open = done, true
      return t.evoOpens ~= false
    end,
    startMoveLearn = function(mon, ids, done)
      log.moves[#log.moves + 1] = { mon, ids }
      log.doneMove, open = done, true
      return t.moveOpens ~= false
    end,
    screenBusy = function() return open end,
  }
  local hr = HolderReady.new(lr, deps)
  return hr, lr, log, function(v) free = v end, function() open = false end
end

local function lr_save_mon(species, level) return { personality = 1234, species = species, level = level, moves = { 1 } } end

-- ------- a holder that learns a move: the relearner opens once the game is free
do
  local mon = lr_save_mon(10, 6)
  local hr, lr, log, setFree, close = setup({ party = { {}, mon }, free = false })
  lr:record(mon, 5, 6)
  hr:push(mon)
  hr:push(mon)
  for _ = 1, 10 do hr:tick() end
  eq(#log.moves, 0, "nothing opens while the game is busy")
  setFree(true)
  hr:tick()
  eq(#log.moves, 1, "the move relearner opens once it is free")
  eq(log.moves[1] and log.moves[1][1], mon, "...for the holder")
  eq(log.moves[1] and log.moves[1][2][1], 7, "...with the move it skipped")
  for _ = 1, 10 do hr:tick() end
  eq(#log.moves, 1, "...once (pushed twice, waiting on the screen)")
  table.insert(mon.moves, 7) -- learned it
  close()
  log.doneMove()
  for _ = 1, 5 do hr:tick() end
  eq(lr:pending(mon), nil, "done: nothing left waiting")
  check(not hr:busy(), "...and the queue is empty")
end

-- ------- evolution first, then the moves
do
  local mon = lr_save_mon(10, 7)
  local hr, lr, log, _, close = setup({ party = { mon } })
  lr:record(mon, 5, 7)
  hr:push(mon)
  hr:tick()
  eq(#log.evo, 1, "an evolution waiting: its scene opens first")
  eq(log.evo[1] and log.evo[1][2], 11, "...into the engine's target")
  eq(#log.moves, 0, "...the moves wait")
  mon.species = 11 -- it evolved
  close()
  log.doneEvo()
  hr:tick()
  eq(#log.moves, 1, "then the move relearner")
  close()
  log.doneMove() -- turned down
  hr:tick()
  eq(lr:pending(mon), nil, "turned down: dismissed, its EXP flows again")
  check(not hr:busy(), "...and it is finished")
end

-- ------- gone from the party, or nothing waiting: skipped
do
  local mon = lr_save_mon(10, 6)
  local hr, lr, log = setup({ party = { {} } })
  lr:record(mon, 5, 6)
  hr:push(mon)
  hr:tick()
  eq(#log.moves, 0, "not in the party any more: nothing opens")
  local other = lr_save_mon(10, 6)
  other.personality = 99
  hr, lr, log = setup({ party = { other } })
  hr:push(other)
  hr:tick()
  eq(#log.moves, 0, "nothing waiting: nothing opens")
  check(not hr:busy(), "...and nothing stays queued")
end

-- ------- a screen that never calls back is given up; one that cannot open does not loop
do
  local mon = lr_save_mon(10, 6)
  local hr, lr, log, _, close = setup({ party = { mon } })
  lr:record(mon, 5, 6)
  hr:push(mon)
  hr:tick()
  close() -- closed without calling done
  for _ = 1, HolderReady.STALE_TICKS + 2 do hr:tick() end
  check(not hr.waiting, "a screen gone without calling back is given up")
  mon = lr_save_mon(10, 6)
  hr, lr, log = setup({ party = { mon }, moveOpens = false })
  lr:record(mon, 5, 6)
  hr:push(mon)
  for _ = 1, 20 do hr:tick() end
  eq(#log.moves, 1, "a screen that cannot open is tried once")
  check(not hr:busy(), "...then dropped (it stays waiting for the partner menu)")
  check(lr:pending(mon) ~= nil, "...its moves still recorded")
end

-- ------- reset clears it
do
  local mon = lr_save_mon(10, 6)
  local hr, lr = setup({ party = { mon }, free = false })
  lr:record(mon, 5, 6)
  hr:push(mon)
  hr:reset()
  check(not hr:busy(), "reset empties the queue")
end

if failures > 0 then
  io.stderr:write(failures .. " failure(s)\n")
  os.exit(1)
end
print("holder_ready_unit_test: all passed")
