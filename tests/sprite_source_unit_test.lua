-- Run: lua tests/sprite_source_unit_test.lua
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

local SpriteSource = assert(loadfile("lib/sprite_source.lua"))(nil)

-- Dex 1 (Bulbasaur): real file, primary folder, both variants present.
-- mod:read's real contract is "file contents or nil" (see lib/config.lua's
-- own use of it for options.lua) -- never a plain boolean.
local mod = {
  read = function(_, rel)
    local f = io.open(rel, "rb")
    if not f then return nil end
    local data = f:read("*a")
    f:close()
    return data
  end,
}

local p1 = SpriteSource.normalPath(mod, 1)
check(p1 ~= nil and p1:find("poke_followers", 1, true) ~= nil,
  "dex 1 normal resolves to poke_followers")

-- Dex 252 (Treecko): Pokewilds-only extension range.
local p252 = SpriteSource.normalPath(mod, 252)
check(p252 ~= nil and p252:find("Pokewilds", 1, true) ~= nil,
  "dex 252 normal resolves to Pokewilds (extension range)")

-- Out-of-range dex numbers resolve to nothing, not a garbage path.
eq(SpriteSource.normalPath(mod, 0), nil, "dex 0 resolves to nothing")
eq(SpriteSource.normalPath(mod, 387), nil, "dex 387 (post-Gen3) resolves to nothing")
eq(SpriteSource.normalPath(mod, 999999), nil, "absurd dex resolves to nothing")

-- pathFor: shiny requested and present -> shiny path.
local pShiny = SpriteSource.pathFor(mod, 1, true)
check(pShiny ~= nil and pShiny:find("shiny", 1, true) ~= nil, "pathFor(shiny=true) serves the shiny file")

-- pathFor: shiny requested but genuinely absent for this dex -> falls back
-- to the normal sheet, never a synthesized recolor. Use a fake mod whose
-- `read` reports the shiny file missing but the normal file present.
local fallbackMod = {
  read = function(_, rel)
    if rel:find("shiny", 1, true) then return nil end
    return "present"
  end,
}
local pFallback = SpriteSource.pathFor(fallbackMod, 1, true)
check(pFallback ~= nil and pFallback:find("normal", 1, true) ~= nil,
  "pathFor falls back to normal when no genuine shiny art exists")

-- pathFor: not shiny -> always the normal path regardless of shiny art.
local pNormal = SpriteSource.pathFor(mod, 1, false)
check(pNormal ~= nil and pNormal:find("normal", 1, true) ~= nil, "pathFor(shiny=false) serves normal")

print("")
if failures > 0 then
  io.stderr:write(failures .. " failure(s)\n")
  os.exit(1)
end
print("sprite_source_unit_test: all passed")
