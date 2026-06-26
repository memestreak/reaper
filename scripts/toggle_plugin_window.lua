-- toggle_plugin_window.lua
--
-- Find the first effect matching a name and toggle its floating
-- (popped-out) window open/closed.

-- One or more Lua patterns. The first FX matching ANY pattern wins.
-- These are Lua patterns, not full regex: %d/%w/%s classes, ^ $ anchors,
-- and * + ? quantifiers work; alternation (|) and {n,m} counts do not.
-- Examples: "^ReaComp", "Comp%d", "Pro%-Q 3" (escape magic chars with %).
TARGET_FX_PATTERNS = { "scheps.omni" }

-- Match case-insensitively (recommended; plugin name casing varies).
CASE_INSENSITIVE = true

MESSAGE_BOX_OK = 0

-- TrackFX_Show showFlag values:
--   2 = hide floating window
--   3 = show floating window
SHOW_FLAG_HIDE_FLOATING = 2
SHOW_FLAG_SHOW_FLOATING = 3

-- Return true if fx_name matches any of the configured Lua patterns.
function MatchesAnyPattern(fx_name)
  local haystack = CASE_INSENSITIVE and fx_name:lower() or fx_name
  for _, pattern in ipairs(TARGET_FX_PATTERNS) do
    local needle = CASE_INSENSITIVE and pattern:lower() or pattern
    if haystack:find(needle) then  -- needle is a Lua pattern
      return true
    end
  end
  return false
end

-- Get the track and effect index for the first matching effect.
-- returns: boolean retval, MediaTrack media_track, integer fx_index
function FindFirstFxInstance()
  local ACTIVE_PROJECT = 0  -- 0 == active project

  for track_index = 0, reaper.CountTracks(ACTIVE_PROJECT) do
    local track = reaper.GetTrack(ACTIVE_PROJECT, track_index)

    for fx_index = 0, reaper.TrackFX_GetCount(track) - 1 do
      local _, cur_fx_name = reaper.TrackFX_GetFXName(track, fx_index)
      if MatchesAnyPattern(cur_fx_name) then
        return true, track, fx_index
      end
    end
  end

  return false, nil, 0  -- Not found
end

local retval, media_track, fx_index = FindFirstFxInstance()

if retval then
  -- Returns a window handle when floating, nil when not.
  local is_floating = reaper.TrackFX_GetFloatingWindow(media_track, fx_index)
  if is_floating then
    reaper.TrackFX_Show(media_track, fx_index, SHOW_FLAG_HIDE_FLOATING)
  else
    reaper.TrackFX_Show(media_track, fx_index, SHOW_FLAG_SHOW_FLOATING)
  end
  reaper.UpdateArrange()
else
  local tried = table.concat(TARGET_FX_PATTERNS, ", ")
  reaper.ShowMessageBox("Not found: " .. tried, "Not found", MESSAGE_BOX_OK)
end
