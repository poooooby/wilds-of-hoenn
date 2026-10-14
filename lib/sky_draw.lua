-- Draws flying Pokemon (lib/sky_flyers.lua's birds and wild Pokemon arriving / leaving by
-- air) as field actors, at their height's look (lib/flight_path.lua).
--
-- Low birds (h below Config.FLYERS.sharpBelow) draw through their own renderer like any
-- wild Pokemon, so gen3-hd-sprites sizes them at window resolution. Higher ones are out
-- of focus: the current frame is rendered once per tick into a small canvas of its own
-- (`prepare`, called from the TICK, never inside the field's draw pass, where
-- gen3-hd-sprites is capturing), and that canvas is drawn blurred and hazed with a small
-- shader. The canvas is never tagged, so it takes none of gen3-hd-sprites' field layers.
-- Between sharpBelow and sharpAbove both are drawn, crossfading, so the switch never pops.
-- No shader / canvas (an old GPU): the blur is left out, the haze and fade stay.
--
-- Every sky actor is drawn after the map's upper layer (roofs, tree crowns): oamPriority
-- 1 (field_view.lua actorPriority), with a fixed subpriority, higher birds last. Birds cast
-- no ground shadow.
local V = ...
local Config = V.require("config")
local FlightPath = V.require("flight_path")

local SkyDraw = {}

local CANVAS = 128              -- px, square; a sprite's tile sits at TILE_X, TILE_Y in it
local TILE_X, TILE_Y = 56, 96   -- so its feet are at (64, 112), room above for tall art
local FOOT_X, FOOT_Y = TILE_X + 8, TILE_Y + 16
SkyDraw.CANVAS, SkyDraw.FOOT_X, SkyDraw.FOOT_Y = CANVAS, FOOT_X, FOOT_Y

local shader -- nil = not tried, false = unavailable
local SHADER_SRC = [[
extern vec2 texel;
extern float radius;
extern vec3 haze;
extern float hazeAmount;
vec4 effect(vec4 color, Image tex, vec2 uv, vec2 sc) {
  vec4 sum = vec4(0.0);
  float wsum = 0.0;
  for (int i = -2; i <= 2; i++) {
    for (int j = -2; j <= 2; j++) {
      float w = exp(-float(i * i + j * j) / 4.5);
      sum += Texel(tex, uv + vec2(float(i), float(j)) * texel * radius * 0.5) * w;
      wsum += w;
    }
  }
  vec4 c = sum / wsum;               // premultiplied (a canvas), so averaging is exact
  c.rgb = mix(c.rgb, haze * c.a, hazeAmount);
  return c * color;
}
]]

local function blurShader()
  if shader ~= nil then return shader or nil end
  shader = false
  if love and love.graphics and love.graphics.newShader then
    local ok, sh = pcall(love.graphics.newShader, SHADER_SRC)
    if ok and sh then shader = sh end
  end
  return shader or nil
end

local pool = {}   -- free canvases
local canvases = setmetatable({}, { __mode = "k" }) -- bird -> its canvas

local function newCanvas()
  if not (love and love.graphics and love.graphics.newCanvas) then return nil end
  local ok, c = pcall(love.graphics.newCanvas, CANVAS, CANVAS, { dpiscale = 1 })
  if not ok then ok, c = pcall(love.graphics.newCanvas, CANVAS, CANVAS) end
  if not (ok and c) then return nil end
  pcall(c.setFilter, c, "linear", "linear")
  return c
end

--- Gives `bird`'s canvas back (it left the sky).
function SkyDraw.release(bird)
  local c = canvases[bird]
  if c then
    canvases[bird] = nil
    pool[#pool + 1] = c
  end
end

--- Does a bird at height `h` draw blurred (needs its canvas prepared)?
function SkyDraw.blurred(h)
  return (tonumber(h) or 0) > Config.FLYERS.sharpBelow
end

--- How much of the sharp sprite / the blurred canvas shows at height `h` (crossfade).
function SkyDraw.mix(h)
  local lo, hi = Config.FLYERS.sharpBelow, Config.FLYERS.sharpAbove
  h = tonumber(h) or 0
  if h <= lo then return 1, 0 end
  if h >= hi then return 0, 1 end
  local t = (h - lo) / (hi - lo)
  return 1 - t, t
end

--- Renders `bird`'s current frame into its canvas. Called from the tick. `bird` =
--- { renderer, facing, pose }. Returns true when it has a canvas to draw.
function SkyDraw.prepare(bird)
  local g = love and love.graphics
  if not (g and g.setCanvas and bird.renderer) then return false end
  local c = canvases[bird]
  if not c then
    c = table.remove(pool) or newCanvas()
    if not c then return false end
    canvases[bird] = c
  end
  local ok = pcall(function()
    g.push("all")
    g.setCanvas(c)
    g.clear(0, 0, 0, 0)
    g.origin()
    g.setShader()
    g.setBlendMode("alpha", "alphamultiply")
    g.setColor(1, 1, 1, 1)
    local r = bird.renderer
    local act = r.act
    r.act = nil -- drawn plain here; height, lift and fade are applied when the canvas is drawn
    local alpha, sil = r.alpha, r.silhouette
    r.alpha = nil
    if bird.silhouette ~= nil then r.silhouette = bird.silhouette end -- a fish's shadow under water
    local okDraw = pcall(r.draw, r, TILE_X, TILE_Y, 0, 0, bird.facing or "down", bird.pose)
    r.act, r.alpha, r.silhouette = act, alpha, sil
    g.pop()
    return okDraw
  end)
  if not ok then pcall(function() g.setCanvas() g.pop() end) end
  return ok
end

-- ------- actors ------------------------------------------------------------

--- Appends the actors for one bird: `bird` = { id, renderer, x, y (world px of its
--- ground point's tile), h, lift (px up: a perch), hop (px up), sink, facing, pose,
--- alpha (extra fade), silhouette (true / false: drawn as a dark shape or not, whatever
--- the renderer's own setting; nil = its own), layers (a swimmer's depth layers) }.
--- (camX, camY, vw, vh) = the view. Nothing when it is hidden.
function SkyDraw.push(actors, bird, camX, camY, vw, vh)
  if bird.hidden then return end
  local look = FlightPath.look(bird.h, bird.layers) -- (a swimmer brings its own depth layers)
  local id = tonumber(bird.id) or 0
  local sharp, soft = SkyDraw.mix(bird.h)
  local sub = math.max(0, 40 - math.floor(look.parallax * 20)) -- higher birds draw later
  -- where it is seen: perspective about the view's centre (FlightPath.toScreen), as a
  -- world point the renderer can be handed with the real camera
  local sx, sy = FlightPath.toScreen(bird.x, bird.y, look.parallax, camX or 0, camY or 0, vw, vh)
  local up = (bird.lift or 0) + (bird.hop or 0)
  local swayX, swayY = bird.swayX or 0, bird.swayY or 0 -- a swimming fish's wiggle
  if sharp > 0 then
    local r = bird.renderer
    actors[#actors + 1] = {
      kind = "sky_mon", x = sx + (camX or 0), y = sy + (camY or 0), sortY = sy + (camY or 0), elevation = 3,
      i = 93500 + id, fixedPriority = true, priority = 1, subpriority = sub,
      draw = function(_, cX, cY)
        local act, alpha, sil = r.act, r.alpha, r.silhouette
        r.act = { scale = look.scale, dx = swayX, dy = swayY - up, sink = bird.sink, facing = bird.facing }
        -- the layer's own transparency too (1 for a low bird; a fish's shadow is see-through)
        r.alpha = sharp * (bird.alpha or 1) * look.alpha
        if bird.silhouette ~= nil then r.silhouette = bird.silhouette end
        r:draw(sx + cX, sy + cY, cX, cY, bird.facing or "down", bird.pose)
        r.act, r.alpha, r.silhouette = act, alpha, sil
      end,
    }
  end
  local c = soft > 0 and canvases[bird]
  if c then
    local alpha = soft * look.alpha * (bird.alpha or 1)
    actors[#actors + 1] = {
      kind = "sky_mon_far", x = sx + (camX or 0), y = sy + (camY or 0), sortY = sy + (camY or 0), elevation = 3,
      i = 94000 + id, fixedPriority = true, priority = 1, subpriority = math.max(0, sub - 1),
      draw = function(_, cX, cY)
        local g = love.graphics
        local pr, pg, pb, pa = g.getColor()
        local bm, am = g.getBlendMode()
        local sh = blurShader()
        if sh then
          local okS = pcall(function()
            sh:send("texel", { 1 / CANVAS, 1 / CANVAS })
            sh:send("radius", look.blur / math.max(0.5, look.scale)) -- blur px as drawn
            sh:send("haze", Config.FLYERS.haze)
            sh:send("hazeAmount", look.haze)
          end)
          if okS then g.setShader(sh) else sh = nil end
        end
        g.setBlendMode("alpha", "premultiplied")
        g.setColor(alpha, alpha, alpha, alpha)
        -- the canvas's feet point on the bird's tile feet point, grown about it
        g.draw(c, sx + 8 + swayX * look.scale, sy + 16 + (swayY - up) * look.scale, 0, look.scale, look.scale, FOOT_X, FOOT_Y)
        if sh then g.setShader() end
        g.setBlendMode(bm, am)
        g.setColor(pr, pg, pb, pa)
      end,
    }
  end
end

return SkyDraw
