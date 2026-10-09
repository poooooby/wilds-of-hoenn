-- Hands the overworld sprite sheets (wild Pokemon and the follower, both styles) to
-- gen3-hd-sprites when it is installed: the field then draws them at the window's
-- resolution instead of on the game's pixel grid, so they can be any size without
-- lumpy pixels ("Overworld Size") and walkers move smoothly between pixels.
--
-- Without that mod, or with its Field HD option off, this does nothing and the sheets
-- are drawn exactly as before. Every sheet shares one spec table, so a size change
-- applies to the sheets already loaded.
local HdField = {}

-- anchored at the feet: a size change keeps a Pokemon standing on its spot
HdField.spec = { scale = 1, anchor = "feet", filter = "nearest" }

local function library(mod)
  if not (mod and type(mod.find) == "function") then return nil end
  local ok, found = pcall(mod.find, mod, "gen3-hd-sprites")
  local ex = ok and found and found.exports
  if type(ex) ~= "table" or type(ex.tag) ~= "function" then return nil end
  return ex
end

--- Tag one sheet image (from ActorRenderer.loadImage). Safe to call with no library.
function HdField.tag(mod, image)
  if image == nil then return false end
  local ex = library(mod)
  if not ex then return false end
  local ok = pcall(ex.tag, image, HdField.spec)
  return ok
end

--- The "Overworld Size" option: a percentage ("100", "90", ...) -> the shared scale.
function HdField.setSize(value)
  local pct = tonumber(value)
  if not pct or pct <= 0 then pct = 100 end
  HdField.spec.scale = math.max(0.25, math.min(2, pct / 100))
  return HdField.spec.scale
end

return HdField
