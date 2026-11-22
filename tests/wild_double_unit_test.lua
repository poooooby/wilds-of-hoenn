-- Run: lua tests/wild_double_unit_test.lua
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

local WildDouble = assert(loadfile("lib/wild_double.lua"))({})

-- ------- the wild intro, built for one foe, brings out both (and the player's two)
do
  -- what the engine's build_wild + MonAnimBattle.introSteps make (animations on)
  local steps = {
    { kind = "fade", data = { mode = "FROM_BLACK" } },
    { kind = "bgslide", data = { slideEnemyMon = true } },
    { kind = "shiny_check", data = { side = "enemy" } },
    { kind = "undarken", data = { side = "enemy" } },
    { kind = "mon_anim", data = { kind = "front", ids = { "enemy" } } },
    { kind = "healthbox", data = { side = "enemy", frames = 23 } },
    { kind = "msg", data = { text = "Two wild ..." } },
    { kind = "player_throw", data = {} },
    { kind = "mon_anim", data = { kind = "back", ids = { "player" } } },
    { kind = "shiny_check", data = { side = "player" } },
    { kind = "mon_anim_wait", data = { ids = { "player" } } },
    { kind = "healthbox", data = { side = "player", frames = 23 } },
    { kind = "cry", data = { side = "enemy" } },
  }
  local n = WildDouble.patchIntroSteps(steps, { 1, 3 }, { 0, 2 })
  eq(n, 9, "every step that brings a Pokemon out is changed")
  local function ids(i) return table.concat(steps[i].data.ids or {}, ",") end
  eq(ids(3), "1,3", "the foes' shiny check covers both")
  eq(ids(5), "1,3", "...their front animation")
  eq(ids(6), "1,3", "...their health boxes")
  eq(ids(8), "0,2", "the throw sends out both of the player's")
  eq(ids(9), "0,2", "...their back animation")
  eq(ids(10), "0,2", "...their shiny check")
  eq(ids(11), "0,2", "...waiting for both")
  eq(ids(12), "0,2", "...their health boxes")
  eq(ids(13), "1,3", "a foe cry (animations off) is both foes'")
  check(steps[2].data.ids == nil and steps[7].data.ids == nil, "the slide and the messages are left alone")
  -- the player with one Pokemon
  local one = { { kind = "player_throw", data = {} }, { kind = "healthbox", data = { side = "player" } } }
  WildDouble.patchIntroSteps(one, { 1, 3 }, { 0 })
  eq(table.concat(one[1].data.ids, ","), "0", "one Pokemon of their own: just that one comes out")
end

-- ------- two foes: no ball, no running; one left: a ball at it, running by the wild odds
do
  eq(WildDouble.ballRule(2), "refuse", "both foes standing: a Poke Ball is refused")
  eq(WildDouble.ballRule(1), "throw", "one left: the ball is thrown")
  check(not WildDouble.canTryRun(2), "both foes standing: no running")
  check(WildDouble.canTryRun(1), "one left: running is tried")
  eq(WildDouble.lastFoe({ [1] = true, [3] = true }), nil, "the ball's foe: none while both stand")
  eq(WildDouble.lastFoe({ [1] = false, [3] = true }), 3, "...the second one when the first is down")
  eq(WildDouble.lastFoe({ [1] = true, [3] = false }), 1, "...the first one when the second is down")
  eq(WildDouble.lastFoe({}), nil, "...none when neither stands")
  -- running from the last one: the wild odds; tries made while both stood do not count
  check(WildDouble.escapes(100, 90, 0, 0, 255), "faster than the foe left: always away")
  -- speed 50 vs 100: 64 base, + 30 a counted failed try
  check(not WildDouble.escapes(50, 100, 0, 0, 64), "slower: speed x 128 / the foe's (64) against the roll")
  check(WildDouble.escapes(50, 100, 1, 0, 64), "...a failed try at the last one adds 30")
  check(not WildDouble.escapes(50, 100, 3, 3, 64), "...tries refused while both stood add nothing")
  check(WildDouble.escapes(50, 100, 4, 3, 64), "...only those after count")
  check(WildDouble.BLOCKED_BALL_TEXT.STRINGID_DONTBEATHIEF and WildDouble.BLOCKED_BALL_TEXT.STRINGID_TRAINERBLOCKEDBALL,
    "the double's trainer-ball lines are the ones silenced")
end

if failures > 0 then
  io.stderr:write(failures .. " failure(s)\n")
  os.exit(1)
end
print("wild_double_unit_test: all passed")
