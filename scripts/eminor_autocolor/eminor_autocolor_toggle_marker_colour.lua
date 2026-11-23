-- eminor_autocolor_toggle_marker_colour.lua
--
-- Action: turn automatic marker colouring on or off. Its toggle
-- state shows on toolbars. The running engine picks the change up at once.

local here = debug.getinfo(1, "S").source:match("^@?(.*[/\\])")
package.path = here .. "?.lua;" .. package.path

require("lib.toggle").run("marker_colour")
