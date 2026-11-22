-- Signature effects: a species' own particles and glow, drawn with its sprite in both styles
-- (PMDCollab and HGSS / PokeMMO), wild Pokemon and the partner alike -- Charmander's tail
-- flame, Pikachu's cheek sparks, Ponyta's mane, Koffing's gas, Swablu's cloud wings, a
-- legendary's glow ... (the list: lib/signature_species.lua). For the partner they stand in
-- for the Type Aura option's generic puffs (lib/follower_adapter.lua).
--
-- WHERE an effect comes from is read from the art itself, per sheet, facing and frame: each
-- emitter has a finder (`find`) -- a colour match (the drawn flame, a red cheek, a white
-- cloud ...), optionally limited to a box of the art, cluster size, the N largest clusters,
-- and clusters that touch a colour they must not (a belly yellow next to a flame yellow).
-- `at` turns the chosen pixels into emitter points: "area" (spread over them), "top" (the
-- top of each cluster, centred), "edge" (those on the art's outline). A frame where nothing
-- matches (a cheek seen from behind) emits nothing. The NORMAL sheet is read (a shiny one
-- has the same layout), once per sheet. A finder may differ per style (`pmd` / `hgss`).
--
-- The renderers call SignatureFx.drawBehind right before the sprite (a glow: the art's own
-- outline, blurred and tinted by a small shader, so it follows every frame) and
-- SignatureFx.drawFront right after it (particles), with the transform the sprite is drawn
-- with -- so every squash, sink, duck, bob, recall and gen3-hd-sprites (WoobleView) size
-- follows (HdField.drawnPoint mirrors how that library grows a sprite about its pivot).
-- Particles live in WORLD px, so they trail behind a walking Pokemon, and age by
-- SignatureFx.clock (main.lua ticks it once per field tick): a paused game holds them still.
local V = ...
local Config = V.require("config")
local HdField = V.require("hd_field")

local function soft(name)
  local ok, m = pcall(V.require, name)
  if ok then return m end
  return nil
end
local SpriteSource = soft("sprite_source")
local Species = V.require("signature_species")

local SignatureFx = {}

SignatureFx.clock = 0
function SignatureFx.tick()
  SignatureFx.clock = SignatureFx.clock + 1
end

-- ------------------------------------------------------------------ species lookup

--- The spec of an art key ("026-alola", "006", 25): its own entry, else -- for a form --
--- the base species' entry when that one says `forms = true` (a legendary's glow fits
--- every form; Galarian Ponyta must not burn). nil = none.
function SignatureFx.specFor(key)
  if key == nil then return nil end
  local s = tostring(key)
  local base = tonumber(s:match("^(%d+)"))
  if not base then return nil end
  local form = s:match("^%d+%-(.+)$")
  if form then
    local own = Species[("%03d-%s"):format(base, form)]
    if own then return own end
    local b = Species[base]
    return (b and b.forms) and b or nil
  end
  return Species[base]
end

-- ------------------------------------------------------------------ colour matching

--- Hue (0..360), saturation and value (0..1) of 0..255 channels. Pure.
function SignatureFx.hsv(r, g, b)
  local mx, mn = math.max(r, g, b), math.min(r, g, b)
  local v, d = mx / 255, mx - mn
  if mx == 0 then return 0, 0, 0 end
  local s = d / mx
  if d == 0 then return 0, s, v end
  local h
  if mx == r then h = (g - b) / d % 6
  elseif mx == g then h = (b - r) / d + 2
  else h = (r - g) / d + 4 end
  return h * 60, s, v
end

local function predOk(p, r, g, b, h, s, v)
  if p.rmin and r < p.rmin then return false end
  if p.rmax and r > p.rmax then return false end
  if p.gmin and g < p.gmin then return false end
  if p.gmax and g > p.gmax then return false end
  if p.bmin and b < p.bmin then return false end
  if p.bmax and b > p.bmax then return false end
  if p.rgmax and r - g > p.rgmax then return false end
  if p.smin and s < p.smin then return false end
  if p.smax and s > p.smax then return false end
  if p.vmin and v < p.vmin then return false end
  if p.vmax and v > p.vmax then return false end
  if p.hmin then
    if p.hmin <= p.hmax then
      if h < p.hmin or h > p.hmax then return false end
    elseif h < p.hmin and h > p.hmax then -- wraps through red
      return false
    end
  end
  return true
end

--- Does a colour match `m`: "body" (any opaque pixel), one predicate table, or a list of
--- them (any). A predicate: rmin/rmax/gmin/gmax/bmin/bmax (0..255), rgmax (r - g), hmin/hmax
--- (degrees; hmin > hmax wraps through red), smin/smax/vmin/vmax (0..1). Pure.
function SignatureFx.matches(m, r, g, b)
  if m == "body" then return true end
  if type(m) ~= "table" then return false end
  local h, s, v = SignatureFx.hsv(r, g, b)
  if m[1] then
    for i = 1, #m do if predOk(m[i], r, g, b, h, s, v) then return true end end
    return false
  end
  return predOk(m, r, g, b, h, s, v)
end

-- ------------------------------------------------------------------ detection

-- evenly picked `n` points (flat x, y list) out of `src` (flat), keeping order
local function thin(src, n)
  local count = #src / 2
  if count <= n then return src end
  local out = {}
  for i = 0, n - 1 do
    local j = math.floor(i * count / n) * 2
    out[#out + 1], out[#out + 2] = src[j + 1], src[j + 2]
  end
  return out
end

local MIRROR = { right = "left", left = "right" }

-- "box": points placed on the art's box per facing (fractions), for a spot no colour marks
-- (the HGSS Pikachu draws no red cheeks). A facing without a list of its own takes its
-- mirror image's, flipped.
local function boxPoints(f, box, facing)
  local list, flip = f.box[facing], false
  if not list and MIRROR[facing] then list, flip = f.box[MIRROR[facing]], true end
  if not list or #list == 0 then return false end
  local bw, bh = box[3] - box[1] + 1, box[4] - box[2] + 1
  local pts = {}
  for _, q in ipairs(list) do
    local fx = flip and (1 - q[1]) or q[1]
    pts[#pts + 1] = box[1] + fx * bw
    pts[#pts + 1] = box[2] + q[2] * bh
  end
  return pts
end

local function findIn(f, px, cw, ch, box, facing)
  if f.box then return boxPoints(f, box, facing) end
  local m, at = f.match, f.at or "area"
  local x0, y0, x1, y1 = 0, 0, cw - 1, ch - 1
  local reg = f.region
  if reg then
    local bw, bh = box[3] - box[1] + 1, box[4] - box[2] + 1
    x0 = math.max(0, math.floor(box[1] + reg[1] * bw))
    y0 = math.max(0, math.floor(box[2] + reg[2] * bh))
    x1 = math.min(cw - 1, math.ceil(box[1] + reg[3] * bw) - 1)
    y1 = math.min(ch - 1, math.ceil(box[2] + reg[4] * bh) - 1)
  end
  local hit, keys = {}, {}
  for y = y0, y1 do
    for x = x0, x1 do
      local r, g, b, a = px(x, y)
      if a > 0 and SignatureFx.matches(m, r, g, b) then
        local k = y * cw + x
        hit[k] = true
        keys[#keys + 1] = k
      end
    end
  end
  if #keys == 0 then return false end
  -- clusters (pixels up to `gap` apart joined)
  local gap = f.gap or 1
  local seen, clusters = {}, {}
  for _, k0 in ipairs(keys) do
    if not seen[k0] then
      seen[k0] = true
      local stack, list, bad = { k0 }, {}, false
      local top, sx, n = math.huge, 0, 0
      while #stack > 0 do
        local k = table.remove(stack)
        local x, y = k % cw, (k - k % cw) / cw
        list[#list + 1] = k
        sx, n = sx + x, n + 1
        if y < top then top = y end
        for dy = -gap, gap do
          for dx = -gap, gap do
            local nx, ny = x + dx, y + dy
            if nx >= 0 and ny >= 0 and nx < cw and ny < ch then
              local nk = ny * cw + nx
              if hit[nk] then
                if not seen[nk] then seen[nk] = true; stack[#stack + 1] = nk end
              elseif f.reject and dx >= -1 and dx <= 1 and dy >= -1 and dy <= 1 then
                local r, g, b, a = px(nx, ny)
                if a > 0 and SignatureFx.matches(f.reject, r, g, b) then bad = true end
              end
            end
          end
        end
      end
      if not bad and n >= (f.minPx or 1) and n <= (f.maxPx or math.huge) then
        -- the top row's pixels, centred (for "top")
        local tx, tn = 0, 0
        for _, k in ipairs(list) do
          if (k - k % cw) / cw == top then tx, tn = tx + k % cw, tn + 1 end
        end
        clusters[#clusters + 1] = { list = list, n = n, top = top, cx = sx / n, tx = tx / tn }
      end
    end
  end
  if #clusters == 0 then return false end
  table.sort(clusters, function(a, b) return a.n > b.n end)
  local take = math.min(#clusters, f.clusters or #clusters)
  local pts = {}
  for i = 1, take do
    local c = clusters[i]
    if at == "top" then
      pts[#pts + 1], pts[#pts + 2] = c.tx + 0.5, c.top + 0.5
    else
      for _, k in ipairs(c.list) do
        local x, y = k % cw, (k - k % cw) / cw
        local ok = true
        if at == "edge" then
          local _, _, _, a1 = px(x - 1, y)
          local _, _, _, a2 = px(x + 1, y)
          local _, _, _, a3 = px(x, y - 1)
          local _, _, _, a4 = px(x, y + 1)
          ok = a1 == 0 or a2 == 0 or a3 == 0 or a4 == 0
        end
        if ok then pts[#pts + 1], pts[#pts + 2] = x + 0.5, y + 0.5 end
      end
    end
  end
  if #pts == 0 then return false end
  return thin(pts, f.samples or 12)
end

--- Emitter points of a sheet: `bytes` = RGBA rows of a `w`-wide sheet of `cw` x `ch`
--- cells, `cols` frames x `rows` facings; `finders` = the emitters' finders; `facingOf(row)`
--- (optional) = the facing a row shows, for "box" finders. Returns
--- out[i][row][col] = flat { x1, y1, x2, y2, ... } (cell px, pixel centres) or false.
--- Pure (tested).
function SignatureFx.detect(bytes, w, cw, ch, cols, rows, finders, facingOf)
  local byte = string.byte
  local out = {}
  for i = 1, #finders do out[i] = {} end
  for row = 0, rows - 1 do
    for i = 1, #finders do out[i][row] = {} end
    for col = 0, cols - 1 do
      local function px(x, y)
        if x < 0 or y < 0 or x >= cw or y >= ch then return 0, 0, 0, 0 end
        local j = ((row * ch + y) * w + col * cw + x) * 4
        return byte(bytes, j + 1, j + 4)
      end
      -- the art's box (for regions)
      local bx0, by0, bx1, by1 = cw, ch, -1, -1
      for y = 0, ch - 1 do
        for x = 0, cw - 1 do
          local _, _, _, a = px(x, y)
          if a > 0 then
            if x < bx0 then bx0 = x end
            if x > bx1 then bx1 = x end
            if y < by0 then by0 = y end
            if y > by1 then by1 = y end
          end
        end
      end
      local box = { bx0, by0, bx1, by1 }
      local facing = facingOf and facingOf(row) or "down"
      for i = 1, #finders do
        out[i][row][col] = bx1 >= 0 and findIn(finders[i], px, cw, ch, box, facing) or false
      end
    end
  end
  return out
end

-- the finder an emitter uses in a style
local function finderOf(em, style)
  return (style and em[style]) or em.find or { match = "body", at = "edge" }
end

local function finderList(spec, style)
  local list = spec._finders and spec._finders[style]
  if list then return list end
  list = {}
  for i, em in ipairs(spec.fx or {}) do list[i] = finderOf(em, style) end
  spec._finders = spec._finders or {}
  spec._finders[style] = list
  return list
end

-- the facing each row shows: a PMD sheet's rows (down, right, up, left; a one-row
-- animation faces `facing`), an HGSS sheet's 18 frames (lib/actor_renderer.lua: 0-2 stand
-- down / up / left, then walk and run in the same order; right = left mirrored)
local PMD_ROWS = { [0] = "down", "right", "up", "left" }
local HGSS_FRAMES = { [0] = "down", "up", "left", "down", "down", "up", "up", "left", "left",
  "down", "down", "down", "up", "up", "up", "left", "left", "left" }
function SignatureFx.facingOfRow(style, row, oneRowFacing)
  if style == "hgss" then return HGSS_FRAMES[row] or "down" end
  if oneRowFacing then return oneRowFacing end
  return PMD_ROWS[row] or "down"
end

-- [path] = points | false (unreadable)
local pointCache = {}

local function sheetPoints(mod, spec, style, path, cw, ch, cols, rows, oneRowFacing)
  local key = path
  local hit = pointCache[key]
  if hit ~= nil then return hit or nil end
  pointCache[key] = false
  local AR = soft("actor_renderer")
  local data = AR and AR.sheetData and AR.sheetData(mod, path)
  if not data then return nil end
  local w, h = data:getDimensions()
  rows = math.min(rows, math.floor(h / ch))
  local pts = SignatureFx.detect(data:getString(), w, cw, ch, cols, rows, finderList(spec, style),
    function(row) return SignatureFx.facingOfRow(style, row, oneRowFacing) end)
  pointCache[key] = pts
  return pts
end

--- Emitter points of a PMD animation (its NORMAL sheet).
function SignatureFx.pmdPoints(mod, info, key, anim, spec)
  local entry = info and info[anim]
  if type(entry) ~= "table" or not (entry.cw and entry.ch and entry.cols) or not SpriteSource then return nil end
  local path = SpriteSource.pmdPath(info, anim, key, false)
  if not path then return nil end
  local rows = tonumber(entry.rows) or 4
  return sheetPoints(mod, spec, "pmd", path, entry.cw, entry.ch, entry.cols, rows,
    rows == 1 and (entry.facing or "down") or nil)
end

--- Emitter points of an HGSS sheet (`frameCount` frames stacked; its NORMAL variant).
local normalPath = {} -- sheet path -> its NORMAL variant's (asked every frame)
function SignatureFx.hgssPoints(mod, path, frameCount, frameW, frameH, spec)
  if type(path) ~= "string" then return nil end
  local normal = normalPath[path]
  if not normal then
    normal = path:gsub("%-shiny%.png$", "-normal.png")
    normalPath[path] = normal
  end
  return sheetPoints(mod, spec, "hgss", normal, frameW, frameH, 1, frameCount)
end

-- ------------------------------------------------------------------ particles

local function rand(st)
  st.seed = (st.seed * 1103515245 + 12345) % 2147483648
  return st.seed / 2147483648
end

local function lerp(a, b, t) return a + (b - a) * t end

--- Colour at age fraction `f` (0 born .. 1 gone) through `colors`. Pure.
function SignatureFx.colorAt(colors, f)
  local n = colors and #colors or 0
  if n == 0 then return 1, 1, 1 end
  local p = math.max(0, math.min(1, f)) * (n - 1)
  local i = math.floor(p)
  if i >= n - 1 then local c = colors[n]; return c[1], c[2], c[3] end
  local t, a, b = p - i, colors[i + 1], colors[i + 2]
  return lerp(a[1], b[1], t), lerp(a[2], b[2], t), lerp(a[3], b[3], t)
end

--- Where a particle is `age` ticks after its birth (offset from where it was born, world
--- px) and how far through its life it is. Pure (tested).
function SignatureFx.offsetAt(p, age, k)
  k = k or p
  local f = age / p.life
  local sway = math.sin((age + p.phase) * (k.swaySpeed or 0.35)) * (k.sway or 0) * p.k
  return p.vx * age + sway, p.vy * age - (k.accel or 0) * age * age * p.k, f
end

-- an emitter's settings: its kind's defaults (Config.SIGNATURE_FX.kinds) under its own
local function settingsOf(em)
  local s = em._s
  if s then return s end
  local cfg = Config.SIGNATURE_FX or {}
  local base = (cfg.kinds or {})[em.kind or "flame"] or {}
  s = {}
  for k, v in pairs(base) do s[k] = v end
  for k, v in pairs(em) do
    if k ~= "find" and k ~= "pmd" and k ~= "hgss" and k ~= "_s" then s[k] = v end
  end
  em._s = s
  return s
end

local function emit(st, s, x, y, k, cfg)
  local parts = st.parts
  local n = st.n + 1
  local p = parts[n]
  if not p then p = {}; parts[n] = p end
  st.n = n
  local spread = (s.spread or 1) * k
  p.s = s
  p.x = x + (rand(st) * 2 - 1) * spread
  p.y = y + (rand(st) * 2 - 1) * spread * 0.5
  p.born = SignatureFx.clock
  p.life = s.life[1] + rand(st) * (s.life[2] - s.life[1])
  local ang = rand(st) * math.pi * 2
  local out = (s.out or 0) * k
  p.vx = (rand(st) * 2 - 1) * (s.drift or 0) * k + math.cos(ang) * out
  p.vy = -(s.rise[1] + rand(st) * (s.rise[2] - s.rise[1])) * k * (s.speed or 1) + math.sin(ang) * out * 0.6
  p.phase = rand(st) * 20
  p.size = (s.size or 1) * (0.75 + rand(st) * 0.5)
  p.k = k
  p.ang = ang
  p.c = (s.palettes and #s.palettes > 0) and s.palettes[1 + math.floor(rand(st) * #s.palettes)] or s.colors
end

local MAX_CATCH_UP = 4

local function stateOf(r)
  local st = r._sig
  if not st then
    local seed = 17
    for c in tostring(r.dex or 1):gmatch(".") do seed = (seed * 31 + c:byte()) % 2147483648 end
    st = { parts = {}, n = 0, acc = {}, seed = seed, phase = seed % 997 }
    r._sig = st
  end
  return st
end

local function drawPart(g, p, s, f, cx, cy, alpha)
  local fade = s.fadeFrom or 0.5
  local a = (f > fade) and (1 - (f - fade) / (1 - fade)) or 1
  if s.fadeIn and f < s.fadeIn then a = a * f / s.fadeIn end
  a = a * (s.alpha or 1)
  if s.flicker and (math.floor(p.phase * 7 + SignatureFx.clock / s.flicker) % 2 == 1) then a = a * (s.flickerAlpha or 0.35) end
  local cr, cg, cb = SignatureFx.colorAt(p.c, f)
  g.setColor(cr, cg, cb, a * (alpha or 1))
  local shape = s.shape or "square"
  local k = p.k
  if shape == "circle" then
    local grow = s.grow or 1
    local rad = math.max(0.5, p.size * k * (1 + (grow - 1) * f))
    g.circle("fill", cx, cy, rad, 8)
  elseif shape == "bolt" then
    local len = (s.length or 4) * p.size * k
    local ux, uy = math.cos(p.ang), math.sin(p.ang)
    local jit = ((p.phase * 13) % 2 - 1) * len * 0.45
    local mx, my = cx + ux * len * 0.5 - uy * jit, cy + uy * len * 0.5 + ux * jit
    g.setLineWidth(math.max(1, k * 0.8))
    g.line(cx, cy, mx, my, cx + ux * len, cy + uy * len)
  elseif shape == "plus" then
    local arm = math.max(1, p.size * k * math.sin(math.pi * math.min(1, f)) * 2)
    local t = math.max(1, math.floor(k * 0.75 + 0.5))
    g.rectangle("fill", math.floor(cx - arm + 0.5), math.floor(cy - t / 2 + 0.5), arm * 2, t)
    g.rectangle("fill", math.floor(cx - t / 2 + 0.5), math.floor(cy - arm + 0.5), t, arm * 2)
  else
    local size = math.max(1, math.floor(p.size * k * (1 - (s.shrink or 0.5) * f) + 0.5))
    g.rectangle("fill", math.floor(cx - size / 2 + 0.5), math.floor(cy - size / 2 + 0.5), size, size)
  end
end

-- age, cull and draw the particles of one pass (behind = true: the ones drawn under it)
local function drawParts(st, behind, camX, camY, alpha)
  local g = love.graphics
  local parts, n, i = st.parts, st.n, 1
  local now = SignatureFx.clock
  local any = false
  while i <= n do
    local p = parts[i]
    local age = now - p.born
    if age >= p.life then
      parts[i], parts[n] = parts[n], p
      n = n - 1
    else
      local s = p.s
      if (s.behind == true) == behind then
        local ox, oy, f = SignatureFx.offsetAt(p, age, s)
        drawPart(g, p, s, f, p.x + ox - camX, p.y + oy - camY, alpha)
        any = true
      end
      i = i + 1
    end
  end
  st.n = n
  if any then g.setColor(1, 1, 1, 1); g.setLineWidth(1) end
end

-- ------------------------------------------------------------------ glow

local GLOW_PAD = 3
local glowShader, glowTried
local GLOW_SRC = [[
extern vec4 rect;
extern vec2 texel;
vec4 effect(vec4 color, Image tex, vec2 uv, vec2 sc) {
  float a = 0.0;
  for (int dy = -3; dy <= 3; dy++) {
    for (int dx = -3; dx <= 3; dx++) {
      vec2 o = vec2(float(dx), float(dy));
      vec2 p = uv + o * texel;
      float w = clamp(1.0 - length(o) / 3.6, 0.0, 1.0);
      if (p.x >= rect.x && p.x <= rect.z && p.y >= rect.y && p.y <= rect.w) {
        a += Texel(tex, p).a * w;
      }
    }
  }
  return vec4(color.rgb, color.a * clamp(a / 5.0, 0.0, 1.0));
}
]]

local function shader()
  if glowTried then return glowShader end
  glowTried = true
  if love and love.graphics and love.graphics.newShader then
    local ok, sh = pcall(love.graphics.newShader, GLOW_SRC)
    if ok then glowShader = sh end
  end
  return glowShader
end

-- the cell's quad grown by GLOW_PAD each way (cached per quad)
local padQuads = setmetatable({}, { __mode = "k" })
local function padQuad(image, quad)
  local q = padQuads[quad]
  if q then return q end
  local qx, qy, qw, qh = quad:getViewport()
  local iw, ih = image:getDimensions()
  q = love.graphics.newQuad(qx - GLOW_PAD, qy - GLOW_PAD, qw + GLOW_PAD * 2, qh + GLOW_PAD * 2, iw, ih)
  padQuads[quad] = q
  return q
end

--- The glow's colour now: its `colors` blended in turn over `cycle` ticks, or a hue
--- wheel (`rainbow`), pulsing between `alpha[1]` and `alpha[2]`. Pure (tested).
function SignatureFx.glowColor(gl, t)
  local cycle = gl.cycle or 180
  local a0, a1 = (gl.alpha or {})[1] or 0.3, (gl.alpha or {})[2] or 0.5
  local pulse = 0.5 - 0.5 * math.cos(t / (gl.pulse or 90) * math.pi * 2)
  local a = a0 + (a1 - a0) * pulse
  if gl.rainbow then
    local h = (t / cycle) % 1 * 6
    local i, f = math.floor(h), h - math.floor(h)
    local r, g, b
    if i == 0 then r, g, b = 1, f, 0 elseif i == 1 then r, g, b = 1 - f, 1, 0
    elseif i == 2 then r, g, b = 0, 1, f elseif i == 3 then r, g, b = 0, 1 - f, 1
    elseif i == 4 then r, g, b = f, 0, 1 else r, g, b = 1, 0, 1 - f end
    return 0.35 + 0.65 * r, 0.35 + 0.65 * g, 0.35 + 0.65 * b, a
  end
  local cs = gl.colors or { { 1, 1, 1 } }
  if #cs == 1 then return cs[1][1], cs[1][2], cs[1][3], a end
  local p = (t / cycle) % 1 * #cs
  local i = math.floor(p)
  local f = 0.5 - 0.5 * math.cos((p - i) * math.pi) -- eased
  local c1, c2 = cs[i + 1], cs[(i + 1) % #cs + 1]
  return lerp(c1[1], c2[1], f), lerp(c1[2], c2[2], f), lerp(c1[3], c2[3], f), a
end

-- ------------------------------------------------------------------ the two passes

-- an effect that fails is switched off for that renderer (and logged once), never the sprite
local warned = {}
local function failed(r, err)
  r._sigSpec = false
  local g = love.graphics
  pcall(g.setShader)
  pcall(g.setColor, 1, 1, 1, 1)
  pcall(g.setLineWidth, 1)
  local key = tostring(r.dex)
  if not warned[key] then
    warned[key] = true
    local log = r.mod and r.mod.log
    if type(log) == "function" then pcall(log, r.mod, "signature effect off for " .. key .. ": " .. tostring(err))
    else print("[wilds_of_hoenn] signature effect off for " .. key .. ": " .. tostring(err)) end
  end
end

--- Called by a renderer right BEFORE its sprite: `r` (the renderer), its spec, the image /
--- quad it draws, where quad px (0, 0) lands on screen (x, y) and its scale (sx, sy),
--- `alpha` (the sprite's). Draws the glow and the particles that go behind it.
-- the glow's uniforms (filled per draw, sent at once) and its draw (no closure a frame)
local glowRect, glowTexel = { 0, 0, 0, 0 }, { 0, 0 }
local function glowBlit(g, image, pq, gx, gy, sx, sy)
  g.draw(image, pq, gx, gy, 0, sx, sy)
end

local function drawBehind(r, spec, image, quad, x, y, sx, sy, camX, camY, alpha)
  local gl = spec.glow
  if gl and image and quad then
    local sh = shader()
    if sh then
      local qx, qy, qw, qh = quad:getViewport()
      local iw, ih = image:getDimensions()
      local pq = padQuad(image, quad)
      local gx, gy, hd = HdField.drawnPoint(r.mod, image, quad, x, y, sx, sy, -GLOW_PAD, -GLOW_PAD)
      local g = love.graphics
      local prev = g.getShader()
      local cr, cg, cb, ca = SignatureFx.glowColor(gl, SignatureFx.clock + stateOf(r).phase)
      glowRect[1], glowRect[2], glowRect[3], glowRect[4] = qx / iw, qy / ih, (qx + qw) / iw, (qy + qh) / ih
      glowTexel[1], glowTexel[2] = 1 / iw, 1 / ih
      local ok = pcall(sh.send, sh, "rect", glowRect) and pcall(sh.send, sh, "texel", glowTexel)
      if ok then
        g.setShader(sh)
        g.setColor(cr, cg, cb, ca * (alpha or 1))
        HdField.untagged(r.mod, image, glowBlit, g, image, pq, gx, gy, sx * hd, sy * hd)
        g.setShader(prev)
        g.setColor(1, 1, 1, 1)
      end
    end
  end
  local st = r._sig
  if st and st.n > 0 then drawParts(st, true, camX, camY, alpha) end
end

--- Called by a renderer right AFTER its sprite (same arguments, plus the emitter points of
--- the sheet drawn, the cell `col` / `row`, and `cutRow`: cell rows from it down are under
--- water -- nothing is born there). Emits and draws the particles in front.
local function drawFront(r, spec, points, col, row, image, quad, x, y, sx, sy, camX, camY, alpha, cutRow)
  local st = stateOf(r)
  local now = SignatureFx.clock
  local fx = spec.fx
  if fx and points and image and quad then
    local steps = math.min(MAX_CATCH_UP, now - (st.last or now - 1))
    if steps > 0 then
      local cfg = Config.SIGNATURE_FX or {}
      local cap = spec.maxParts or cfg.maxParts or 40
      for i, em in ipairs(fx) do
        local byRow = points[i] and points[i][row]
        local pts = byRow and byRow[col]
        if pts then
          local s = settingsOf(em)
          local np = #pts / 2
          local hdk
          for _ = 1, steps do
            st.acc[i] = (st.acc[i] or rand(st)) + 1 / math.max(0.1, s.every or 2)
            while st.acc[i] >= 1 do
              st.acc[i] = st.acc[i] - 1
              for _ = 1, (s.burst or 1) do
                if st.n >= cap then break end
                local j = 1 + math.floor(rand(st) * np) * 2
                local px, py = pts[j], pts[j + 1]
                if not (cutRow and py >= cutRow) then
                  local wx, wy, hd = HdField.drawnPoint(r.mod, image, quad, x, y, sx, sy, px, py)
                  hdk = hdk or math.abs(sx) * hd
                  emit(st, s, wx + camX, wy + camY, hdk, cfg)
                end
              end
            end
            if st.acc[i] > 1 then st.acc[i] = 1 end
          end
        end
      end
    end
  end
  st.last = now
  if st.n > 0 then drawParts(st, false, camX, camY, alpha) end
end

function SignatureFx.drawBehind(r, ...)
  if not (love and love.graphics) then return end
  local ok, err = pcall(drawBehind, r, ...)
  if not ok then failed(r, err) end
end

function SignatureFx.drawFront(r, ...)
  if not (love and love.graphics) then return end
  local ok, err = pcall(drawFront, r, ...)
  if not ok then failed(r, err) end
end

return SignatureFx
