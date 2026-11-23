-- lib/sws_switches.lua
--
-- SWS's own Auto Color/Icon/Layout on/off switches. They are SWS actions
-- with toggle states, so we read and flip them through the Action List.
-- When SWS isn't installed, NamedCommandLookup finds nothing and every
-- switch reads as missing.

local M = {}

-- Same order and keys as settings.SWITCHES, so each pairs with ours.
M.LIST = {
  { key = "track_colour", command = "_SWSAUTOCOLOR_ENABLE",
    label = "Auto track coloring" },        -- SWS: Toggle auto track coloring enable
  { key = "track_icon", command = "_S&MAUTOICON_ENABLE",
    label = "Auto track icon" },            -- SWS/S&M: Toggle auto track icon enable
  { key = "track_layout", command = "_S&MAUTOLAYOUT_ENABLE",
    label = "Auto track layout" },          -- SWS/S&M: Toggle auto track layout enable
  { key = "marker_colour", command = "_S&MAUTOCOLOR_MKR_ENABLE",
    label = "Auto marker coloring" },       -- SWS/S&M: Toggle auto marker coloring enable
  { key = "region_colour", command = "_S&MAUTOCOLOR_RGN_ENABLE",
    label = "Auto region coloring" },       -- SWS/S&M: Toggle auto region coloring enable
}

local MAIN_SECTION = 0

local function command_id(switch)
  local id = reaper.NamedCommandLookup(switch.command)
  if id and id ~= 0 then return id end
  return nil
end

-- True when SWS's Auto Color actions are there.
function M.installed()
  return command_id(M.LIST[1]) ~= nil
end

-- { key -> true/false } for the switches that exist.
function M.read()
  local states = {}
  for _, switch in ipairs(M.LIST) do
    local id = command_id(switch)
    if id then states[switch.key] = reaper.GetToggleCommandState(id) == 1 end
  end
  return states
end

-- Turns one SWS switch on or off (only runs its action if it must change).
function M.set(key, on)
  for _, switch in ipairs(M.LIST) do
    if switch.key == key then
      local id = command_id(switch)
      if not id then return false end
      if (reaper.GetToggleCommandState(id) == 1) ~= on then
        reaper.Main_OnCommand(id, 0)
      end
      return true
    end
  end
  return false
end

return M
