-- Minimal JSON decoder for the baked indexes (assets/pmd/index.json, assets/atlas/*.json).
-- A release build loads their Lua twins instead (lib/data_file.lua); this is the
-- fallback, kept quick anyway: it dispatches on byte codes and copies a string's
-- plain runs with string.find / sub instead of character by character (the 1.1 MB
-- PMD index: ~77 -> ~47 ms, 12.7 -> 4.6 MB of garbage, desktop LuaJIT).
local V = ...

local JsonDecode = {}

local byte, sub, find, match, char = string.byte, string.sub, string.find, string.match, string.char
local concat, floor = table.concat, math.floor

local function fail(msg, i)
  return nil, string.format("%s at %d", tostring(msg), tonumber(i) or 0)
end

local parseValue

-- space, tab, CR, LF
local function skipWs(s, i)
  local b = byte(s, i)
  if b == nil or (b ~= 32 and b ~= 9 and b ~= 10 and b ~= 13) then return i end
  local _, j = find(s, "^[ \t\r\n]*", i)
  return (j or (i - 1)) + 1
end

local ESCAPES = {
  [34] = '"', [92] = "\\", [47] = "/",
  [98] = "\b", [102] = "\f", [110] = "\n", [114] = "\r", [116] = "\t",
}

local function utf8(code)
  if code < 128 then return char(code) end
  if code < 0x800 then return char(0xC0 + floor(code / 64), 0x80 + (code % 64)) end
  return char(0xE0 + floor(code / 4096), 0x80 + (floor(code / 64) % 64), 0x80 + (code % 64))
end

local function parseString(s, i)
  if byte(s, i) ~= 34 then return fail("expected string", i) end
  i = i + 1
  local j = find(s, '["\\]', i)
  if not j then return fail("unterminated string", i) end
  if byte(s, j) == 34 then return sub(s, i, j - 1), j + 1 end -- no escapes: one copy
  local out, n = {}, 0
  while true do
    j = find(s, '["\\]', i)
    if not j then return fail("unterminated string", i) end
    if j > i then n = n + 1 out[n] = sub(s, i, j - 1) end
    if byte(s, j) == 34 then return concat(out, "", 1, n), j + 1 end
    local e = byte(s, j + 1)
    local m = ESCAPES[e]
    if m then
      n = n + 1 out[n] = m
      i = j + 2
    elseif e == 117 then -- \uXXXX
      local code = tonumber(sub(s, j + 2, j + 5), 16)
      if not code then return fail("bad unicode escape", j) end
      n = n + 1 out[n] = utf8(code)
      i = j + 6
    else
      return fail("bad escape", j)
    end
  end
end

local function parseArray(s, i)
  if byte(s, i) ~= 91 then return fail("expected [", i) end
  i = skipWs(s, i + 1)
  local arr, n = {}, 0
  if byte(s, i) == 93 then return arr, i + 1 end
  while true do
    local v, nextI = parseValue(s, i)
    if type(nextI) ~= "number" then return nil, v end
    n = n + 1
    arr[n] = v
    i = skipWs(s, nextI)
    local c = byte(s, i)
    if c == 93 then return arr, i + 1 end
    if c ~= 44 then return fail("expected , or ]", i) end
    i = skipWs(s, i + 1)
  end
end

local function parseObject(s, i)
  if byte(s, i) ~= 123 then return fail("expected {", i) end
  i = skipWs(s, i + 1)
  local obj = {}
  if byte(s, i) == 125 then return obj, i + 1 end
  while true do
    local key, nextI = parseString(s, i)
    if type(nextI) ~= "number" then return nil, key end
    i = skipWs(s, nextI)
    if byte(s, i) ~= 58 then return fail("expected :", i) end
    i = skipWs(s, i + 1)
    local val
    val, nextI = parseValue(s, i)
    if type(nextI) ~= "number" then return nil, val end
    obj[key] = val
    i = skipWs(s, nextI)
    local c = byte(s, i)
    if c == 125 then return obj, i + 1 end
    if c ~= 44 then return fail("expected , or }", i) end
    i = skipWs(s, i + 1)
  end
end

parseValue = function(s, i)
  i = skipWs(s, i)
  local c = byte(s, i)
  if c == 34 then
    return parseString(s, i)
  elseif c == 123 then
    return parseObject(s, i)
  elseif c == 91 then
    return parseArray(s, i)
  elseif c == 116 and sub(s, i, i + 3) == "true" then
    return true, i + 4
  elseif c == 102 and sub(s, i, i + 4) == "false" then
    return false, i + 5
  elseif c == 110 and sub(s, i, i + 3) == "null" then
    return nil, i + 4
  elseif c == 45 or (c and c >= 48 and c <= 57) then
    local num = match(s, "^-?%d+%.?%d*[eE]?[+-]?%d*", i)
    if not num then return fail("bad number", i) end
    return tonumber(num), i + #num
  end
  return fail("unexpected token", i)
end

function JsonDecode.decode(text)
  if type(text) ~= "string" then
    return nil, "json text must be a string"
  end
  local value, nextOrErr = parseValue(text, 1)
  if type(nextOrErr) ~= "number" then
    return nil, tostring(value or nextOrErr or "decode failed")
  end
  return value
end

return JsonDecode
