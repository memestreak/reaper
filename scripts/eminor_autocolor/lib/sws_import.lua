-- lib/sws_import.lua
--
-- Reads SWS Auto Color/Icon/Layout rules from sws-autocoloricon.ini and
-- turns them into eminor Auto Color rules. Pure Lua: tested outside REAPER.
--
-- SWS stores each rule as one line in its [SWS] section:
--   AutoColor 6=2 verse 42649127 "" "" ""
-- which is: type, filter, colour, icon, TCP layout, MCP layout.
--   type    0 track, 1 marker, 2 region
--   colour  0xRRGGBB plus a 0x2000000 "portable" flag, or a negative mode:
--           -1 Custom, -2 Gradient, -3 Random, -4 None, -5 Parent, -6 Ignore
-- The number after "AutoColor" is the priority (1 = top).

local colour = require("lib.colour")

local M = {}

local TARGETS = { [0] = "track", [1] = "marker", [2] = "region" }
local PORTABLE_FLAG = 0x2000000
local MODES = {
  [-1] = "random",   -- SWS "Custom" cycles REAPER's custom colours, which
                     -- macOS doesn't keep in reaper.ini; random is closest
  [-2] = "gradient",
  [-3] = "random",
  [-4] = "none",
  [-5] = "parent",
  [-6] = "ignore",
}

-- Splits a line into tokens the way REAPER's config parser does: spaces
-- separate tokens, and a token may be wrapped in "", '' or ``.
function M.tokenize(line)
  local tokens, i = {}, 1
  while i <= #line do
    local ch = line:sub(i, i)
    if ch:match("%s") then
      i = i + 1
    elseif ch == '"' or ch == "'" or ch == "`" then
      local close = line:find(ch, i + 1, true) or (#line + 1)
      tokens[#tokens + 1] = line:sub(i + 1, close - 1)
      i = close + 1
    else
      local stop = line:find("%s", i) or (#line + 1)
      tokens[#tokens + 1] = line:sub(i, stop - 1)
      i = stop
    end
  end
  return tokens
end

-- Converts SWS's stored colour into a colour spec for the rules file.
-- `from_native` converts an old, unflagged native colour (needs REAPER);
-- it is only used for files written by very old SWS versions.
local function convert_colour(value, from_native)
  if value < 0 then
    local mode = MODES[value]
    if not mode then return { mode = "ignore" } end
    return { mode = mode }
  end
  local rgb
  if value & PORTABLE_FLAG ~= 0 then
    rgb = value & 0xFFFFFF
  elseif from_native then
    rgb = from_native(value)
  else
    rgb = value & 0xFFFFFF
  end
  return { mode = "fixed", rgb = colour.to_hex(rgb) }
end

-- Parses the ini text. Returns:
--   rules     raw rule tables in priority order, ready for rules.check_rule
--   switches  SWS's five on/off switches, keyed like settings.SWITCHES
--   skipped   lines that couldn't be read, as messages
function M.parse(text, from_native)
  local entries, switches, skipped = {}, {}, {}
  local switch_keys = {
    AutoColorEnable = "track_colour",
    AutoIconEnable = "track_icon",
    AutoLayoutEnable = "track_layout",
    AutoColorMarkerEnable = "marker_colour",
    AutoColorRegionEnable = "region_colour",
  }
  local in_sws = false
  for line in (text .. "\n"):gmatch("([^\r\n]*)\r?\n") do
    local section = line:match("^%s*%[(.-)%]")
    if section then
      in_sws = section == "SWS"
    elseif in_sws then
      local key, value = line:match("^%s*([^=]-)%s*=(.*)$")
      if key then
        local priority = tonumber(key:match("^AutoColor (%d+)$"))
        if priority then
          local t = M.tokenize(value)
          local target = TARGETS[tonumber(t[1])]
          local stored = math.tointeger(tonumber(t[3]))
          if target and t[2] and t[2] ~= "" and stored then
            entries[#entries + 1] = {
              priority = priority,
              rule = {
                target = target,
                filter = t[2],
                colour = convert_colour(stored, from_native),
                icon = target == "track" and t[4] or "",
                tcp_layout = target == "track" and t[5] or "",
                mcp_layout = target == "track" and t[6] or "",
              },
            }
          else
            skipped[#skipped + 1] = "could not read " .. key .. "=" .. value
          end
        elseif switch_keys[key] then
          switches[switch_keys[key]] = value:match("^%s*1") ~= nil
        end
      end
    end
  end
  -- The ini lists keys in text order ("AutoColor 10" before "AutoColor 2"),
  -- so sort by the number.
  table.sort(entries, function(a, b) return a.priority < b.priority end)
  local rules = {}
  for i, entry in ipairs(entries) do rules[i] = entry.rule end
  return rules, switches, skipped
end

-- True for the placeholder SWS adds with its Add button and that was never
-- edited: filter "(name)", colour None, no icon or layouts.
function M.is_unused_placeholder(rule)
  return rule.filter == "(name)" and rule.colour.mode == "none"
      and rule.icon == "" and rule.tcp_layout == "" and rule.mcp_layout == ""
end

return M
