-- Run: lua tests/level_ready_unit_test.lua
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

local LevelReady = assert(loadfile("lib/level_ready.lua"))()

local LEARN = { [7] = { 40 }, [8] = { 41, 42 }, [9] = {} }
local evoTarget = nil
local function deps()
  return {
    movesLearnedAt = function(_mon, level) return LEARN[level] or {} end,
    knowsMove = function(mon, id)
      for _, m in ipairs(mon.moves or {}) do if m == id then return true end end
      return false
    end,
    evolutionTarget = function() return evoTarget end,
  }
end
local function newStore()
  local data = {}
  return { save = { get = function(_, k) return data[k] end, set = function(_, k, v) data[k] = v end }, _data = data }
end
local function mon(t)
  local m = { personality = 1234, level = 6, moves = { 33 } }
  for k, v in pairs(t or {}) do m[k] = v end
  return m
end

-- ------- nothing leveled, nothing waiting
do
  local lr = LevelReady.new(newStore(), deps())
  eq(lr:pending(mon()), nil, "a fresh Pokemon waits for nothing")
  eq(lr:label(mon(), 0), nil, "...and shows no label")
  lr:record(mon(), 6, 6)
  eq(lr:pending(mon()), nil, "no level gained: nothing recorded")
end

-- ------- moves learned at the levels crossed
do
  local store = newStore()
  local lr = LevelReady.new(store, deps())
  local m = mon()
  lr:record(m, 6, 8)
  local p = lr:pending(m)
  eq(#p.moves, 3, "every move of every level crossed is waiting")
  eq(p.moves[1], 40, "...in level order")
  eq(lr:label(m, 0), "New move ready!", "the label asks for a move")
  m.moves = { 33, 40 }
  p = lr:pending(m)
  eq(#p.moves, 2, "a move it learned meanwhile stops waiting")
  m.moves = { 33, 40, 41, 42 }
  eq(lr:pending(m), nil, "when it knows them all nothing is waiting")
  eq(lr:label(m, 0), nil, "...and the label is gone")
  eq(store._data["level_ready/state"]["1234"], nil, "...and the entry is dropped from the save")
end

-- ------- a move it already knows is never queued
do
  local lr = LevelReady.new(newStore(), deps())
  local m = mon({ moves = { 33, 40 } })
  lr:record(m, 6, 7)
  eq(lr:pending(m), nil, "a level's move it already knows is not asked about")
end

-- ------- no duplicates across level-ups
do
  local lr = LevelReady.new(newStore(), deps())
  local m = mon()
  lr:record(m, 6, 7)
  lr:record(m, 6, 7)
  eq(#lr:pending(m).moves, 1, "the same move is only queued once")
end

-- ------- evolution
do
  local lr = LevelReady.new(newStore(), deps())
  local m = mon({ species = 277 })
  evoTarget = nil
  lr:record(m, 8, 9)
  eq(lr:pending(m), nil, "a level-up that evolves nothing asks nothing")
  evoTarget = 278
  lr:record(m, 9, 10)
  check(lr:pending(m).evolve, "a level-up that makes it evolvable asks to evolve")
  eq(lr:label(m, 0), "Ready to evolve!", "the label says so")
  evoTarget = nil -- an Everstone: the engine offers nothing
  eq(lr:pending(m), nil, "while the engine offers no evolution (an Everstone) nothing shows")
  evoTarget = 278 -- the stone came off
  check(lr:pending(m) and lr:pending(m).evolve, "...and it comes back when the engine offers one again")
  m.species = 278 -- it evolved
  eq(lr:pending(m), nil, "once it has evolved the request is done")
  evoTarget = 279
  eq(lr:pending(m), nil, "...and its next stage is not asked about unless a level-up made it possible")
  evoTarget = nil
end

-- ------- a Pokemon that merely could evolve is never asked about
do
  local lr = LevelReady.new(newStore(), deps())
  local m = mon({ species = 277 })
  evoTarget = 278
  eq(lr:pending(m), nil, "nothing was recorded, so nothing is asked")
  evoTarget = nil
end

-- ------- both: the label alternates
do
  local lr = LevelReady.new(newStore(), deps())
  local m = mon()
  evoTarget = 278
  lr:record(m, 6, 7)
  eq(lr:label(m, 0), "Ready to evolve!", "with both waiting, first the evolution")
  eq(lr:label(m, 150), "New move ready!", "...then the move")
  eq(lr:label(m, 300), "Ready to evolve!", "...and round again")
  eq(lr:label(m, 40, 30), "New move ready!", "the period is adjustable")
  evoTarget = nil
end

-- ------- saved with the save file, per Pokemon
do
  local store = newStore()
  local lr = LevelReady.new(store, deps())
  lr:record(mon(), 6, 7)
  local again = LevelReady.new(store, deps())
  eq(#again:pending(mon()).moves, 1, "it survives a reload")
  eq(again:pending(mon({ personality = 99 })), nil, "...for that Pokemon only")
  lr:reset()
  eq(#lr:pending(mon()).moves, 1, "reset re-reads the save")
  eq(LevelReady.new(nil, deps()):pending(mon()), nil, "no save at all is harmless")
  eq(lr:pending({}), nil, "a Pokemon with no personality is ignored")
end

-- ------- it follows the Pokemon, not the field: out of the party, back, another one out
do
  local store = newStore()
  local lr = LevelReady.new(store, deps())
  evoTarget = 278
  local m = mon({ species = 277 })
  lr:record(m, 6, 7)
  -- a battle, a map change: the tracker is not told, nothing changes
  check(lr:pending(m) ~= nil, "after a battle or a map change it is still waiting")
  -- deposited in the PC and withdrawn: a different table, the same personality
  local back = mon({ species = 277, moves = { 33 } })
  check(lr:pending(back) ~= nil and lr:pending(back).evolve, "withdrawn from the PC it is still waiting")
  -- another Pokemon is out meanwhile: its own state is separate
  local other = mon({ personality = 777, species = 25 })
  eq(lr:pending(other), nil, "another Pokemon does not inherit it")
  check(lr:pending(back) ~= nil, "...and it is still there when this one is out again")
  -- the save is written and read back
  local again = LevelReady.new(store, deps())
  check(again:pending(back) ~= nil and again:pending(back).evolve, "after a save and load it is still waiting")
  evoTarget = nil
end

if failures > 0 then
  io.stderr:write(failures .. " failure(s)\n")
  os.exit(1)
end
print("level_ready_unit_test: all passed")
