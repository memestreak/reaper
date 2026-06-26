-- toggle_tuner.lua
--
-- Find the first effect matching "ReaTune" and toggle its state.

TUNER_FX_NAME = "ReaTune"
MESSAGE_BOX_OK = 0

-- TrackFX_Show showFlag values:
--   2 = hide floating window
--   3 = show floating window
SHOW_FLAG_HIDE_FLOATING = 2
SHOW_FLAG_SHOW_FLOATING = 3

-- Get the track and effect index for the specific effect name.
-- returns: boolean retval, MediaTrack media_track, integer fx_index
function FindFirstFxInstance(fx_name)
  local ACTIVE_PROJECT = 0  -- 0 == active project

  for track_index = 0, reaper.CountTracks(ACTIVE_PROJECT) do
    local track = reaper.GetTrack(ACTIVE_PROJECT, track_index)

    for fx_index = 0, reaper.TrackFX_GetCount(track) - 1 do
      local _, cur_fx_name = reaper.TrackFX_GetFXName(track, fx_index)
      if cur_fx_name:find(fx_name) then -- Match the FX name (substring match)
        return true, track, fx_index
      end
    end
  end

  return false, nil, 0  -- Not found
end

local retval, media_track, fx_index = FindFirstFxInstance(TUNER_FX_NAME)

if retval then
  -- TrackFX_GetEnabled returns true when the FX is enabled (not bypassed).
  local is_enabled = reaper.TrackFX_GetEnabled(media_track, fx_index)
  local enable = not is_enabled
  reaper.TrackFX_SetEnabled(media_track, fx_index, enable)

  -- Pop out the floating window when enabling, hide it when bypassing.
  local show_flag = enable and SHOW_FLAG_SHOW_FLOATING
                           or SHOW_FLAG_HIDE_FLOATING
  reaper.TrackFX_Show(media_track, fx_index, show_flag)

  reaper.UpdateArrange()
else
  reaper.ShowMessageBox("Not found: " .. TUNER_FX_NAME, "Not found", MESSAGE_BOX_OK)
end

