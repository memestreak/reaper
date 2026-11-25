-- lib/helpers.lua
--
-- The `bridge` table that request scripts can call. It covers the jobs
-- that take many API calls to get right (finding a track, changing the
-- time signature, and reading and writing MIDI, in lib/midi.lua), so most
-- requests stay a few lines long.
-- Scripts can still call reaper.* directly for anything else.
--
-- Conventions: bars and tracks count from 1, as REAPER shows them. Note
-- times and lengths are in quarter notes. Functions raise an error with a
-- plain message when given something they cannot use.

local midi = require("lib.midi")

local M = {}

local MATCH_SECONDS = 1e-6   -- two positions closer than this are the same

function M.new(r)
  local bridge = {}

  local function track_name(track)
    local _, name = r.GetSetMediaTrackInfo_String(track, "P_NAME", "", false)
    return name
  end

  -- Start of bar `bar` (from 1): seconds and quarter notes.
  local function bar_start(bar)
    if math.type(bar) ~= "integer" or bar < 1 then
      error("bar must be a whole number from 1, got " .. tostring(bar), 0)
    end
    local seconds, qn = r.TimeMap_GetMeasureInfo(0, bar - 1)
    return seconds, qn
  end

  -- Finds a track by number (from 1) or by name. A name matches exactly
  -- first (ignoring case), then as part of a name if only one track fits.
  function bridge.find_track(ref)
    local count = r.CountTracks(0)
    if type(ref) == "number" then
      local track = r.GetTrack(0, ref - 1)
      if not track then
        error(string.format("there is no track %s (the project has %d)", ref, count), 0)
      end
      return track
    end

    local wanted = tostring(ref):lower()
    local partial, names = {}, {}
    for i = 0, count - 1 do
      local track = r.GetTrack(0, i)
      local name = track_name(track)
      names[#names + 1] = name
      if name:lower() == wanted then return track end
      if name:lower():find(wanted, 1, true) then partial[#partial + 1] = track end
    end
    if #partial == 1 then return partial[1] end
    local problem = #partial == 0 and "no track is named" or "more than one track matches"
    error(string.format('%s "%s". Tracks: %s', problem, ref, table.concat(names, ", ")), 0)
  end

  local function track_number(track)
    return math.tointeger(r.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER"))
  end

  -- What the user has selected, and what the MIDI editor shows, so
  -- "the selected item" and "what I have open" can be found.
  local function selection_summary()
    local selected = { tracks = {}, items = {}, midi_editor = nil }
    for i = 0, r.CountSelectedTracks(0) - 1 do
      local track = r.GetSelectedTrack(0, i)
      selected.tracks[#selected.tracks + 1] = { number = track_number(track), name = track_name(track) }
    end
    local function describe(item)
      local take = r.GetActiveTake(item)
      local track = r.GetMediaItem_Track(item)
      local start = r.GetMediaItemInfo_Value(item, "D_POSITION")
      local beats, measures = r.TimeMap2_timeToBeats(0, start)
      local name = ""
      if take then _, name = r.GetSetMediaItemTakeInfo_String(take, "P_NAME", "", false) end
      return {
        track = track_name(track),
        track_number = track_number(track),
        name = name,
        midi = take ~= nil and r.TakeIsMIDI(take),
        start = string.format("%d.%g", measures + 1, math.floor((beats + 1) * 1e6 + 0.5) / 1e6),
        start_seconds = start,
        length_seconds = r.GetMediaItemInfo_Value(item, "D_LENGTH"),
      }
    end
    for i = 0, r.CountSelectedMediaItems(0) - 1 do
      selected.items[#selected.items + 1] = describe(r.GetSelectedMediaItem(0, i))
    end
    local editor = r.MIDIEditor_GetActive()
    local take = editor and r.MIDIEditor_GetTake(editor)
    if take then selected.midi_editor = describe(r.GetMediaItemTake_Item(take)) end
    return selected
  end

  -- A plain-table description of the project, for deciding what to do.
  function bridge.project_summary()
    local cursor = r.GetCursorPosition()
    local num, denom, tempo = r.TimeMap_GetTimeSigAtTime(0, cursor)
    local summary = {
      tempo_bpm = tempo,
      time_signature = string.format("%d/%d", num, denom),
      cursor_seconds = cursor,
      length_seconds = r.GetProjectLength(0),
      play_state = r.GetPlayState(),
      tracks = {},
      markers = {},
      regions = {},
    }

    for i = 0, r.CountTracks(0) - 1 do
      local track = r.GetTrack(0, i)
      local fx = {}
      for slot = 0, r.TrackFX_GetCount(track) - 1 do
        local _, fx_name = r.TrackFX_GetFXName(track, slot, "")
        fx[#fx + 1] = fx_name
      end
      summary.tracks[#summary.tracks + 1] = {
        number = i + 1,
        name = track_name(track),
        fx = fx,
        has_instrument = r.TrackFX_GetInstrument(track) >= 0,
        item_count = r.CountTrackMediaItems(track),
        record_armed = r.GetMediaTrackInfo_Value(track, "I_RECARM") == 1,
        muted = r.GetMediaTrackInfo_Value(track, "B_MUTE") == 1,
      }
    end

    summary.selected = selection_summary()

    local _, marker_count, region_count = r.CountProjectMarkers(0)
    for i = 0, marker_count + region_count - 1 do
      local _, is_region, pos, region_end, name, number = r.EnumProjectMarkers3(0, i)
      if is_region then
        summary.regions[#summary.regions + 1] =
          { number = number, name = name, start_seconds = pos, end_seconds = region_end }
      else
        summary.markers[#summary.markers + 1] =
          { number = number, name = name, seconds = pos }
      end
    end
    return summary
  end

  -- Sets the time signature from bar `options.bar` (default 1) onward.
  -- `options.bpm` also sets the tempo there; otherwise the tempo is kept.
  function bridge.set_time_signature(numerator, denominator, options)
    options = options or {}
    local seconds = bar_start(options.bar or 1)

    -- Reuse a tempo marker that is already at this position.
    local index, bpm, linear = -1, nil, false
    for i = 0, r.CountTempoTimeSigMarkers(0) - 1 do
      local _, marker_seconds, _, _, marker_bpm, _, _, marker_linear =
        r.GetTempoTimeSigMarker(0, i)
      if math.abs(marker_seconds - seconds) < MATCH_SECONDS then
        index, bpm, linear = i, marker_bpm, marker_linear
        break
      end
    end
    if not bpm then
      local _, _, tempo_here = r.TimeMap_GetTimeSigAtTime(0, seconds)
      bpm = tempo_here
    end
    bpm = options.bpm or bpm

    local ok = r.SetTempoTimeSigMarker(
      0, index, seconds, -1, -1, bpm, numerator, denominator, linear)
    if not ok then error("REAPER refused the time signature change", 0) end
    r.UpdateTimeline()
    return { bar = options.bar or 1, bpm = bpm,
             time_signature = string.format("%d/%d", numerator, denominator) }
  end

  midi.add(bridge, r)

  return bridge
end

return M
