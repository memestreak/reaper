-- escape_or_zoom_out.lua
--
-- A "get me out of here" action, meant for a single keybinding (CTRL-g).
--
--   * If any object is selected -- tracks, items or envelope points --
--     clear those and stop, leaving any time selection alone.
--   * Otherwise, if a time selection or loop points are set, clear those
--     and stop.
--   * If nothing at all is selected, zoom out to show the whole project.
--
-- Repeated presses therefore peel back state one layer at a time: the
-- first press drops the object selection, the second drops time, the
-- third zooms out.

local ACTIVE_PROJECT = 0  -- 0 == active project

-- Native action command IDs (see Reaper's Action List).
local COMMAND_UNSELECT_ALL = 40769           -- Unselect all tracks/items/envelope points
local COMMAND_REMOVE_TIME_SELECTION = 40020  -- Time selection: Remove time selection and loop points
local COMMAND_ZOOM_OUT_PROJECT = 40295       -- View: Zoom out project

local EXEC_MODE_NORMAL = 0

-- GetSet_LoopTimeRange isLoop values.
local RANGE_TIME_SELECTION = false
local RANGE_LOOP_POINTS = true

-- Returns true if the requested range spans more than zero time, i.e. the
-- user has actually made a selection.
function TimeRangeIsSet(is_loop)
  local start_pos, end_pos = reaper.GetSet_LoopTimeRange(
      false,    -- isSet
      is_loop,
      0,        -- startOut. NA for get.
      0,        -- endOut. NA for get.
      false)    -- allowautoseek. NA for get.

  return start_pos ~= end_pos
end

-- Returns true if any point on the envelope is selected.
function EnvelopeHasSelectedPoint(envelope)
  for point_index = 0, reaper.CountEnvelopePoints(envelope) - 1 do
    -- returns: retval, time, value, shape, tension, selected
    local _, _, _, _, _, selected = reaper.GetEnvelopePoint(envelope, point_index)
    if selected then
      return true
    end
  end

  return false
end

-- Returns true if any track or take envelope has a selected point.
-- Points nested inside automation items are not scanned.
function AnyEnvelopePointIsSelected()
  for track_index = 0, reaper.CountTracks(ACTIVE_PROJECT) - 1 do
    local track = reaper.GetTrack(ACTIVE_PROJECT, track_index)

    for env_index = 0, reaper.CountTrackEnvelopes(track) - 1 do
      local envelope = reaper.GetTrackEnvelope(track, env_index)
      if EnvelopeHasSelectedPoint(envelope) then
        return true
      end
    end
  end

  for item_index = 0, reaper.CountMediaItems(ACTIVE_PROJECT) - 1 do
    local item = reaper.GetMediaItem(ACTIVE_PROJECT, item_index)

    for take_index = 0, reaper.CountTakes(item) - 1 do
      local take = reaper.GetTake(item, take_index)

      if take then  -- Empty takes report as nil.
        for env_index = 0, reaper.CountTakeEnvelopes(take) - 1 do
          local envelope = reaper.GetTakeEnvelope(take, env_index)
          if EnvelopeHasSelectedPoint(envelope) then
            return true
          end
        end
      end
    end
  end

  return false
end

-- Returns true if any object -- track, item or envelope point -- is
-- selected. These are exactly what COMMAND_UNSELECT_ALL clears.
function AnyObjectIsSelected()
  return reaper.CountSelectedTracks(ACTIVE_PROJECT) > 0
      or reaper.CountSelectedMediaItems(ACTIVE_PROJECT) > 0
      or AnyEnvelopePointIsSelected()
end

-- Returns true if a time selection or loop points are set. These are
-- exactly what COMMAND_REMOVE_TIME_SELECTION clears.
function AnyTimeRangeIsSet()
  return TimeRangeIsSet(RANGE_TIME_SELECTION)
      or TimeRangeIsSet(RANGE_LOOP_POINTS)
end

if AnyObjectIsSelected() then
  reaper.Main_OnCommand(COMMAND_UNSELECT_ALL, EXEC_MODE_NORMAL)
elseif AnyTimeRangeIsSet() then
  reaper.Main_OnCommand(COMMAND_REMOVE_TIME_SELECTION, EXEC_MODE_NORMAL)
else
  reaper.Main_OnCommand(COMMAND_ZOOM_OUT_PROJECT, EXEC_MODE_NORMAL)
end

reaper.UpdateArrange()
