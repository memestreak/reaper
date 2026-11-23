-- lib/apply.lua
--
-- Entry points for applying the rules to the current project. The work is
-- done in apply_tracks.lua (track colour, icon, layouts) and
-- apply_markers.lua (marker and region colour); see those for how changes
-- made by hand are kept.

local apply_tracks = require("lib.apply_tracks")
local apply_markers = require("lib.apply_markers")

local M = {}

local ACTIVE_PROJECT = 0
local UNDO_STATE_TRACKCFG = 1   -- track settings, including colour, icon and layout
local UNDO_STATE_MISCCFG = 8    -- markers and regions

-- Every switch on: what Force uses, since it ignores the switches (as SWS's does).
M.ALL_ON = {
  track_colour = true, track_icon = true, track_layout = true,
  marker_colour = true, region_colour = true,
}

local function any_on(switches)
  for _, on in pairs(switches) do
    if on then return true end
  end
  return false
end

-- One pass, as the engine runs it: no undo point.
--   rules     clean rule list (rules.parse)
--   switches  settings.read_switches() result
--   force     true to overwrite hand-made changes and respread families
-- Returns the number of changes made.
function M.run_pass(rules, switches, force)
  if not any_on(switches) then
    return 0
  end
  reaper.PreventUIRefresh(1)
  local track_changes = apply_tracks.run(rules, switches, force)
  local marker_changes = apply_markers.run(rules, switches, force)
  reaper.PreventUIRefresh(-1)
  if track_changes > 0 then
    reaper.TrackList_AdjustWindows(false)
    reaper.UpdateArrange()
  end
  if marker_changes > 0 then
    reaper.UpdateTimeline()
  end
  return track_changes + marker_changes
end

-- Force: reapplies every rule, overwriting hand-made changes, with one
-- undo point. Runs whatever the on/off switches say.
function M.force(rules)
  reaper.Undo_BeginBlock2(ACTIVE_PROJECT)
  local changed = M.run_pass(rules, M.ALL_ON, true)
  reaper.Undo_EndBlock2(ACTIVE_PROJECT, "Apply auto color/icon/layout",
      UNDO_STATE_TRACKCFG | UNDO_STATE_MISCCFG)
  return changed
end

return M
