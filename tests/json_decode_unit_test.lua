-- Run: lua tests/json_decode_unit_test.lua
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

local V = {}
function V.require(name) return assert(loadfile("lib/" .. name .. ".lua"))(V) end
local Json = V.require("json_decode")

local function same(a, b)
  if type(a) ~= type(b) then return false end
  if type(a) ~= "table" then return a == b end
  for k, v in pairs(a) do if not same(v, b[k]) then return false end end
  for k in pairs(b) do if a[k] == nil then return false end end
  return true
end

-- values
eq(Json.decode('"plain"'), "plain", "a plain string")
eq(Json.decode('"a\\"b\\\\c\\/d\\n\\t"'), 'a"b\\c/d\n\t', "escapes")
eq(Json.decode('"x\\u0041y"'), "xAy", "\\u escape (ASCII)")
eq(Json.decode('"\\u00e9"'), "\195\169", "\\u escape (2-byte UTF-8)")
eq(Json.decode('"\\u3042"'), "\227\129\130", "\\u escape (3-byte UTF-8)")
eq(Json.decode('"caf\195\169"'), "caf\195\169", "raw UTF-8 passes through")
eq(Json.decode("12"), 12, "an integer")
eq(Json.decode("-3.5e2"), -350, "a negative exponent number")
eq(Json.decode("0.25"), 0.25, "a fraction")
eq(Json.decode("true"), true, "true")
eq(Json.decode("false"), false, "false")
eq(Json.decode("null"), nil, "null")

-- structures, whitespace
check(same(Json.decode(' { "a" : [1, 2, {"b": "c"}], "d": {}, "e": [] } \n'),
  { a = { 1, 2, { b = "c" } }, d = {}, e = {} }), "nested objects and arrays, spaces anywhere")
check(same(Json.decode('{"walk":{"durations":[4,8,4],"ax":12,"ay":20},"k":"v"}'),
  { walk = { durations = { 4, 8, 4 }, ax = 12, ay = 20 }, k = "v" }), "an index-shaped object")
check(same(Json.decode("[\r\n\t1,\r\n\t2\r\n]"), { 1, 2 }), "CR LF and tabs")

-- errors: nil + a message, never a throw
local function bad(text, what)
  local v, err = Json.decode(text)
  check(v == nil and type(err) == "string", what .. " -> nil, " .. tostring(err))
end
bad('"open', "an unterminated string")
bad('"bad \\x escape"', "a bad escape")
bad("[1, 2", "an unterminated array")
bad('{"a" 1}', "a missing colon")
bad("{1: 2}", "a non-string key")
bad("@", "an unexpected token")
local v, err = Json.decode(nil)
check(v == nil and err, "not a string -> nil + message")

if failures > 0 then
  io.stderr:write(("json_decode_unit_test: %d failure(s)\n"):format(failures))
  os.exit(1)
end
print("json_decode_unit_test: all passed")
