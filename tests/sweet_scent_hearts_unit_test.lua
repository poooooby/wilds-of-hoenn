-- Run: lua tests/sweet_scent_hearts_unit_test.lua
-- The hearts over a Pokemon Sweet Scent called over: staggered, rising, swaying, fading,
-- and gone with the lure. No love context: the actor draws nothing here.
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

local H = assert(loadfile("lib/sweet_scent_hearts.lua"))({})
local LIFE, N = H.RISE_TICKS, H.COUNT

check(H.state(0, 1, 3600) ~= nil and H.state(0, 2, 3600) == nil, "heart 1 starts first, heart 2 waits its turn")
check(H.state(LIFE / N, 2, 3600) ~= nil, "heart 2 appears a third of a rise later")
local a, b = H.state(5, 1, 3600), H.state(40, 1, 3600)
check(b.dy < a.dy, "a heart rises (dy goes up the screen)")
check(-b.dy <= H.RISE_PX, "it rises at most RISE_PX")
check(H.state(1, 1, 3600).alpha < H.state(20, 1, 3600).alpha, "it fades in")
check(H.state(LIFE - 1, 1, 3600).alpha < H.state(30, 1, 3600).alpha, "and fades out at the top")
local c = H.state(LIFE + 5, 1, 3600)
check(c and math.abs(c.dy - a.dy) < 1e-9, "then starts over from the bottom")
check(H.state(30, 1, 0).alpha == 0, "no hearts once the lure is over")
check(H.state(30, 1, H.FADE_OUT / 2).alpha < H.state(30, 1, 3600).alpha, "they fade over the lure's last second")
local s1, s2 = H.state(30, 1, 3600), H.state(30 + LIFE / N, 2, 3600)
check(s1.dx * s2.dx < 0, "neighbouring hearts drift to opposite sides")
check(#H.SHAPE == 6 and #H.SHAPE[1] == 7, "a 7 x 6 pixel heart")

local actor = H.actor(32, 48, 24, 30, 3600, 3, 5)
check(actor.kind == "ow_sweet_scent_hearts" and actor.y == 48 + 16 - 24, "the actor sits above the head (lift)")
check(actor.sortY > 48 + 16, "and in front of the Pokemon it floats over")
check(pcall(actor.draw, actor, 0, 0), "drawing without love does nothing, never errors")

print("")
if failures > 0 then
  io.stderr:write(failures .. " failure(s)\n")
  os.exit(1)
end
print("sweet_scent_hearts_unit_test: all passed")
