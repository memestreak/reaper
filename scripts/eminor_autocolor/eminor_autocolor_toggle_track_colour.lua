-- eminor_autocolor_toggle_track_colour.lua
--
-- Action: turn automatic track colouring on or off. Its toggle state shows
-- on toolbars. The running engine picks the change up at once.

local here = debug.getinfo(1, "S").source:match("^@?(.*[/\\])")
package.path = here .. "?.lua;" .. package.path

local settings = require("lib.settings")

local SWITCH = "track_colour"
local MAIN_SECTION = 0

local _, _, _, command_id = reaper.get_action_context()
settings.remember_toggle_command(SWITCH, command_id)

local on = not settings.read_switches()[SWITCH]
settings.set_switch(SWITCH, on)
reaper.SetToggleCommandState(MAIN_SECTION, command_id, on and 1 or 0)
reaper.RefreshToolbar2(MAIN_SECTION, command_id)
