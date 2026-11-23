-- eminor_autocolor_toggle_track_layout.lua
--
-- Action: turn automatic track layouts on or off (TCP and MCP layouts,
-- including "(hide)"). Its toggle state shows on toolbars. The running
-- engine picks the change up at once.

local here = debug.getinfo(1, "S").source:match("^@?(.*[/\\])")
package.path = here .. "?.lua;" .. package.path

require("lib.toggle").run("track_layout")
