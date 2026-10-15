-- How this mod's true-colour art is drawn into a Gen 1 / Gen 2 field (lib/engine_gb.lua).
--
-- Gen 1 colours its whole world canvas AFTER everything is drawn: a palette-zone pass
-- maps each pixel's red channel to the zone's four colours (PaletteFX shader():
-- r > 0.83 -> c0, > 0.5 -> c1, > 0.17 -> c2, else c3). Full-colour art drawn raw into
-- that canvas would come out as noise, so in every mode but the ones that honour true
-- colour (PaletteFX.honorsTrueColor(): ADVANCED / "redpp") the art is drawn through a
-- luminance shader that writes three grey shades -- light, dark, black, never the white
-- key -- and the zone pass then colours our Pokemon like every other sprite (what Wilds
-- of Kanto Revival does with its baked luminance sheets). In a true-colour mode the art
-- is drawn as it is and its rect reported with PaletteFX.markTrueColor, exactly as the
-- engine's own SpriteRenderer does for a trueColor sprite.
--
-- Gen 2 has no such pass (each sprite is coloured when it is drawn), so its art is
-- always drawn as it is.
--
-- Both engines draw a 16x16 walker 4 px above its tile (SpriteRenderer.getScreenOrigin:
-- WORLD_ANCHOR_Y 12 - anchorY 16), while this mod's renderers put the feet on the tile's
-- bottom edge (the Gen 3 way): FOOT_LIFT moves them up to match.
local GbColor = {}

GbColor.FOOT_LIFT = 4

-- the three shades: under 0.83 (never the white key), between the zone thresholds
GbColor.SHADES = { light = 0.72, mid = 0.35, dark = 0.05 }
GbColor.CUTS = { light = 0.55, mid = 0.25 }

local SHADER_SRC = ([[
  vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
    vec4 p = Texel(tex, tc) * color;
    float l = dot(p.rgb, vec3(0.299, 0.587, 0.114));
    float s = l > %.3f ? %.3f : (l > %.3f ? %.3f : %.3f);
    return vec4(s, s, s, p.a);
  }
]]):format(GbColor.CUTS.light, GbColor.SHADES.light, GbColor.CUTS.mid, GbColor.SHADES.mid,
  GbColor.SHADES.dark)

local lumShader -- false = unavailable (headless, no shader support)

local function shader()
  if lumShader == nil then
    local ok, sh = pcall(function() return love.graphics.newShader(SHADER_SRC) end)
    lumShader = ok and sh or false
  end
  return lumShader or nil
end

--- The shade (0..1) a colour (r, g, b in 0..1) is drawn as in the luminance mode. Pure;
--- the shader computes the same thing per pixel.
function GbColor.shadeOf(r, g, b)
  local l = 0.299 * r + 0.587 * g + 0.114 * b
  if l > GbColor.CUTS.light then return GbColor.SHADES.light end
  if l > GbColor.CUTS.mid then return GbColor.SHADES.mid end
  return GbColor.SHADES.dark
end

--- "raw" (draw as is), "mark" (draw as is + report the rect as true colour) or "luma"
--- (draw through the luminance shader), for `generation` and the PaletteFX module.
function GbColor.mode(generation, PaletteFX)
  if generation ~= 1 or type(PaletteFX) ~= "table" then return "raw" end
  local honors = PaletteFX.honorsTrueColor
  if type(honors) == "function" then
    local ok, yes = pcall(honors)
    if ok and yes then return "mark" end
  end
  return "luma"
end

--- Runs `fn` (which draws one actor) the way `mode` says; (x, y, w, h) is a canvas rect
--- that covers what it draws (only used for "mark").
function GbColor.draw(mode, PaletteFX, fn, x, y, w, h)
  if mode == "mark" then
    if PaletteFX and PaletteFX.markTrueColor then pcall(PaletteFX.markTrueColor, x, y, w, h) end
    return fn()
  end
  local sh = mode == "luma" and shader() or nil
  if not sh then return fn() end
  local G = love.graphics
  local prev = G.getShader()
  G.setShader(sh)
  local ok, err = pcall(fn)
  G.setShader(prev)
  if not ok then error(err, 0) end
end

return GbColor
