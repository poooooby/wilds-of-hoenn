-- Run: lua tests/actor_renderer_unit_test.lua
-- Covers the parts of ActorRenderer that don't need love.graphics: frame
-- index selection and sheet path resolution. draw() itself needs a real
-- love context and is exercised only in game (see MANUAL_TEST.md).
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

local modules = {}
local V = { path = "." }
function V.require(name)
  if modules[name] ~= nil then return modules[name] end
  local chunk = assert(loadfile("lib/" .. name .. ".lua"))
  local value = chunk(V)
  modules[name] = value
  return value
end

local ActorRenderer = V.require("actor_renderer")

local POSE_STAND, POSE_WALK_A, POSE_WALK_B = ActorRenderer.POSE_STAND, ActorRenderer.POSE_WALK_A, ActorRenderer.POSE_WALK_B
local POSE_RUN_BASE, POSE_RUN_A, POSE_RUN_B = ActorRenderer.POSE_RUN_BASE, ActorRenderer.POSE_RUN_A, ActorRenderer.POSE_RUN_B
-- Kanto's 6-frame Poke Followers / GSC layout is gone: any frame count other
-- than 18 reads the 18-frame table, never a stale 6-frame one.
eq(ActorRenderer.frameIndexFor("down", POSE_WALK_B, 6), 4, "a leftover 6-frame count reads the 18-frame table (walkB = 4, not the old collapsed 3)")
eq(ActorRenderer.frameIndexFor("down", "not-a-real-pose", 18), 0, "an unrecognized pose falls back to stand")

-- ------- frame index, 18 frames (the only layout): the full walk-A/
-- walk-B/run-base/run-A/run-B layout from tools/generate_true_size_18frame.py.
eq(ActorRenderer.frameIndexFor("down", POSE_STAND, 18), 0, "18-frame stand down = 0")
eq(ActorRenderer.frameIndexFor("up", POSE_STAND, 18), 1, "18-frame stand up = 1")
eq(ActorRenderer.frameIndexFor("left", POSE_STAND, 18), 2, "18-frame stand left = 2")
eq(ActorRenderer.frameIndexFor("right", POSE_STAND, 18), 2, "18-frame stand right mirrors left = 2")
eq(ActorRenderer.frameIndexFor("down", POSE_WALK_A, 18), 3, "18-frame walkA down = 3")
eq(ActorRenderer.frameIndexFor("down", POSE_WALK_B, 18), 4, "18-frame walkB down = 4")
eq(ActorRenderer.frameIndexFor("up", POSE_WALK_A, 18), 5, "18-frame walkA up = 5")
eq(ActorRenderer.frameIndexFor("up", POSE_WALK_B, 18), 6, "18-frame walkB up = 6")
eq(ActorRenderer.frameIndexFor("left", POSE_WALK_A, 18), 7, "18-frame walkA left = 7")
eq(ActorRenderer.frameIndexFor("left", POSE_WALK_B, 18), 8, "18-frame walkB left = 8")
eq(ActorRenderer.frameIndexFor("down", POSE_RUN_BASE, 18), 9, "18-frame runBase down = 9")
eq(ActorRenderer.frameIndexFor("down", POSE_RUN_A, 18), 10, "18-frame runA down = 10")
eq(ActorRenderer.frameIndexFor("down", POSE_RUN_B, 18), 11, "18-frame runB down = 11")
eq(ActorRenderer.frameIndexFor("up", POSE_RUN_BASE, 18), 12, "18-frame runBase up = 12")
eq(ActorRenderer.frameIndexFor("left", POSE_RUN_BASE, 18), 15, "18-frame runBase left = 15")
eq(ActorRenderer.frameIndexFor("right", POSE_RUN_A, 18), 16, "18-frame right mirrors left for runA = 16")
eq(ActorRenderer.frameIndexFor(nil, POSE_STAND, 18), 0, "18-frame: unknown facing falls back to down")

eq(ActorRenderer.frameCountFor("followers"), 18, "a stale 'followers' style still gets the 18-frame layout")
eq(ActorRenderer.frameCountFor("pokemmo"), 18, "frameCountFor pokemmo = 18")

-- ------- construction + imagePath delegates to SpriteSource
local mod = {
  read = function(_, rel)
    local f = io.open(rel, "rb")
    if not f then return nil end
    local data = f:read("*a")
    f:close()
    return data
  end,
}
local r = ActorRenderer.new(mod, 1, false)
eq(r.dex, 1, "stores dex")
eq(r.shiny, false, "stores shiny")
eq(r.silhouette, false, "silhouette defaults off")
local path = r:imagePath()
check(path ~= nil and path:find("true_size18/hgss/001-normal", 1, true) ~= nil,
  "imagePath resolves the real dex 1 normal sheet")

local rShiny = ActorRenderer.new(mod, 1, true)
local pathShiny = rShiny:imagePath()
check(pathShiny ~= nil and pathShiny:find("true_size18/hgss/001-shiny", 1, true) ~= nil,
  "imagePath resolves the real dex 1 shiny sheet")

-- ------- HGSS / PokeMMO ("pokemmo") style resolves a completely
-- different, real, on-disk sheet when passed through
local SpriteSource = V.require("sprite_source")
local rPokemmo = ActorRenderer.new(mod, 1, false, SpriteSource.STYLE_POKEMMO)
eq(rPokemmo.style, SpriteSource.STYLE_POKEMMO, "stores the requested style")
eq(rPokemmo.frameCount, 18, "pokemmo style renderer uses the 18-frame layout")
local pokemmoPath = rPokemmo:imagePath()
check(pokemmoPath ~= nil and pokemmoPath:find("true_size18/hgss", 1, true) ~= nil,
  "imagePath honours the pokemmo style")

local rDefaultStyle = ActorRenderer.new(mod, 1, false)
eq(rDefaultStyle.style, SpriteSource.STYLE_POKEMMO, "style defaults to HGSS / PokeMMO when omitted")
eq(rDefaultStyle.frameCount, 18, "the default renderer uses the 18-frame layout")

-- ------- anchorOffset: Gen 3's own native OW sprite anchor -- centered
-- horizontally in a 16px cell, feet flush with the cell's bottom edge.
-- A plain 16x16 frame is a no-op (fills the cell exactly).
local ax16, ay16 = ActorRenderer.anchorOffset(16, 16)
eq(ax16, 0, "a 16x16 frame has no horizontal anchor offset")
eq(ay16, 0, "a 16x16 frame has no vertical anchor offset")

-- A bigger HGSS-style frame (e.g. Snorlax-ish) is centered horizontally
-- and extends UPWARD from the cell's bottom (negative y offset), never
-- squashed or drawn hanging below its feet.
local ax32, ay32 = ActorRenderer.anchorOffset(32, 32)
eq(ax32, -8, "a 32-wide frame is centered 8px left of the cell")
eq(ay32, -16, "a 32-tall frame extends 16px above the cell, feet at the bottom")

-- A non-square frame (real HGSS sheets aren't always square, e.g. dex 252
-- is 25 wide x 28 tall per frame) anchors each axis independently.
local axRect, ayRect = ActorRenderer.anchorOffset(24, 18)
eq(axRect, -4, "non-square frame: horizontal anchor still centers")
eq(ayRect, -2, "non-square frame: vertical anchor still flushes feet to the bottom")

-- ------- drawOffset: the exact love.graphics.draw(image, quad, drawX,
-- drawY, 0, flipX, 1) arguments. A regression test for a real bug: the
-- mirrored (facing="right") drawX used to be `frameW - anchorX`, which
-- only matches the correct `anchorX + frameW` when frameW == CELL (16) --
-- true for every Poke Followers/GSC frame, so it went unnoticed until a
-- non-16-wide HGSS/PokeMMO frame made it snap on every left<->right turn.
--
-- A 16x16 (GSC) frame: mirroring changes nothing visible, by construction.
local dxL16, dyL16, flipL16 = ActorRenderer.drawOffset("left", 16, 16)
local dxR16, dyR16, flipR16 = ActorRenderer.drawOffset("right", 16, 16)
eq(dxL16, 0, "16x16 left drawX")
eq(dxR16, 16, "16x16 right drawX (still correct even though the old buggy formula agreed here)")
eq(dyL16, dyR16, "16x16: drawY identical regardless of facing")
eq(flipL16, 1, "left is never mirrored")
eq(flipR16, -1, "right is always mirrored")

-- A non-square, non-16-wide HGSS-style frame (dex 252 is 25x28): this is
-- exactly the shape that exposed the bug. The footprint center -- drawX
-- (or drawX - frameW for the mirrored span) -- must land on the SAME
-- point for both facings, or turning around in place visibly shifts the
-- sprite sideways (the reported "snapping").
local frameW, frameH = 25, 28
local dxL, dyL, flipL = ActorRenderer.drawOffset("left", frameW, frameH)
local dxR, dyR, flipR = ActorRenderer.drawOffset("right", frameW, frameH)
eq(flipL, 1, "non-square left is never mirrored")
eq(flipR, -1, "non-square right is always mirrored")
eq(dyL, dyR, "non-square: drawY identical regardless of facing (mirroring is horizontal only)")
local leftCenter = dxL + frameW / 2
local rightCenter = dxR - frameW / 2 -- mirrored span runs [drawX-frameW, drawX]
eq(leftCenter, rightCenter,
  "non-square: left and right footprints share the same horizontal center (no sideways snap)")
eq(leftCenter, 16 / 2, "that shared center is the tile's own center (CELL / 2)")

-- down/up are never mirrored and never go through the facing=="right" branch.
local dxDown, _, flipDown = ActorRenderer.drawOffset("down", frameW, frameH)
eq(flipDown, 1, "down is never mirrored")
eq(dxDown, ActorRenderer.anchorOffset(frameW, frameH), "down drawX is the plain anchor offset")

-- ------- behindOffset: pushes a draw position AWAY from the facing
-- direction (toward where the entity came from) -- the large-follower
-- "spacing out" mechanism (lib/follower_adapter.lua).
eq(select(2, ActorRenderer.behindOffset("down", 0)), 0, "zero pushback is always a no-op (dy)")
eq(select(1, ActorRenderer.behindOffset("down", 0)), 0, "zero pushback is always a no-op (dx)")
eq(select(1, ActorRenderer.behindOffset(nil, 10)), 0, "nil pushback amount: no-op (dx)")
local dxD, dyD = ActorRenderer.behindOffset("down", 10)
eq(dxD, 0, "facing down: push is purely vertical (dx)")
eq(dyD, -10, "facing down: pushes UP the screen (away from where 'down' walks toward)")
local dxU, dyU = ActorRenderer.behindOffset("up", 10)
eq(dxU, 0, "facing up: push is purely vertical (dx)")
eq(dyU, 10, "facing up: pushes DOWN the screen (away from where 'up' walks toward)")
local dxL2, dyL2 = ActorRenderer.behindOffset("left", 10)
eq(dxL2, 10, "facing left: pushes RIGHT (away from where 'left' walks toward)")
eq(dyL2, 0, "facing left: push is purely horizontal (dy)")
local dxR2, dyR2 = ActorRenderer.behindOffset("right", 10)
eq(dxR2, -10, "facing right: pushes LEFT (away from where 'right' walks toward)")
eq(dyR2, 0, "facing right: push is purely horizontal (dy)")

-- ------- frameWidth: the whole loaded image's width (frames stack
-- vertically), via a fake mod.assets.image so this needs no real love
-- context -- draw()'s own image-loading fallback chain tries
-- mod.assets.image FIRST.
local fakeImageMod = {
  assets = {
    image = function(_, _path) return { getDimensions = function() return 48, 864 end } end,
  },
}
local rWide = ActorRenderer.new(fakeImageMod, 1, false, SpriteSource.STYLE_POKEMMO)
eq(rWide:frameWidth(), 48, "frameWidth reads the loaded image's own width")

local rNoArt = ActorRenderer.new({}, 999999, false, SpriteSource.STYLE_POKEMMO)
eq(rNoArt:frameWidth(), nil, "frameWidth is nil when no art resolves for this dex")

-- ------- idleFlapPose: walkA, stand, walkB, stand, each held N ticks
eq(ActorRenderer.idleFlapPose(0, 20), "walkA", "idle flap starts on walkA")
eq(ActorRenderer.idleFlapPose(19, 20), "walkA", "idle flap holds a pose for the full tick count")
eq(ActorRenderer.idleFlapPose(20, 20), "stand", "then stands")
eq(ActorRenderer.idleFlapPose(40, 20), "walkB", "then walkB")
eq(ActorRenderer.idleFlapPose(60, 20), "stand", "then stands again")
eq(ActorRenderer.idleFlapPose(80, 20), "walkA", "and wraps")
eq(ActorRenderer.idleFlapPose(nil, 20), "walkA", "nil clock is safe")

-- ------- approach: eased, never overshoots
eq(ActorRenderer.approach(nil, 7, 2), 7, "approach from nothing snaps to target")
eq(ActorRenderer.approach(0, 10, 2), 2, "approach steps toward a far target")
eq(ActorRenderer.approach(0, -10, 2), -2, "approach steps negatively")
eq(ActorRenderer.approach(9, 10, 2), 10, "approach never overshoots")

-- ------- largePushback defaults to 0 (no visual change) until a caller
-- (lib/follower_adapter.lua) sets it.
eq(rDefaultStyle.largePushback, 0, "largePushback defaults to 0")

-- ------- a follower action scene: its facing and offset reach the draw call
do
  local drawn = {}
  local savedLove = love
  love = { graphics = {
    newQuad = function(qx, qy, qw, qh) return { getViewport = function() return qx, qy, qw, qh end, qy = qy } end,
    draw = function(_img, quad, dx, dy, _r, sx) drawn[#drawn + 1] = { quad = quad, x = dx, y = dy, sx = sx } end,
    setColor = function() end,
  } }
  local fakeMod = { assets = { image = function() return { getDimensions = function() return 18, 18 * 18 end } end } }
  local ar = ActorRenderer.new(fakeMod, 4321, false, "pokemmo", "land")
  ar.pushX, ar.pushY = 0, 0
  ar.imagePath = function() return "actor_renderer_test_sheet.png" end -- hermetic: no art needed
  ar:draw(100, 50, 0, 0, "down", POSE_STAND, false)
  local base = drawn[#drawn]
  check(base ~= nil, "a normal draw reaches love.graphics.draw")
  ar.act = { dx = 16, dy = -8, facing = "up" }
  ar:draw(100, 50, 0, 0, "down", POSE_STAND, false)
  local moved = drawn[#drawn]
  check(moved.quad.qy ~= base.quad.qy, "an action's facing replaces the engine's (a different frame row)")
  eq(moved.x, base.x + 16, "an action's x offset moves the sprite")
  eq(moved.y, base.y - 8, "an action's y offset moves the sprite")
  ar.act = nil
  ar:draw(100, 50, 0, 0, "down", POSE_STAND, false)
  eq(drawn[#drawn].x, base.x, "clearing the action restores the normal draw")
  love = savedLove
end

print("")
if failures > 0 then
  io.stderr:write(failures .. " failure(s)\n")
  os.exit(1)
end
print("actor_renderer_unit_test: all passed")
