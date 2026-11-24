-- lib/json.lua
--
-- Turns a Lua value into JSON text. Encoding only: requests arrive as Lua,
-- so the bridge never has to read JSON.
--
-- Tables with only keys 1..n become arrays; other tables become objects
-- (keys are turned into strings and sorted). An empty table becomes [].
-- Values JSON cannot hold (functions, REAPER pointers) become their
-- tostring() text. NaN and infinity become null.

local M = {}

local MAX_DEPTH = 32

local ESCAPES = {
  ['"'] = '\\"', ["\\"] = "\\\\", ["\b"] = "\\b", ["\f"] = "\\f",
  ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t",
}

local function encode_string(text)
  local escaped = text:gsub('[%c"\\]', function(char)
    return ESCAPES[char] or string.format("\\u%04x", char:byte())
  end)
  return '"' .. escaped .. '"'
end

local function is_array(tbl)
  local count = 0
  for _ in pairs(tbl) do count = count + 1 end
  return count == #tbl
end

local encode_value

local function encode_table(tbl, depth, seen)
  if seen[tbl] then error("cannot encode a table that contains itself") end
  if depth > MAX_DEPTH then error("table is nested too deeply to encode") end
  seen[tbl] = true

  local parts = {}
  local text
  if is_array(tbl) then
    for i = 1, #tbl do
      parts[i] = encode_value(tbl[i], depth + 1, seen)
    end
    text = "[" .. table.concat(parts, ",") .. "]"
  else
    local keys = {}
    for key in pairs(tbl) do keys[#keys + 1] = tostring(key) end
    table.sort(keys)
    local by_text = {}
    for key, value in pairs(tbl) do by_text[tostring(key)] = value end
    for i, key in ipairs(keys) do
      parts[i] = encode_string(key) .. ":" .. encode_value(by_text[key], depth + 1, seen)
    end
    text = "{" .. table.concat(parts, ",") .. "}"
  end

  seen[tbl] = nil
  return text
end

function encode_value(value, depth, seen)
  local kind = type(value)
  if kind == "nil" then
    return "null"
  elseif kind == "boolean" then
    return value and "true" or "false"
  elseif kind == "number" then
    if value ~= value or value == math.huge or value == -math.huge then
      return "null"
    elseif math.type(value) == "integer" then
      return string.format("%d", value)
    end
    return string.format("%.14g", value)
  elseif kind == "string" then
    return encode_string(value)
  elseif kind == "table" then
    return encode_table(value, depth, seen)
  end
  return encode_string(tostring(value))
end

function M.encode(value)
  return encode_value(value, 1, {})
end

return M
