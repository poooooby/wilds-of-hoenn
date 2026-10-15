-- Our Pokemon as sprites a voxel world mod can build cards from (TERRARIUM, Potato Voxel,
-- Dramaless, Stadium2 -- on Red / Blue / Yellow / Gold / Silver / Crystal: lib/engine_gb.lua,
-- lib/compat/).
--
-- A render pipeline mod draws the world itself, from each entity's ENGINE sprite: e:pose()
-- -> sprite, whose `def.image` it loads through src.render.Assets and slices with Gen 1's
-- SpriteRenderer layout (a vertical strip: STAND down / up / left = frames 0-2, WALK =
-- 3-5, right = left mirrored). Our renderers draw HGSS / PMDCollab art of any size, so for
-- each (art key, shiny, style, silhouette, colour mode) this bakes such a strip once: the
-- renderer's own drawing of each pose, rendered into a canvas cell (feet on the cell's
-- bottom edge, centred), read back and registered as a COMPOSED asset
-- (Assets.compose(path, build)) -- so `Assets.image(def.image)` and the mod's palette bake
-- (Assets.imageData) both find it with nothing written to disk. The def carries the real
-- frame size and anchor (frameWidth / frameHeight / anchorX / anchorY, Gen1Recomp's own
-- SpriteDef geometry names); the adapters in lib/compat/ (Wilds of Kanto Revival's) make
-- the cards that size.
--
-- Colour: in a mode that honours true colour the sheet keeps its colours (trueColor =
-- true); otherwise it is baked in the three luminance shades lib/gb_color.lua draws the 2D
-- path with (trueColor = false), so the mod colours it from the map's palette like any
-- vanilla sprite. PMD art is baked on its Idle's first frame (standing) and its Walk's
-- first stride (walking): a card shows one still frame per pose.
local V = ...
local GbColor = V.require("gb_color")
local HdField = V.require("hd_field")
local Config = V.require("config")

local VoxelSheets = {}
VoxelSheets.__index = VoxelSheets

VoxelSheets.FRAMES = 6
-- SpriteRenderer.STAND / WALK (src/render/SpriteRenderer.lua)
VoxelSheets.ROWS = {
  { facing = "down", walk = false }, { facing = "up", walk = false }, { facing = "left", walk = false },
  { facing = "down", walk = true }, { facing = "up", walk = true }, { facing = "left", walk = true },
}
VoxelSheets.MIN_CELL, VoxelSheets.MAX_CELL = 32, 160

--- A square cell side (px, a multiple of 16) that holds art reaching `lift` px above its
--- feet: room for the height and for a wide body.
function VoxelSheets.cellFor(lift)
  lift = tonumber(lift) or 24
  local side = math.ceil(1.6 * (lift + 8) / 16) * 16
  if side < VoxelSheets.MIN_CELL then side = VoxelSheets.MIN_CELL end
  if side > VoxelSheets.MAX_CELL then side = VoxelSheets.MAX_CELL end
  return side
end

--- deps: makeRenderer(key, shiny, style) -> a fresh renderer, assets (src.render.Assets),
--- poses (the ActorRenderer POSE_* constants: STAND, WALK_A).
function VoxelSheets.new(deps)
  return setmetatable({ deps = deps or {}, sprites = {}, data = {} }, VoxelSheets)
end

local function styleOf(r)
  return r.isPmd and "pmd" or (r.style or "pokemmo")
end

-- draws one pose of `r` into the current canvas, its tile at (tx, ty)
local function drawPose(r, row, tx, ty, poses)
  if r.isPmd then
    local entry
    if row.walk then
      r.anim = "walk"
      entry = r.info and r.info.walk
      local d = entry and entry.durations
      r.clock = (type(d) == "table" and tonumber(d[1])) or 0 -- the first stride
    else
      r.anim, r.clock = "idle", 0
    end
    r:draw(tx, ty, 0, 0, row.facing, 0, false)
  else
    r:draw(tx, ty, 0, 0, row.facing, row.walk and poses.WALK_A or poses.STAND, false)
  end
end

-- renders the six poses into an ImageData (cell x cell*6), or nil
local function bake(r, cell, luma, poses)
  local G = love.graphics
  if not (G and G.newCanvas) then return nil end
  local ok, canvas = pcall(G.newCanvas, cell, cell * VoxelSheets.FRAMES)
  if not (ok and canvas) then return nil end
  G.push("all")
  G.origin()
  G.setCanvas(canvas)
  G.clear(0, 0, 0, 0)
  G.setShader()
  G.setColor(1, 1, 1, 1)
  G.setBlendMode("alpha")
  local okDraw, err = pcall(function()
    for i, row in ipairs(VoxelSheets.ROWS) do
      -- the renderer puts the art's feet on the tile's bottom edge, centred on it
      drawPose(r, row, cell / 2 - 8, (i - 1) * cell + cell - 16, poses)
    end
  end)
  G.setCanvas()
  G.pop()
  if not okDraw then error(err, 0) end
  local data = canvas:newImageData()
  canvas:release()
  if luma then
    data:mapPixel(function(_, _, cr, cg, cb, ca)
      if ca <= 0 then return 0, 0, 0, 0 end
      local s = GbColor.shadeOf(cr, cg, cb)
      return s, s, s, ca
    end)
  end
  return data
end

--- The engine-shaped sprite for a renderer's art, or nil (no art, no love). Cached per
--- art key / shiny / style / silhouette / colour mode / species size; the pixels are baked
--- the first time the mod asks for the image (Assets.compose's build), inside its own draw.
--- Species Sizes (HGSS_scale / PMD_scale, lib/hd_field.lua): the card's display size
--- (displayWidth / displayHeight, which the adapters in lib/compat/ honour, the anchor
--- scaled with it) is the frame times the species' factor; the sheet itself is shared.
function VoxelSheets:spriteFor(r, luma)
  if type(r) ~= "table" or r.dex == nil then return nil end
  local style = styleOf(r)
  local sil = r.silhouette and true or false
  local key = table.concat({ tostring(r.dex), r.shiny and "s" or "n", style, sil and "sil" or "",
    luma and "luma" or "color" }, "-")
  local factor = HdField.factorFor(style == "pmd" and "pmd" or "hgss", r.dex)
  -- sized against the shorter Game Boy player (Config.gbSizeRatio; 1 on Gen 3), with
  -- Species Sizes on only -- off, a card keeps its art's own size
  if HdField.speciesSizes then factor = factor * Config.gbSizeRatio() end
  local spriteKey = key .. "@" .. factor
  local hit = self.sprites[spriteKey]
  if hit ~= nil then return hit or nil end
  local deps = self.deps
  local Assets = deps.assets
  local fresh = deps.makeRenderer and deps.makeRenderer(r.dex, r.shiny, style)
  if not (Assets and Assets.compose and fresh) then
    self.sprites[spriteKey] = false
    return nil
  end
  fresh.silhouette = sil
  local lift = fresh.headLift and fresh:headLift() or (fresh.visualHeight and fresh:visualHeight()) or 24
  local cell = VoxelSheets.cellFor(lift)
  local path = "wilds_of_hoenn/voxel/" .. key .. ".png"
  local data = self.data
  if not self.composed then self.composed = {} end
  if not self.composed[path] then self.composed[path] = true Assets.compose(path, function()
    if data[path] == nil then
      local okB, img = pcall(bake, fresh, cell, luma, deps.poses or {})
      data[path] = okB and img or false
    end
    local img = data[path]
    if not img then return love.image.newImageData(1, 1) end
    return img:clone() -- callers may change what they get
  end) end
  local def = {
    id = "WILDS_OF_HOENN_" .. key, image = path, frames = VoxelSheets.FRAMES, walker = true,
    trueColor = not luma, frameWidth = cell, frameHeight = cell, anchorX = cell / 2, anchorY = cell,
    wohVoxel = true,
  }
  if factor ~= 1 then
    def.displayWidth, def.displayHeight = cell * factor, cell * factor
  end
  local sprite = {
    def = def, frameWidth = cell, frameHeight = cell, anchorX = cell / 2, anchorY = cell,
    resolveImage = function() return Assets.image(path) end,
  }
  self.sprites[spriteKey] = sprite
  return sprite
end

return VoxelSheets
