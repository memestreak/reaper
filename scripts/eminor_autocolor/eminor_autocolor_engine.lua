-- eminor_autocolor_engine.lua
--
-- Action: start or stop the eminor Auto Color engine. It runs in the
-- background, colouring tracks by the rules in
-- <REAPER resource folder>/Data/eminor_autocolor/rules.lua.
--
-- Running the action again stops it. Its toggle state shows on toolbars.

local here = debug.getinfo(1, "S").source:match("^@?(.*[/\\])")
package.path = here .. "?.lua;" .. package.path

require("lib.engine").run()
