-- lib/helpers.lua
--
-- The `bridge` table that request scripts can call. It covers the jobs
-- that take many API calls to get right (finding a track, writing MIDI,
-- changing the time signature), so most requests stay a few lines long.
-- Scripts can still call reaper.* directly for anything else.
--
-- Conventions: bars and tracks count from 1, as REAPER shows them. Note
-- times and lengths are in quarter notes. Functions raise an error with a
-- plain message when given something they cannot use.

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

  local function check_note(note, i)
    local function need(field, low, high)
      local value = note[field]
      if type(value) ~= "number" or value < low or (high and value > high) then
        error(string.format("note %d: %s is %s", i, field, tostring(value)), 0)
      end
    end
    need("pitch", 0, 127)
    need("start", 0)
    need("length", 0)
    if note.length == 0 then error(string.format("note %d: length is 0", i), 0) end
  end

  -- Creates a MIDI item on `track_ref` (see find_track) and fills it.
  --
  -- spec = {
  --   bar = 1,            -- bar the item starts on (default 1)
  --   bars = 4,           -- item length in bars (default: just fits the notes)
  --   name = "Chords",    -- item name (optional)
  --   notes = {           -- times in quarter notes from the item's start
  --     { pitch = 61, start = 0, length = 5, velocity = 90, channel = 1 },
  --   },
  -- }
  -- velocity defaults to 96 and channel to 1 (channels are 1-16).
  function bridge.insert_midi(track_ref, spec)
    local track = bridge.find_track(track_ref)
    local notes = spec.notes or {}
    for i, note in ipairs(notes) do check_note(note, i) end

    local bar = spec.bar or 1
    local start_seconds, start_qn = bar_start(bar)
    local end_qn
    if spec.bars then
      local _, qn = bar_start(bar + spec.bars)
      end_qn = qn
    else
      end_qn = start_qn
      for _, note in ipairs(notes) do
        end_qn = math.max(end_qn, start_qn + note.start + note.length)
      end
    end
    if end_qn <= start_qn then error("the item would be empty: give bars or notes", 0) end
    local end_seconds = r.TimeMap2_QNToTime(0, end_qn)

    local item = r.CreateNewMIDIItemInProj(track, start_seconds, end_seconds, false)
    local take = r.GetActiveTake(item)
    if spec.name then
      r.GetSetMediaItemTakeInfo_String(take, "P_NAME", spec.name, true)
    end

    for _, note in ipairs(notes) do
      local note_start = start_qn + note.start
      local start_ppq = r.MIDI_GetPPQPosFromProjQN(take, note_start)
      local end_ppq = r.MIDI_GetPPQPosFromProjQN(take, note_start + note.length)
      local channel = (note.channel or 1) - 1
      local velocity = math.floor(note.velocity or 96)
      r.MIDI_InsertNote(take, false, false, start_ppq, end_ppq,
                        channel, math.floor(note.pitch), velocity, true)
    end
    r.MIDI_Sort(take)
    r.UpdateItemInProject(item)

    return {
      track = track_name(track),
      bar = bar,
      start_seconds = start_seconds,
      end_seconds = end_seconds,
      note_count = #notes,
    }
  end

  -- Reads every MIDI item on a track. Note times are in quarter notes from
  -- each item's start, the same shape insert_midi takes.
  function bridge.read_midi(track_ref)
    local track = bridge.find_track(track_ref)
    local items = {}
    for i = 0, r.CountTrackMediaItems(track) - 1 do
      local item = r.GetTrackMediaItem(track, i)
      local take = r.GetActiveTake(item)
      if take and r.TakeIsMIDI(take) then
        local start_seconds = r.GetMediaItemInfo_Value(item, "D_POSITION")
        local length_seconds = r.GetMediaItemInfo_Value(item, "D_LENGTH")
        local start_qn = r.TimeMap2_timeToQN(0, start_seconds)
        local _, take_name = r.GetSetMediaItemTakeInfo_String(take, "P_NAME", "", false)
        local notes = {}
        local _, note_count = r.MIDI_CountEvts(take)
        for n = 0, note_count - 1 do
          local _, _, muted, start_ppq, end_ppq, channel, pitch, velocity =
            r.MIDI_GetNote(take, n)
          local note_start = r.MIDI_GetProjQNFromPPQPos(take, start_ppq)
          local note_end = r.MIDI_GetProjQNFromPPQPos(take, end_ppq)
          notes[#notes + 1] = {
            pitch = pitch,
            start = note_start - start_qn,
            length = note_end - note_start,
            velocity = velocity,
            channel = channel + 1,
            muted = muted or nil,
          }
        end
        items[#items + 1] = {
          name = take_name,
          start_seconds = start_seconds,
          end_seconds = start_seconds + length_seconds,
          start_qn = start_qn,
          notes = notes,
        }
      end
    end
    return items
  end

  return bridge
end

return M
