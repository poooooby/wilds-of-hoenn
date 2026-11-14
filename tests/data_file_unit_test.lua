-- Run: lua tests/data_file_unit_test.lua
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
local V = {}
function V.require(name)
  if modules[name] == nil then modules[name] = assert(loadfile("lib/" .. name .. ".lua"))(V) end
  return modules[name]
end
local DataFile = V.require("data_file")

local files = {
  ["assets/pmd/index.json"] = '{"version":1,"dex":{"25":{"walk":{"frames":4}}}}',
  ["assets/bad.json"] = "{not json",
}
local reads, infos = 0, 0
local mod = {
  read = function(_, rel) reads = reads + 1 return files[rel] end,
  info = function(_, rel) infos = infos + 1 if files[rel] then return { type = "file", size = #files[rel] } end end,
}

local idx = DataFile.load(mod, "assets/pmd/index.json")
check(idx and idx.version == 1 and idx.dex["25"].walk.frames == 4, "load: decoded")
eq(DataFile.load(mod, "assets/none.json"), nil, "load: missing -> nil")
eq(DataFile.load(mod, "assets/bad.json"), nil, "load: malformed -> nil")
eq(DataFile.load(nil, "assets/pmd/index.json"), nil, "load: no mod -> nil")

reads = 0
check(DataFile.exists(mod, "assets/pmd/index.json"), "exists: there")
check(not DataFile.exists(mod, "assets/none.json"), "exists: missing")
eq(reads, 0, "exists asks mod:info, never reads the file")

-- a mod table without info (the other tests' fakes): falls back to reading
local plain = { read = function(_, rel) return files[rel] end }
check(DataFile.exists(plain, "assets/pmd/index.json"), "exists without info: read")
check(not DataFile.exists(plain, "assets/none.json"), "exists without info: missing")
check(not DataFile.exists(nil, "x.json"), "exists: no mod -> false")

-- a throwing read is a miss, not an error
local throwing = { read = function() error("boom") end }
eq(DataFile.load(throwing, "assets/pmd/index.json"), nil, "a throwing read -> nil")

if failures > 0 then
  io.stderr:write(("data_file_unit_test: %d failure(s)\n"):format(failures))
  os.exit(1)
end
print("data_file_unit_test: all passed")
