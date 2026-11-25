-- tests/fake_reaper.lua
--
-- A stand-in for the parts of REAPER's API the bridge uses, so its logic
-- can be tested with plain Lua. The fake project has a steady tempo and
-- at most one time signature, set at bar 1.

local M = {}

local PPQ = 960

-- Returns a fresh fake `reaper` table. `track_names` lists the tracks.
-- The table's `fake` field holds the state, for tests to inspect.
function M.new(track_names)
  local state = {
    bpm = 120, numerator = 4, denominator = 4,
    tempo_markers = {},     -- at most one, at time 0
    tracks = {},
    play_state = 0,
    clock = 0,              -- time_precise(); tests may move it
    clock_step = 0,         -- added on every time_precise() call
    undo = {},              -- labels of finished undo blocks
    undo_open = 0,
    ui_refresh = 0,
    selected_tracks = {},   -- tracks, in order
    selected_items = {},    -- items, in order
    editor_take = nil,      -- the take "open in the MIDI editor"
  }
  for i, name in ipairs(track_names or {}) do
    state.tracks[i] = { name = name, items = {}, fx = {}, number = i }
  end

  local r = { fake = state }

  local function qn_per_bar() return state.numerator * 4 / state.denominator end
  local function qn_to_seconds(qn) return qn * 60 / state.bpm end
  local function seconds_to_qn(seconds) return seconds * state.bpm / 60 end

  function r.time_precise()
    state.clock = state.clock + state.clock_step
    return state.clock
  end
  function r.GetPlayState() return state.play_state end
  -- Like REAPER's: the file at `index` in `folder`, or nil past the end.
  -- index -1 refreshes REAPER's cached listing; here every call reads
  -- the folder afresh.
  function r.EnumerateFiles(folder, index)
    if index < 0 then return nil end
    local names = {}
    local listing = io.popen('ls -1 "' .. folder .. '" 2>/dev/null')
    for name in listing:lines() do names[#names + 1] = name end
    listing:close()
    return names[index + 1]
  end
  function r.Undo_BeginBlock2() state.undo_open = state.undo_open + 1 end
  function r.Undo_EndBlock2(_, label)
    state.undo_open = state.undo_open - 1
    state.undo[#state.undo + 1] = label
  end
  function r.PreventUIRefresh(change) state.ui_refresh = state.ui_refresh + change end
  function r.UpdateArrange() end
  function r.UpdateTimeline() end
  function r.UpdateItemInProject() end

  function r.CountTracks() return #state.tracks end
  function r.GetTrack(_, index) return state.tracks[index + 1] end
  function r.GetSetMediaTrackInfo_String(track) return true, track.name end
  function r.GetMediaTrackInfo_Value(track, key)
    if key == "IP_TRACKNUMBER" then return track.number + 0.0 end
    return 0
  end
  function r.CountSelectedTracks() return #state.selected_tracks end
  function r.GetSelectedTrack(_, index) return state.selected_tracks[index + 1] end
  function r.CountSelectedMediaItems() return #state.selected_items end
  function r.GetSelectedMediaItem(_, index) return state.selected_items[index + 1] end
  function r.MIDIEditor_GetActive() return state.editor_take and "editor" or nil end
  function r.MIDIEditor_GetTake() return state.editor_take end
  function r.GetMediaItemTake_Item(take) return take.item end
  function r.GetMediaItem_Track(item) return item.track end
  function r.TrackFX_GetCount(track) return #track.fx end
  function r.TrackFX_GetFXName(track, slot) return true, track.fx[slot + 1] end
  function r.TrackFX_GetInstrument(track) return #track.fx > 0 and 0 or -1 end
  function r.CountTrackMediaItems(track) return #track.items end
  function r.GetTrackMediaItem(track, index) return track.items[index + 1] end

  function r.GetCursorPosition() return 0 end
  function r.GetProjectLength() return 0 end
  function r.CountProjectMarkers() return 0, 0, 0 end

  function r.TimeMap_GetTimeSigAtTime()
    return state.numerator, state.denominator, state.bpm
  end
  function r.TimeMap_GetMeasureInfo(_, measure)
    local qn = measure * qn_per_bar()
    return qn_to_seconds(qn), qn, qn + qn_per_bar(),
           state.numerator, state.denominator, state.bpm
  end
  function r.TimeMap2_QNToTime(_, qn) return qn_to_seconds(qn) end
  function r.TimeMap2_timeToQN(_, seconds) return seconds_to_qn(seconds) end
  -- Beats into the measure, measure (from 0), and more REAPER returns.
  function r.TimeMap2_timeToBeats(_, seconds)
    local qn = seconds_to_qn(seconds)
    local measure = math.floor(qn / qn_per_bar() + 1e-9)
    local beats = (qn - measure * qn_per_bar()) * state.denominator / 4
    return beats, measure, state.numerator, qn, state.denominator
  end

  function r.CountTempoTimeSigMarkers() return #state.tempo_markers end
  function r.GetTempoTimeSigMarker(_, index)
    local marker = state.tempo_markers[index + 1]
    return true, marker.seconds, 0, 0, marker.bpm,
           marker.numerator, marker.denominator, false
  end
  function r.SetTempoTimeSigMarker(_, index, seconds, _, _, bpm, numerator, denominator)
    assert(seconds == 0, "the fake only supports a time signature at bar 1")
    local marker = { seconds = seconds, bpm = bpm,
                     numerator = numerator, denominator = denominator }
    state.tempo_markers[index == -1 and #state.tempo_markers + 1 or index + 1] = marker
    state.bpm, state.numerator, state.denominator = bpm, numerator, denominator
    return true
  end

  function r.CreateNewMIDIItemInProj(track, start_seconds, end_seconds)
    local item = { start = start_seconds, length = end_seconds - start_seconds, track = track }
    item.take = { item = item, name = "", notes = {}, ccs = {} }
    track.items[#track.items + 1] = item
    return item
  end
  function r.GetActiveTake(item) return item.take end
  function r.TakeIsMIDI() return true end
  function r.GetMediaItemInfo_Value(item, key)
    return key == "D_POSITION" and item.start or item.length
  end
  function r.GetSetMediaItemTakeInfo_String(take, _, value, set)
    if set then take.name = value end
    return true, take.name
  end
  function r.MIDI_GetPPQPosFromProjQN(take, qn)
    return (qn - seconds_to_qn(take.item.start)) * PPQ
  end
  function r.MIDI_GetProjQNFromPPQPos(take, ppq)
    return ppq / PPQ + seconds_to_qn(take.item.start)
  end
  function r.MIDI_InsertNote(take, selected, muted, start_ppq, end_ppq, channel, pitch, velocity)
    take.notes[#take.notes + 1] = {
      selected = selected, muted = muted, start_ppq = start_ppq, end_ppq = end_ppq,
      channel = channel, pitch = pitch, velocity = velocity,
    }
    return true
  end
  function r.MIDI_SetNote(take, index, selected, muted, start_ppq, end_ppq, channel, pitch, velocity)
    local note = take.notes[index + 1]
    local function keep(new, old) if new == nil then return old end return new end
    note.selected, note.muted = keep(selected, note.selected), keep(muted, note.muted)
    note.start_ppq, note.end_ppq = keep(start_ppq, note.start_ppq), keep(end_ppq, note.end_ppq)
    note.channel, note.pitch = keep(channel, note.channel), keep(pitch, note.pitch)
    note.velocity = keep(velocity, note.velocity)
    return true
  end
  function r.MIDI_DeleteNote(take, index) table.remove(take.notes, index + 1) return true end
  function r.MIDI_InsertCC(take, selected, muted, ppq, status, channel, msg2, msg3)
    take.ccs[#take.ccs + 1] = { selected = selected, muted = muted, ppq = ppq,
      status = status, channel = channel, msg2 = msg2, msg3 = msg3 }
    return true
  end
  function r.MIDI_GetCC(take, index)
    local cc = take.ccs[index + 1]
    return true, cc.selected, cc.muted, cc.ppq, cc.status, cc.channel, cc.msg2, cc.msg3
  end
  function r.MIDI_DeleteCC(take, index) table.remove(take.ccs, index + 1) return true end
  -- Moves only the item's end here: events keep their project positions.
  function r.MIDI_SetItemExtents(item, start_qn, end_qn)
    assert(math.abs(qn_to_seconds(start_qn) - item.start) < 1e-9, "the fake only moves the end")
    item.length = qn_to_seconds(end_qn) - item.start
    return true
  end
  function r.MIDI_Sort(take)
    table.sort(take.notes, function(a, b)
      if a.start_ppq ~= b.start_ppq then return a.start_ppq < b.start_ppq end
      return a.pitch < b.pitch
    end)
    table.sort(take.ccs, function(a, b) return a.ppq < b.ppq end)
  end
  function r.MIDI_CountEvts(take) return true, #take.notes, #take.ccs, 0 end
  function r.MIDI_GetNote(take, index)
    local note = take.notes[index + 1]
    return true, note.selected, note.muted, note.start_ppq, note.end_ppq,
           note.channel, note.pitch, note.velocity
  end

  return r
end

return M
