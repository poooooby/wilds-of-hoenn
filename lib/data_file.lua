-- The baked JSON indexes (assets/pmd/index.json, assets/pmd/portraits.json,
-- assets/atlas/*.json): one place that reads and decodes them, and checks for one
-- without reading it (the PMD index is 1.1 MB).
local V = ...

local DataFile = {}

local function read(mod, rel)
  if not (mod and type(mod.read) == "function") then return nil end
  local ok, data = pcall(mod.read, mod, rel)
  if ok and type(data) == "string" and data ~= "" then return data end
  return nil
end
DataFile.read = read

--- The index at `rel` decoded, or nil when it is missing or not a JSON object / array.
function DataFile.load(mod, rel)
  local raw = read(mod, rel)
  if not raw then return nil end
  local ok, decoded = pcall(V.require("json_decode").decode, raw)
  if ok and type(decoded) == "table" then return decoded end
  return nil
end

--- Whether the file is there, via mod:info (no read); a mod table without `info`
--- (the unit tests' fakes) falls back to reading it.
function DataFile.exists(mod, rel)
  if type(mod) ~= "table" then return false end
  if type(mod.info) == "function" then
    local ok, info = pcall(mod.info, mod, rel)
    return ok and type(info) == "table"
  end
  return read(mod, rel) ~= nil
end

return DataFile
