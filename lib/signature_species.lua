-- Which species have a signature effect (lib/signature_fx.lua) and where it comes from.
-- Keyed by national dex number, or by art key for a form ("026-alola"); `forms = true` lets
-- the base entry stand for every form without one of its own (a legendary's glow).
--
-- An entry: `fx` = emitters, each { kind = flame | spark | gas | smoke | cloud | sparkle |
-- glint | wisp | mote (Config.SIGNATURE_FX.kinds), find = finder, pmd = / hgss = a finder
-- for that style instead, plus any kind setting (every, size, colors, ...) }; `glow` = an
-- outline glow { colors, cycle, alpha = {lo, hi}, pulse, rainbow }.
-- A finder: { match = "body" | colour predicate(s), region = {x0, y0, x1, y1} (fractions of
-- the art's box), at = "area" | "top" | "edge", clusters = N largest, minPx, maxPx, gap,
-- reject = colour(s) a cluster may not touch, samples } -- or { box = { down = {{x, y}, ...},
-- left = ..., up = ..., right = ... } }: points on the art's box per facing, for a spot no
-- colour marks (a facing without its own list mirrors left / right). The colours were read
-- off each species' sheets, per style: the PMDCollab sheets share one palette (255, 247, 0
-- yellow, 215, 63, 0 red ...), the HGSS ones each have their own.

-- particle colours
local C = {
  redYellow = { { 1, 0.9, 0.3 }, { 1, 0.55, 0.1 }, { 0.9, 0.2, 0.05 }, { 0.6, 0.1, 0.05 } },
  purpleBlue = { { 0.85, 0.8, 1 }, { 0.55, 0.5, 1 }, { 0.45, 0.25, 0.85 }, { 0.25, 0.1, 0.5 } },
  purpleRed = { { 1, 0.45, 0.3 }, { 0.9, 0.25, 0.6 }, { 0.6, 0.2, 0.75 }, { 0.3, 0.1, 0.45 } },
  purplePink = { { 1, 0.75, 0.95 }, { 0.9, 0.4, 0.85 }, { 0.6, 0.25, 0.8 }, { 0.3, 0.1, 0.45 } },
  pinkFlame = { { 1, 0.85, 0.92 }, { 1, 0.55, 0.75 }, { 0.9, 0.3, 0.55 }, { 0.55, 0.1, 0.3 } },
  tealGreen = { { 0.85, 1, 0.6 }, { 0.35, 0.95, 0.35 }, { 0.0, 0.7, 0.6 }, { 0.0, 0.35, 0.4 } },
  poisonYellow = { { 0.95, 0.92, 0.6 }, { 0.85, 0.8, 0.45 } },
  poisonGreen = { { 0.7, 0.95, 0.55 }, { 0.45, 0.75, 0.35 } },
  ghostPurple = { { 0.75, 0.55, 0.95 }, { 0.55, 0.35, 0.8 } },
  glowYellow = { { 1, 1, 0.75 }, { 1, 0.95, 0.5 } },
}

local function hsv(h0, h1, s0, v0, v1) return { hmin = h0, hmax = h1, smin = s0, vmin = v0, vmax = v1 } end
local function area(match, opts)
  local f = opts or {}
  f.match, f.at = match, f.at or "area"
  return f
end
-- a finder per style
local function F(pmd, hgss) return { pmd = pmd, hgss = hgss } end
local function em(kind, finders, opts)
  local e = opts or {}
  e.kind, e.pmd, e.hgss = kind, finders.pmd, finders.hgss
  return e
end
local function rgb(hex)
  return { tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255 }
end
local function glow(...)
  return { colors = { ... }, alpha = { 0.3, 0.55 } }
end

local S = {}

-- ---------------------------------------------------------------- fire
-- Charmander's line: PMD its flame yellow (255, 247, 0) touching none of the belly's
-- yellows; HGSS the tail flame's red
local charFind = F(
  { match = { rmin = 240, gmin = 230, bmax = 60 }, reject = { rmin = 151, gmin = 101, bmax = 179, rgmax = 79 },
    at = "top", clusters = 1, gap = 2 },
  { match = hsv(350, 8, 0.7, 0.75), at = "top", clusters = 1, gap = 2 })
S[4] = { fx = { em("flame", charFind, { every = 4, size = 1, speed = 0.9 }) } }
S[5] = { fx = { em("flame", charFind, { every = 3, size = 1.1, speed = 1 }) } }
S[6] = { fx = { em("flame", charFind, { every = 2, size = 1.3, speed = 1.15 }) } }

-- Ponyta / Rapidash: the drawn mane, tail and hoof flames
local ponyFind = F(area(hsv(15, 60, 0.95, 0.8), { minPx = 2, samples = 18 }),
  area(hsv(8, 40, 0.85, 0.85), { minPx = 2, samples = 18 }))
S[77] = { fx = { em("flame", ponyFind, { every = 2.5 }) } }
S[78] = { fx = { em("flame", ponyFind, { every = 1.6, size = 1.2 }) } }
-- Magmar: red and yellow flames from the tail tip, yellow from the pointed ears
local magmarTail = { box = { right = { { 0.08, 0.58 } }, up = { { 0.5, 0.86 } } } }
S[126] = { fx = {
  em("flame", F(area(hsv(48, 60, 0.95, 0.9), { region = { 0, 0, 1, 0.3 } }),
    area(hsv(48, 56, 0.95, 0.9), { region = { 0, 0, 1, 0.3 } })), { every = 3, colors = C.redYellow }),
  em("flame", F(magmarTail, magmarTail), { every = 3, colors = C.redYellow }),
} }
S[146] = { fx = { em("flame", F(area(hsv(325, 20, 0.45, 0.6), { minPx = 2, samples = 24 }),
  area(hsv(345, 12, 0.5, 0.6), { minPx = 2, samples = 24 })), { every = 1.4, size = 1.2 }) } }
S["146-galar"] = { fx = { em("flame", F(area(hsv(330, 345, 0.4, 0.85), { minPx = 2, samples = 24 }),
  area(hsv(320, 345, 0.25, 0.85), { samples = 24 })), { every = 1.6, size = 1.2, colors = C.pinkFlame }) } }
-- Cyndaquil's line: PMD shows its red vents only, HGSS the flames themselves
-- (a red touching the cream face or belly is a mouth / eye, not a vent)
local cream = { hmin = 30, hmax = 60, smin = 0.25, smax = 0.6, vmin = 0.8 }
local ventFind = F(area(hsv(355, 20, 0.95, 0.6), { samples = 14, reject = cream }), area(hsv(354, 6, 0.6, 0.6), { samples = 16 }))
S[155] = { fx = { em("flame", ventFind, { every = 1.6, size = 1.2, speed = 1.1 }) } }
S[156] = { fx = { em("flame", ventFind, { every = 1.2, size = 1.3, speed = 1.15 }) } }
S[157] = { fx = { em("flame", ventFind, { every = 1, size = 1.4, speed = 1.2 }) } }
S["157-hisui"] = { fx = { em("flame", F(area(hsv(290, 5, 0.3, 0.65), { samples = 14, reject = cream }),
  area(hsv(295, 355, 0.5, 0.65), { samples = 16 })), { every = 1, size = 1.4, speed = 1.2, colors = C.purpleRed }) } }
-- Alolan Marowak: teal and green flames on both ends of its bone (the PMD art draws none:
-- the bone's two ends, per facing)
S["105-alola"] = { fx = { em("flame", F(
  { box = { down = { { 0.1, 0.2 }, { 0.12, 0.8 } }, up = { { 0.82, 0.22 }, { 0.84, 0.78 } },
    left = { { 0.07, 0.38 }, { 0.58, 0.36 } }, right = { { 0.84, 0.42 }, { 0.48, 0.12 } } } },
  area(hsv(70, 160, 0.45, 0.4), { samples = 12 })), { every = 2, size = 1.3, colors = C.tealGreen }) } }
S[390] = { fx = { em("flame", F(area(hsv(355, 20, 0.95, 0.6), { minPx = 2, gap = 2, reject = cream }),
  area(hsv(355, 10, 0.7, 0.85), { gap = 2 })), { every = 3 }) } }
S[391] = { fx = { em("flame", F(area({ hsv(14, 18, 0.95, 0.85), hsv(48, 60, 0.95, 0.85) }, { minPx = 2 }),
  area({ hsv(355, 10, 0.7, 0.85), hsv(44, 48, 0.95, 0.95) }, { gap = 2 })), { every = 2.5 }) } }
S[392] = { fx = { em("flame", F(area(hsv(48, 60, 0.95, 0.85), { region = { 0, 0, 1, 0.45 }, minPx = 2 }),
  area(hsv(44, 52, 0.95, 0.8), { region = { 0, 0, 1, 0.45 } })), { every = 1.8 }) } }
-- Magmortar: the orange flames of its tail, shoulders and head (not its yellow arms / belly)
S[467] = { fx = { em("flame", F(area(hsv(20, 30, 0.8, 0.95), { minPx = 2, samples = 18 }),
  area(hsv(10, 14, 0.85, 0.92), { region = { 0, 0, 1, 0.55 }, samples = 18 })), { every = 1.6 }) } }
S[500] = { fx = { em("flame", F(area(hsv(28, 60, 0.83, 0.84), { region = { 0, 0, 1, 0.5 }, minPx = 2, samples = 16 }),
  area(hsv(30, 50, 0.95, 0.9), { region = { 0, 0, 1, 0.5 }, samples = 16 })), { every = 1.8 }) } }
S[555] = { fx = { em("flame", F(area(hsv(45, 55, 0.9, 0.9), { region = { 0, 0, 1, 0.45 } }),
  area(hsv(45, 55, 0.9, 0.9), { region = { 0, 0, 1, 0.45 } })), { every = 2.5 }) } }
S[607] = { fx = { em("flame", F(area(hsv(220, 262, 0.3, 0.5), { region = { 0, 0, 1, 0.5 } }),
  area(hsv(230, 262, 0.35, 0.6), { region = { 0, 0, 1, 0.5 } })), { every = 3, colors = C.purpleBlue }) } }
S[609] = { fx = { em("flame", F(area(hsv(220, 260, 0.45, 0.8), { minPx = 2, samples = 18 }),
  area(hsv(245, 256, 0.5, 0.65), { samples = 18 })), { every = 2, colors = C.purpleBlue }) } }
-- Delphox: the burning tip of the stick in its hand (the PMD art draws no stick: at the
-- hand; HGSS: the stick's tip, per facing)
S[655] = { fx = { em("flame", F({ box = { down = { { 0.26, 0.56 } }, right = { { 0.66, 0.55 } } } },
  { box = { down = { { 0.03, 0.36 } }, up = { { 0.97, 0.36 } }, left = { { 0.05, 0.28 } } } }), { every = 3 }) } }
S[727] = { fx = { em("flame", F(area(hsv(52, 60, 0.95, 0.95), { region = { 0, 0.3, 1, 0.85 } }),
  area(hsv(40, 50, 0.55, 0.9), { region = { 0, 0.3, 1, 0.85 } })), { every = 2.5 }) } }
S[851] = { fx = { em("flame", F(area(hsv(15, 55, 0.9, 0.84), { minPx = 2, samples = 18 }),
  area(hsv(12, 60, 0.45, 0.94), { samples = 18 })), { every = 1.6 }) } }
S[910] = { fx = { em("flame", F(area(hsv(35, 56, 0.55, 0.95), { region = { 0, 0, 1, 0.5 }, minPx = 2 }),
  area(hsv(30, 50, 0.6, 0.9), { region = { 0, 0, 1, 0.5 } })), { every = 2.5, life = { 8, 14 }, rise = { 0.15, 0.3 } }) } }
S[911] = { fx = { em("flame", F(area(hsv(30, 56, 0.95, 0.95), { region = { 0, 0, 1, 0.6 }, minPx = 2 }),
  area(hsv(15, 50, 0.9, 0.95), { region = { 0, 0, 1, 0.6 } })), { every = 2 }) } }
-- Charcadet: the little flame on top of its head (drawn pink and blue at its tip)
local cadetTip = { hsv(25, 40, 0.9, 0.85), hsv(280, 330, 0.6, 0.8), hsv(205, 218, 0.8, 0.75) }
S[935] = { fx = { em("flame", F(area(cadetTip, { region = { 0, 0, 1, 0.35 }, at = "top", clusters = 1, gap = 2 }),
  area(cadetTip, { region = { 0, 0, 1, 0.35 }, at = "top", clusters = 1, gap = 2 })), { every = 3 }) } }
S[936] = { fx = { em("flame", F(area(hsv(0, 60, 0.75, 0.8), { region = { 0, 0, 1, 0.3 }, minPx = 2 }),
  area(hsv(0, 60, 0.75, 0.8), { region = { 0, 0, 1, 0.3 } })), { every = 2.2 }) } }
S[937] = { fx = { em("flame", F(area(hsv(215, 305, 0.3, 0.7), { region = { 0, 0, 1, 0.35 } }),
  area(hsv(215, 305, 0.3, 0.68), { region = { 0, 0, 1, 0.35 } })), { every = 2.2, colors = C.purplePink }) } }

-- ---------------------------------------------------------------- electric
S[25] = { fx = { em("spark", F(area({ rmin = 205, rmax = 225, gmin = 53, gmax = 73, bmax = 10 }, { region = { 0, 0.25, 1, 0.85 }, maxPx = 16 }),
  { box = { down = { { 0.22, 0.6 }, { 0.78, 0.6 } }, left = { { 0.3, 0.55 } } } })) } }
S[172] = { fx = { em("spark", F(area({ rmin = 245, gmin = 125, gmax = 145, bmin = 85, bmax = 105 }, { maxPx = 16 }),
  area(hsv(320, 345, 0.4, 0.7)))) } }
S[26] = { fx = { em("spark", F(area(hsv(48, 60, 0.95, 0.95), { region = { 0.1, 0.33, 0.9, 0.62 }, maxPx = 12 }),
  { box = { down = { { 0.25, 0.42 }, { 0.75, 0.42 } }, left = { { 0.32, 0.4 } } } })) } }
S["026-alola"] = { fx = { em("spark", F(
  { box = { down = { { 0.3, 0.53 }, { 0.7, 0.53 } }, left = { { 0.36, 0.53 } } } },
  { box = { down = { { 0.27, 0.56 }, { 0.73, 0.56 } }, left = { { 0.3, 0.56 } } } })) } }
local magnetEnds = F(area({ hsv(340, 20, 0.7, 0.7), hsv(200, 225, 0.65, 0.7) }),
  area({ hsv(350, 10, 0.6, 0.85), hsv(205, 225, 0.6, 0.85) }))
S[81] = { fx = { em("spark", magnetEnds, { every = 12 }) } }
S[82] = { fx = { em("spark", magnetEnds, { every = 8 }) } }
local leftEnd = { match = "body", region = { 0, 0.25, 0.22, 0.85 }, at = "edge", samples = 6 }
local rightEnd = { match = "body", region = { 0.78, 0.25, 1, 0.85 }, at = "edge", samples = 6 }
S[462] = { fx = {
  em("spark", F(leftEnd, leftEnd), { every = 12 }),
  em("spark", F(rightEnd, rightEnd), { every = 12 }),
  em("spark", F(area(hsv(45, 60, 0.9, 0.9), { region = { 0, 0, 1, 0.3 }, at = "top", clusters = 1 }),
    area(hsv(50, 58, 0.9, 0.9), { region = { 0, 0, 1, 0.3 }, at = "top", clusters = 1 })), { every = 16 }),
} }

-- ---------------------------------------------------------------- gas, smoke, clouds
S[92] = { fx = { em("gas", F(area(hsv(255, 275, 0.3, 0.7), { at = "edge", samples = 18 }),
  area(hsv(255, 275, 0.28, 0.55), { at = "edge", samples = 18 })), { every = 6, colors = C.ghostPurple }) } }
S[109] = { fx = { em("gas", F(area(hsv(38, 52, 0.9, 0.6)), area(hsv(44, 56, 0.35, 0.5))), { every = 10, colors = C.poisonYellow }) } }
S[110] = { fx = { em("gas", F(area(hsv(28, 40, 0.5, 0.7)), area(hsv(44, 56, 0.35, 0.5))), { every = 7, colors = C.poisonYellow }) } }
S["110-galar"] = { fx = { em("gas", F(area({ rmin = 250, gmin = 250, bmin = 250 }, { region = { 0, 0, 1, 0.4 } }),
  area({ smax = 0.03, vmin = 0.85 }, { region = { 0, 0, 1, 0.4 } })), { every = 6, colors = C.poisonGreen }) } }
local shellTop = { match = "body", region = { 0.25, 0, 0.75, 0.12 }, at = "edge", samples = 6 }
S[324] = { fx = { em("smoke", F(shellTop, shellTop), { every = 6 }) } }
local wings = F(area({ smax = 0.06, vmin = 0.85 }, { minPx = 4, samples = 16 }),
  area({ smax = 0.12, vmin = 0.88 }, { minPx = 4, samples = 16 }))
S[333] = { fx = { em("cloud", wings, { every = 12 }) } }
S[334] = { fx = { em("cloud", wings, { every = 7 }) } }
local cloudBottom = F(area({ smax = 0.1, vmin = 0.83 }, { region = { 0, 0.55, 1, 1 }, minPx = 3, samples = 16 }),
  area({ smax = 0.08, vmin = 0.8 }, { region = { 0, 0.55, 1, 1 }, minPx = 3, samples = 16 }))
S[641] = { fx = { em("cloud", cloudBottom, { every = 7 }) } }
S[645] = { fx = { em("cloud", cloudBottom, { every = 7 }) } }
S[905] = { fx = { em("cloud", cloudBottom, { every = 7 }) } }

-- ---------------------------------------------------------------- glowing points
local chinFind = F(area(hsv(45, 60, 0.95, 0.85), { minPx = 8 }), area(hsv(40, 46, 0.6, 0.85)))
local lureFind = F(area(hsv(45, 60, 0.95, 0.85), { minPx = 2, region = { 0, 0, 1, 0.3 } }), area(hsv(40, 46, 0.6, 0.85)))
local tipLight = { { 1, 1, 0.9 }, { 1, 0.97, 0.6 } }
S[170] = { fx = {
  em("gleam", chinFind, { colors = tipLight }),
  em("mote", chinFind, { every = 14, colors = C.glowYellow, out = 0.06, life = { 20, 34 } }),
} }
S[171] = { fx = {
  em("gleam", lureFind, { colors = tipLight, size = 1.9 }),
  em("mote", lureFind, { every = 12, colors = C.glowYellow, out = 0.06, life = { 20, 34 } }),
} }

-- ---------------------------------------------------------------- glows (legendaries and the like)
local edge = { match = "body", at = "edge", samples = 24 }
local function glowFx(spec)
  spec.forms = true
  return spec
end
S[150] = glowFx({ glow = glow(rgb("b060ff"), rgb("ff70e0")) })
S[151] = glowFx({ glow = glow(rgb("70f0f0")) })
S[249] = glowFx({ glow = glow(rgb("a8d8ff")) })
S[245] = glowFx({ glow = glow(rgb("60e8e0")) })
S[244] = glowFx({ glow = glow(rgb("ff4830")) })
S[243] = glowFx({ glow = glow(rgb("ffe040")) })
S[250] = glowFx({ fx = { { kind = "sparkle", find = edge, every = 10, out = 0.18 } } })
S[380] = glowFx({ glow = glow(rgb("ff50b0")) })
S[381] = glowFx({ glow = glow(rgb("5080ff")) })
S[382] = glowFx({ glow = glow(rgb("4878ff")) })
S[383] = glowFx({ glow = glow(rgb("ff4030")) })
S[384] = glowFx({ glow = glow(rgb("ff4040")) })
S[385] = glowFx({ glow = glow(rgb("ffe860"), rgb("60f0f0")) })
S[386] = glowFx({ glow = glow(rgb("ff9030"), rgb("30d0c8")) })
S[486] = glowFx({ glow = glow(rgb("ffe050")) })
S[487] = glowFx({ glow = glow(rgb("a050e0")) })
S[490] = glowFx({ glow = glow(rgb("30d8d0")) })
S[491] = glowFx({ glow = glow(rgb("a01828")) })
S[492] = glowFx({ glow = glow(rgb("70e070")) })
S[493] = glowFx({ glow = glow(rgb("ffe060")) })
S[494] = glowFx({ glow = glow(rgb("fff4a0")) })
S[643] = glowFx({ glow = glow(rgb("b0e0ff")) })
S[644] = glowFx({ glow = glow(rgb("ff4030")) })
S[646] = glowFx({ glow = glow(rgb("a0f0ff")) })
S[638] = glowFx({ glow = glow(rgb("40d0c8")) })
S[639] = glowFx({ glow = glow(rgb("ff9a40")) })
S[640] = glowFx({ glow = glow(rgb("60e070")) })
S[647] = glowFx({ glow = glow(rgb("ff4848"), rgb("40d8d0")) })
S[648] = glowFx({ glow = glow(rgb("90f0c0")) })
S[649] = glowFx({ glow = glow(rgb("b060ff")) })
S[716] = glowFx({ glow = { rainbow = true, cycle = 240, alpha = { 0.3, 0.55 } } })
S[717] = glowFx({ glow = glow(rgb("e02030"), rgb("201018")) })
S[718] = glowFx({ glow = glow(rgb("40e060"), rgb("102018")) })
S[719] = glowFx({ glow = glow(rgb("ffb0d0")) })
S[720] = glowFx({ glow = glow(rgb("ff40a0"), rgb("9040e0")) })
S[721] = glowFx({ glow = glow(rgb("901830"), rgb("70c8ff")) })
S[800] = glowFx({ glow = glow(rgb("181020")), fx = { { kind = "wisp", find = edge, every = 7 } } })
S[802] = glowFx({ glow = glow(rgb("101010"), rgb("909090")) })
S[809] = glowFx({ glow = glow(rgb("fff0a0")), fx = { { kind = "glint", find = { match = "body", at = "area", samples = 24 }, every = 40 } } })
S[888] = glowFx({ glow = glow(rgb("4880ff")) })
S[889] = glowFx({ glow = glow(rgb("ff4040")) })
S[890] = glowFx({ glow = glow(rgb("a030e0"), rgb("e02040")),
  fx = { { kind = "wisp", find = edge, every = 7, palettes = { { { 0.7, 0.25, 0.9 }, { 0.45, 0.1, 0.6 } }, { { 0.95, 0.2, 0.3 }, { 0.6, 0.08, 0.15 } } } } } })
S[1007] = glowFx({ glow = glow(rgb("ff2840")) })
S[1008] = glowFx({ glow = glow(rgb("9050ff")) })
S[1014] = glowFx({ glow = glow(rgb("6028a0")) })
S[1015] = glowFx({ glow = glow(rgb("6028a0")) })
S[1016] = glowFx({ glow = glow(rgb("6028a0")) })
S[1017] = glowFx({ glow = glow(rgb("50d860")) })
S[1024] = glowFx({ glow = glow(rgb("40d8d0"), rgb("a050f0"), rgb("4070ff")) })
S[1025] = glowFx({ glow = glow(rgb("a040e0"), rgb("ff60c0")) })

return S
