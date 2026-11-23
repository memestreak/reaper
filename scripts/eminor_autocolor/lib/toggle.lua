-- lib/toggle.lua
--
-- Shared body of the toggle actions: flips one switch (or the timing log),
-- remembers the action's command ID so the engine can show its state on
-- toolbars, and updates the toolbar button now.

local settings = require("lib.settings")

local M = {}

local MAIN_SECTION = 0

local function is_on(key)
  if key == settings.TIMING_LOG then return settings.timing_log_on() end
  return settings.read_switches()[key]
end

local function set_on(key, on)
  if key == settings.TIMING_LOG then
    settings.set_timing_log(on)
  else
    settings.set_switch(key, on)
  end
end

-- `key` is a settings.SWITCHES key, or settings.TIMING_LOG.
function M.run(key)
  local _, _, _, command_id = reaper.get_action_context()
  settings.remember_toggle_command(key, command_id)
  local on = not is_on(key)
  set_on(key, on)
  reaper.SetToggleCommandState(MAIN_SECTION, command_id, on and 1 or 0)
  reaper.RefreshToolbar2(MAIN_SECTION, command_id)
end

return M
