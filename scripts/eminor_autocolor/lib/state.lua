-- lib/state.lua
--
-- What this script last set on a track, marker or region, stored as short
-- text so it saves with the project. For example:
--   c=16777215;r=r3;s=2;i=guitar.png;t=Wide;h=1
--
-- Keys (all optional):
--   c  native colour this script last set (0 = it cleared the colour)
--   r  id of the rule that set the colour
--   s  family slot, for "family" rules
--   i  icon this script set, as a name under Data/track_icons
--   t  TCP layout this script set
--   m  MCP layout this script set
--   h  which panels this script hid the track in: 1 = TCP, 2 = MCP, 3 = both
--
-- Text values are %-escaped, so names may hold ";" or "=".
-- Pure Lua: tested outside REAPER.

local M = {}

M.HIDDEN_TCP = 1
M.HIDDEN_MCP = 2

local NUMBER_KEYS = { c = true, s = true, h = true }
local TEXT_KEYS = { r = true, i = true, t = true, m = true }
local ORDER = { "c", "r", "s", "i", "t", "m", "h" }

local function escape(text)
  return (text:gsub("[%%;=]", function(ch) return string.format("%%%02X", ch:byte()) end))
end

local function unescape(text)
  return (text:gsub("%%(%x%x)", function(hex) return string.char(tonumber(hex, 16)) end))
end

function M.parse(text)
  local state = {}
  for key, value in (text or ""):gmatch("(%a)=([^;]*)") do
    if NUMBER_KEYS[key] then
      state[key] = math.tointeger(tonumber(value))
    elseif TEXT_KEYS[key] then
      state[key] = unescape(value)
    end
  end
  return state
end

function M.format(state)
  local parts = {}
  for _, key in ipairs(ORDER) do
    local value = state[key]
    if value ~= nil then
      if TEXT_KEYS[key] then value = escape(value) end
      parts[#parts + 1] = key .. "=" .. value
    end
  end
  return table.concat(parts, ";")
end

return M
