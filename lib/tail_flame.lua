-- Charmander, Charmeleon and Charizard's tail flame, in the PMDCollab style: a stream of
-- small code-drawn flame particles rising from the tip of the tail.
--
-- Where the tip is comes from the art itself, per animation, facing and frame: the flame
-- is the only bright yellow (255, 247, 0) in these sheets that does not touch the belly's
-- darker yellows / creams, so each cell's largest such cluster (pixels up to 2 apart
-- joined) is the flame, and the top of it (centred across) the emitter. A frame where the tail is hidden behind
-- the body (Charmeleon's raised-arms Idle from the front) has none, and emits nothing. The
-- normal sheet is read (a shiny one has the same layout), once per species and animation.
--
-- lib/pmd_renderer.lua calls TailFlame.draw right after the sprite, with the transform the
-- sprite was drawn with -- so the emitter follows every squash, sink, duck, bob, recall and
-- gen3-hd-sprites (WoobleView) size the sprite gets (HdField.drawnPoint mirrors how that
-- library grows a sprite about its pivot). Particles live in WORLD px, so they trail behind
-- a walking Pokemon; they age by TailFlame.clock (main.lua ticks it once per field tick),
-- so they hold still while the game is paused.
local V = ...
local Config = V.require("config")
local SpriteSource = V.require("sprite_source")
local ActorRenderer = V.require("actor_renderer")
local HdField = V.require("hd_field")

local TailFlame = {}

TailFlame.clock = 0
function TailFlame.tick()
  TailFlame.clock = TailFlame.clock + 1
end

--- The species' flame settings (Config.TAIL_FLAME.species), by art key or dex; nil = none.
function TailFlame.settingsFor(dex)
  local cfg = Config.TAIL_FLAME
  local species = cfg and cfg.species
  if not species or dex == nil then return nil end
  local base = tonumber(dex) or tonumber(tostring(dex):match("^(%d+)"))
  return base and species[base] or nil
end

local function isFlame(r, g, b) return r >= 240 and g >= 230 and b <= 60 end
-- the belly's yellows / creams (and their shading): darker or paler than the flame's yellow
local function isWarm(r, g, b)
  return not isFlame(r, g, b) and r > 150 and g > 100 and b < 180 and r - g < 80
end

--- Where the flame burns in each cell of a sheet (the top of its yellow core, centred): `bytes` = RGBA rows of a `w`-wide sheet of
--- `cw` x `ch` cells, `cols` frames x `rows` facings. Returns points[row][col] = { x, y }
--- (cell px, pixel centres) or false where no flame shows. Pure (tested).
function TailFlame.detect(bytes, w, cw, ch, cols, rows)
  local byte = string.byte
  local out = {}
  for row = 0, rows - 1 do
    local list = {}
    out[row] = list
    for col = 0, cols - 1 do
      local function px(x, y)
        if x < 0 or y < 0 or x >= cw or y >= ch then return 0, 0, 0, 0 end
        local i = ((row * ch + y) * w + col * cw + x) * 4
        return byte(bytes, i + 1, i + 4)
      end
      local flame, keys = {}, {}
      for y = 0, ch - 1 do
        for x = 0, cw - 1 do
          local r, g, b, a = px(x, y)
          if a > 0 and isFlame(r, g, b) then
            local k = y * cw + x
            flame[k] = true
            keys[#keys + 1] = k
          end
        end
      end
      local seen, best, bestN = {}, nil, 0
      for _, k0 in ipairs(keys) do
        if not seen[k0] then
          seen[k0] = true
          local stack, sx, top, n, warm = { k0 }, 0, math.huge, 0, false
          while #stack > 0 do
            local k = table.remove(stack)
            local x, y = k % cw, math.floor(k / cw)
            sx, n = sx + x, n + 1
            if y < top then top = y end
            for dy = -2, 2 do
              for dx = -2, 2 do
                local nx, ny = x + dx, y + dy
                if nx >= 0 and ny >= 0 and nx < cw and ny < ch then
                  local nk = ny * cw + nx
                  if flame[nk] then
                    if not seen[nk] then seen[nk] = true; stack[#stack + 1] = nk end
                  elseif dx >= -1 and dx <= 1 and dy >= -1 and dy <= 1 then
                    local r, g, b, a = px(nx, ny)
                    if a > 0 and isWarm(r, g, b) then warm = true end
                  end
                end
              end
            end
          end
          if not warm and n > bestN then best, bestN = { sx / n + 0.5, top + 0.5 }, n end
        end
      end
      list[col] = best or false
    end
  end
  return out
end

-- [dex .. "/" .. anim] = points (false = unreadable / no such sheet)
local pointCache = {}

--- The flame points of `anim` for a renderer's species (read from its NORMAL sheet).
function TailFlame.pointsFor(mod, info, dex, anim)
  local key = tostring(dex) .. "/" .. anim
  local hit = pointCache[key]
  if hit ~= nil then return hit or nil end
  pointCache[key] = false
  local entry = info and info[anim]
  if type(entry) ~= "table" or not (entry.cw and entry.ch and entry.cols) then return nil end
  local path = SpriteSource.pmdPath(info, anim, dex, false)
  local data = path and ActorRenderer.sheetData(mod, path)
  if not data then return nil end
  local w, h = data:getDimensions()
  local rows = math.min(tonumber(entry.rows) or 4, math.floor(h / entry.ch))
  local points = TailFlame.detect(data:getString(), w, entry.cw, entry.ch, entry.cols, rows)
  pointCache[key] = points
  return points
end

-- a tiny LCG per flame: the particles never touch math.random's state
local function rand(st)
  st.seed = (st.seed * 1103515245 + 12345) % 2147483648
  return st.seed / 2147483648
end

local function lerp(a, b, t) return a + (b - a) * t end

--- Particle colour at age fraction `f` (0 born .. 1 gone) through `colors`. Pure.
function TailFlame.colorAt(colors, f)
  local n = #colors
  if n == 0 then return 1, 1, 1 end
  local p = math.max(0, math.min(1, f)) * (n - 1)
  local i = math.floor(p)
  if i >= n - 1 then local c = colors[n]; return c[1], c[2], c[3] end
  local t, a, b = p - i, colors[i + 1], colors[i + 2]
  return lerp(a[1], b[1], t), lerp(a[2], b[2], t), lerp(a[3], b[3], t)
end

--- Where a particle is `age` ticks after its birth (offset from where it was born, world
--- px) and how far through its life it is. Pure (tested).
function TailFlame.offsetAt(p, age, cfg)
  local f = age / p.life
  local sway = math.sin((age + p.phase) * (cfg.swaySpeed or 0.35)) * (cfg.sway or 0) * p.k
  return p.vx * age + sway, p.vy * age - (cfg.accel or 0) * age * age * p.k, f
end

local function emit(st, s, cfg, x, y, k)
  local parts = st.parts
  local n = st.n + 1
  local p = parts[n]
  if not p then p = {}; parts[n] = p end
  st.n = n
  local spread = (cfg.spread or 1) * k
  local lo, hi = cfg.life[1], cfg.life[2]
  p.x = x + (rand(st) * 2 - 1) * spread
  p.y = y + (rand(st) * 2 - 1) * spread * 0.5
  p.born = TailFlame.clock
  p.life = lo + rand(st) * (hi - lo)
  p.vx = (rand(st) * 2 - 1) * (cfg.drift or 0) * k
  p.vy = -(cfg.rise[1] + rand(st) * (cfg.rise[2] - cfg.rise[1])) * k * (s.speed or 1)
  p.phase = rand(st) * 20
  p.size = (s.size or 1) * (0.75 + rand(st) * 0.5)
  p.k = k
end

local MAX_CATCH_UP = 4 -- ticks of emission made up after a frame without a draw

--- Draw `r`'s flame (a PmdRenderer, right after its sprite). `points` = this animation's
--- flame points, `col`/`row` the cell drawn, `image`/`quad` what was drawn at screen (dx,
--- dy) with (sx, sy), `camX/camY` the camera, `alpha` the sprite's. `cutRow` (optional):
--- cell rows from it down are under water -- no flame there.
function TailFlame.draw(r, s, points, col, row, image, quad, dx, dy, sx, sy, camX, camY, alpha, cutRow)
  local cfg = Config.TAIL_FLAME
  if not (cfg and love and love.graphics) then return end
  local st = r._flame
  if not st then
    st = { parts = {}, n = 0, acc = 0, seed = (tonumber(r.dex) or 1) * 7919 + 17 }
    r._flame = st
  end
  local now = TailFlame.clock
  local pts = points and points[row]
  local pt = pts and pts[col]
  if pt and cutRow and pt[2] >= cutRow then pt = nil end
  -- the emitter where the sprite is drawn now, in world px
  if pt then
    local x, y, hd = HdField.drawnPoint(r.mod, image, quad, dx, dy, sx, sy, pt[1], pt[2])
    local k = math.abs(sx) * hd
    local wx, wy = x + camX, y + camY
    local steps = math.min(MAX_CATCH_UP, now - (st.last or now - 1))
    if steps > 0 then
      local fromX, fromY = st.ex or wx, st.ey or wy
      for i = 1, steps do
        st.acc = st.acc + 1 / math.max(0.1, s.every or 2)
        local t = i / steps
        while st.acc >= 1 and st.n < (cfg.maxParts or 24) do
          st.acc = st.acc - 1
          emit(st, s, cfg, lerp(fromX, wx, t), lerp(fromY, wy, t), k)
        end
        if st.acc > 1 then st.acc = 1 end
      end
    end
    st.ex, st.ey = wx, wy
  else
    st.ex, st.ey = nil, nil
  end
  st.last = now
  -- age, cull and draw (alive ones are kept in parts[1..n])
  local parts, n, i = st.parts, st.n, 1
  local fade = cfg.fadeFrom or 0.55
  local g = love.graphics
  while i <= n do
    local p = parts[i]
    local age = now - p.born
    if age >= p.life then
      parts[i], parts[n] = parts[n], p
      n = n - 1
    else
      local ox, oy, f = TailFlame.offsetAt(p, age, cfg)
      local cr, cg, cb = TailFlame.colorAt(cfg.colors, f)
      local a = (f > fade) and (1 - (f - fade) / (1 - fade)) or 1
      local size = math.max(1, math.floor(p.size * p.k * (1 - 0.5 * f) + 0.5))
      g.setColor(cr, cg, cb, a * (alpha or 1))
      g.rectangle("fill", math.floor(p.x + ox - camX - size / 2 + 0.5), math.floor(p.y + oy - camY - size / 2 + 0.5), size, size)
      i = i + 1
    end
  end
  st.n = n
  if n > 0 then g.setColor(1, 1, 1, 1) end
end

return TailFlame
