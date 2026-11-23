-- lib/settings.lua
--
-- Values the engine, the actions and (later) the editor share through
-- REAPER's ExtState, all in the section "eminor_autocolor".
--
-- Keys:
--   switch.track_colour     "1" or "0"   live on/off switches; saved across
--   switch.track_icon                    REAPER restarts
--   switch.track_layout
--   switch.marker_colour
--   switch.region_colour
--   switches_version        bumped whenever a switch changes, so the engine
--                           notices without re-reading every key each tick
--   rules_version           bumped whenever the rules file is saved
--   toggle_cmd.<switch>     named command ID of each toggle action, so the engine
--                           can show the right state on toolbars at startup
--   timing_log              "1" while the engine logs its timing (not saved)
--   engine_running          "1" while the engine runs (not saved)

local M = {}

M.SECTION = "eminor_autocolor"

-- Each switch and whether it starts on. Mirrors SWS's five toggles.
M.SWITCHES = {
  { key = "track_colour",  label = "Track colour",  default = true },
  { key = "track_icon",    label = "Track icon",    default = true },
  { key = "track_layout",  label = "Track layout",  default = false },
  { key = "marker_colour", label = "Marker colour", default = true },
  { key = "region_colour", label = "Region colour", default = true },
}

local PERSIST = true

local function get(key)
  return reaper.GetExtState(M.SECTION, key)
end

local function set(key, value, persist)
  reaper.SetExtState(M.SECTION, key, value, persist)
end

-- Returns a table of switch key -> true/false.
function M.read_switches()
  local switches = {}
  for _, switch in ipairs(M.SWITCHES) do
    local value = get("switch." .. switch.key)
    if value == "" then
      switches[switch.key] = switch.default
    else
      switches[switch.key] = value == "1"
    end
  end
  return switches
end

local function bump(key)
  local value = (tonumber(get(key)) or 0) + 1
  set(key, tostring(value), PERSIST)
end

function M.set_switch(key, on)
  set("switch." .. key, on and "1" or "0", PERSIST)
  bump("switches_version")
end

function M.switches_version()
  return get("switches_version")
end

function M.rules_version()
  return get("rules_version")
end

function M.bump_rules_version()
  bump("rules_version")
end

-- Script command IDs are renumbered each time REAPER starts, so the stable
-- named ID ("RS...") is what gets saved.
function M.remember_toggle_command(key, command_id)
  local named = reaper.ReverseNamedCommandLookup(command_id)
  if named then
    set("toggle_cmd." .. key, named, PERSIST)
  end
end

-- The toggle action's current numeric command ID, or nil if unknown.
function M.toggle_command(key)
  local named = get("toggle_cmd." .. key)
  if named == "" then return nil end
  local command_id = reaper.NamedCommandLookup("_" .. named)
  if command_id == 0 then return nil end
  return command_id
end

-- The timing log is a debugging aid, so it resets when REAPER restarts.
-- Turning it on or off bumps switches_version so the engine notices at once.
M.TIMING_LOG = "timing_log"

function M.timing_log_on()
  return get(M.TIMING_LOG) == "1"
end

function M.set_timing_log(on)
  set(M.TIMING_LOG, on and "1" or "", false)
  bump("switches_version")
end

function M.set_engine_running(running)
  set("engine_running", running and "1" or "", false)
end

return M
