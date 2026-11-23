-- eminor_autocolor_toggle_timing_log.lua
--
-- Action: turn the engine's timing log on or off. While on, the engine
-- prints how much UI time it used to the ReaScript console every ten
-- seconds. Off again after REAPER restarts.

local here = debug.getinfo(1, "S").source:match("^@?(.*[/\\])")
package.path = here .. "?.lua;" .. package.path

require("lib.toggle").run("timing_log")
