-- lib/midi.lua
--
-- Reading and writing MIDI: notes, CCs, pitch bend and the other channel
-- messages. Adds bridge.read_midi and bridge.write_midi (and keeps the
-- older bridge.insert_midi) to the `bridge` table built in helpers.lua.
--
-- One rule for positions, used both ways: a note's or event's `start` is
-- in quarter notes from the start of the `bar` it is given with. So what
-- read_midi returns for bars 5 to 8 can be changed and written back with
-- write_midi{ mode = "replace", bar = 5, bars = 4, ... }.
--
-- Pitches are MIDI numbers (60 is middle C, "C4" in REAPER's default
-- naming) or names such as "C#4" and "Db4". Channels are 1-16.

local M = {}

M.MAX_NOTES = 5000          -- read_midi stops after this many per call
M.DEFAULT_VELOCITY = 96

local NOTE_NAMES = { "C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B" }
local LETTER_SEMITONES = { C = 0, D = 2, E = 4, F = 5, G = 7, A = 9, B = 11 }

-- Status bytes (high nibble) of the channel messages a CC lane can hold.
local STATUS = {
  poly_aftertouch = 0xA0,
  cc = 0xB0,
  program = 0xC0,
  channel_pressure = 0xD0,
  pitch_bend = 0xE0,
}
local STATUS_NAMES = {}
for name, status in pairs(STATUS) do STATUS_NAMES[status] = name end

local PITCH_BEND_CENTER = 8192

---------------------------------------------------------------------------
-- Pure helpers (no REAPER calls), exported for the tests.

-- "C#4" for 61. Sharps only; middle C (60) is C4.
function M.note_name(pitch)
  return NOTE_NAMES[pitch % 12 + 1] .. tostring(pitch // 12 - 1)
end

-- 61 for 61, "C#4" or "Db4". Errors on anything else. `where` names the
-- value in error messages.
function M.parse_pitch(value, where)
  local pitch
  if math.type(value) == "integer" or (type(value) == "number" and value % 1 == 0) then
    pitch = math.tointeger(value)
  elseif type(value) == "string" then
    local letter, accidental, octave = value:match("^%s*([A-Ga-g])([#b]?)(%-?%d+)%s*$")
    if letter then
      pitch = (tonumber(octave) + 1) * 12 + LETTER_SEMITONES[letter:upper()]
      if accidental == "#" then pitch = pitch + 1 end
      if accidental == "b" then pitch = pitch - 1 end
    end
  end
  if not pitch or pitch < 0 or pitch > 127 then
    error(string.format('%s: pitch must be 0-127 or a name like "C#4", got %s',
                        where, tostring(value)), 0)
  end
  return pitch
end

-- Rounds away float noise such as 3.9999999 from tempo-map conversions.
local function tidy(number)
  return math.floor(number * 1e6 + 0.5) / 1e6
end

---------------------------------------------------------------------------

function M.add(bridge, r)

  local function need_number(value, where, low, high, whole)
    if type(value) ~= "number" or value < low or (high and value > high)
       or (whole and value % 1 ~= 0) then
      local range = high and string.format("%s-%s", low, high) or ("at least " .. low)
      error(string.format("%s must be %s%s, got %s", where,
            whole and "a whole number " or "", range, tostring(value)), 0)
    end
    return value
  end

  -- Start of bar `bar` (from 1), in project quarter notes.
  local function bar_qn(bar)
    need_number(bar, "bar", 1, nil, true)
    local _, qn = r.TimeMap_GetMeasureInfo(0, bar - 1)
    return qn
  end

  -- The bar (from 1) a project quarter-note position falls in, and the
  -- beat within it (from 1, in the time signature's beat unit).
  local function bar_and_beat(qn)
    local seconds = r.TimeMap2_QNToTime(0, qn)
    local beats, measures = r.TimeMap2_timeToBeats(0, seconds)
    return measures + 1, tidy(beats + 1)
  end

  -- "5.1" for the first beat of bar 5, "5.2.5" halfway through beat 2.
  -- Beats are cut (not rounded, which could give beat 5 of a 4/4 bar)
  -- to hundredths, enough to read; `start` keeps the exact time.
  local function position(qn)
    local bar, beat = bar_and_beat(qn)
    return string.format("%d.%g", bar, math.floor(beat * 100 + 1e-6) / 100)
  end

  local function track_name(track)
    local _, name = r.GetSetMediaTrackInfo_String(track, "P_NAME", "", false)
    return name
  end

  local function item_extent_qn(item)
    local start = r.GetMediaItemInfo_Value(item, "D_POSITION")
    local length = r.GetMediaItemInfo_Value(item, "D_LENGTH")
    return r.TimeMap2_timeToQN(0, start), r.TimeMap2_timeToQN(0, start + length)
  end

  local function midi_take(item)
    local take = item and r.GetActiveTake(item)
    if take and r.TakeIsMIDI(take) then return take end
  end

  local function ppq_of(take, qn)
    return math.floor(r.MIDI_GetPPQPosFromProjQN(take, qn) + 0.5)
  end

  local function qn_of(take, ppq)
    return r.MIDI_GetProjQNFromPPQPos(take, ppq)
  end

  -- The take open in the MIDI editor, or an error.
  local function editor_take()
    local editor = r.MIDIEditor_GetActive()
    local take = editor and r.MIDIEditor_GetTake(editor)
    if not take then error("no MIDI editor is open", 0) end
    return take
  end

  -- Selected items with a MIDI take, as a list of items.
  local function selected_midi_items()
    local items = {}
    for i = 0, r.CountSelectedMediaItems(0) - 1 do
      local item = r.GetSelectedMediaItem(0, i)
      if midi_take(item) then items[#items + 1] = item end
    end
    return items
  end

  -- The MIDI items a spec points at: spec.track (number or name), or
  -- spec.item = "selected" or "editor".
  local function items_for(spec)
    if spec.item == "editor" then
      return { r.GetMediaItemTake_Item(editor_take()) }
    elseif spec.item == "selected" then
      local items = selected_midi_items()
      if #items == 0 then error("no MIDI items are selected", 0) end
      return items
    elseif spec.item ~= nil then
      error('item must be "selected" or "editor", got ' .. tostring(spec.item), 0)
    end
    if spec.track == nil then error('give track, or item = "selected" or "editor"', 0) end
    local track = bridge.find_track(spec.track)
    local items = {}
    for i = 0, r.CountTrackMediaItems(track) - 1 do
      local item = r.GetTrackMediaItem(track, i)
      if midi_take(item) then items[#items + 1] = item end
    end
    return items
  end

  -- A CC-lane event as a plain table. `origin_qn` is where `start` counts from.
  local function describe_event(take, origin_qn, ppq, status, channel, msg2, msg3)
    local kind = STATUS_NAMES[status]
    local event = { type = kind, start = tidy(qn_of(take, ppq) - origin_qn), channel = channel + 1 }
    if kind == "cc" then
      event.cc, event.value = msg2, msg3
    elseif kind == "pitch_bend" then
      event.value = msg3 * 128 + msg2 - PITCH_BEND_CENTER
    elseif kind == "poly_aftertouch" then
      event.pitch, event.value = msg2, msg3
    else
      event.value = msg2
    end
    return event
  end

  ---------------------------------------------------------------------------
  -- Reading

  -- Reads MIDI items. spec (all optional except where to read):
  --   track = "Piano"            -- a track number or name, or instead:
  --   item = "selected"          -- the selected MIDI items, or
  --   item = "editor"            -- the take open in the MIDI editor
  --   from_bar = 5, to_bar = 8   -- only events in these bars (inclusive)
  --   events = false             -- leave out CCs, pitch bend and the rest
  -- Also takes a bare track number or name, as earlier versions did.
  --
  -- Returns a list of items. Each has `bar` (where its notes' `start`
  -- counts from: from_bar, else the bar the item starts in), the item's
  -- place, `notes` and `events`.
  function bridge.read_midi(spec)
    if type(spec) ~= "table" then spec = { track = spec } end
    local range_start, range_end
    if spec.from_bar then range_start = bar_qn(spec.from_bar) end
    if spec.to_bar then range_end = bar_qn(spec.to_bar + 1) end
    if range_start and range_end and range_end <= range_start then
      error("to_bar must not be before from_bar", 0)
    end
    local function in_range(qn)
      return (not range_start or qn >= range_start - 1e-9)
         and (not range_end or qn < range_end - 1e-9)
    end

    local total_notes, truncated = 0, false
    local results = {}
    for _, item in ipairs(items_for(spec)) do
      local take = midi_take(item)
      local start_qn, end_qn = item_extent_qn(item)
      local overlaps = (not range_start or end_qn > range_start)
                   and (not range_end or start_qn < range_end)
      if overlaps then
        local bar = spec.from_bar or (bar_and_beat(start_qn))
        local origin = bar_qn(bar)
        local _, take_name = r.GetSetMediaItemTakeInfo_String(take, "P_NAME", "", false)
        local track = r.GetMediaItem_Track(item)

        local notes = {}
        local _, note_count, event_count = r.MIDI_CountEvts(take)
        for n = 0, note_count - 1 do
          local _, _, muted, start_ppq, end_ppq, channel, pitch, velocity = r.MIDI_GetNote(take, n)
          local note_start = qn_of(take, start_ppq)
          if in_range(note_start) then
            if total_notes >= M.MAX_NOTES then truncated = true break end
            total_notes = total_notes + 1
            notes[#notes + 1] = {
              pitch = pitch,
              name = M.note_name(pitch),
              start = tidy(note_start - origin),
              length = tidy(qn_of(take, end_ppq) - note_start),
              velocity = velocity,
              channel = channel + 1,
              at = position(note_start),
              muted = muted or nil,
            }
          end
        end

        local events = {}
        if spec.events ~= false then
          for e = 0, event_count - 1 do
            local _, _, _, ppq, status, channel, msg2, msg3 = r.MIDI_GetCC(take, e)
            if STATUS_NAMES[status] and in_range(qn_of(take, ppq)) then
              events[#events + 1] = describe_event(take, origin, ppq, status, channel, msg2, msg3)
            end
          end
        end

        results[#results + 1] = {
          track = track_name(track),
          name = take_name,
          bar = bar,
          item_start = position(start_qn),
          item_length_qn = tidy(end_qn - start_qn),
          start_qn = tidy(start_qn),
          start_seconds = r.GetMediaItemInfo_Value(item, "D_POSITION"),
          end_seconds = r.TimeMap2_QNToTime(0, end_qn),
          notes = notes,
          events = events,
        }
      end
    end
    if truncated then
      results[#results + 1] = { truncated = string.format(
        "stopped after %d notes: read fewer bars at a time", M.MAX_NOTES) }
    end
    return results
  end

  ---------------------------------------------------------------------------
  -- Writing

  local function check_notes(notes)
    local checked = {}
    for i, note in ipairs(notes or {}) do
      local where = "note " .. i
      local start = need_number(note.start, where .. ": start", 0)
      local length = need_number(note.length, where .. ": length", 0)
      if length == 0 then error(where .. ": length is 0", 0) end
      checked[i] = {
        pitch = M.parse_pitch(note.pitch, where),
        start = start,
        length = length,
        velocity = need_number(note.velocity or M.DEFAULT_VELOCITY, where .. ": velocity", 1, 127, true),
        channel = need_number(note.channel or 1, where .. ": channel", 1, 16, true),
      }
    end
    return checked
  end

  -- Each event becomes { start, status, channel, msg2, msg3, lane }.
  -- `lane` names what it controls ("cc:64", "pitch_bend"), so replace
  -- mode clears only the lanes it writes.
  local function check_events(events)
    local checked = {}
    for i, event in ipairs(events or {}) do
      local where = "event " .. i
      local kind = event.type or "cc"
      local status = STATUS[kind]
      if not status then
        error(string.format("%s: type must be cc, pitch_bend, program, channel_pressure "
              .. "or poly_aftertouch, got %s", where, tostring(kind)), 0)
      end
      local out = {
        start = need_number(event.start, where .. ": start", 0),
        status = status,
        channel = need_number(event.channel or 1, where .. ": channel", 1, 16, true),
        msg3 = 0,
        lane = kind,
      }
      if kind == "cc" then
        out.msg2 = need_number(event.cc, where .. ": cc", 0, 127, true)
        out.msg3 = need_number(event.value, where .. ": value", 0, 127, true)
        out.lane = "cc:" .. math.tointeger(out.msg2)
      elseif kind == "pitch_bend" then
        local raw = need_number(event.value, where .. ": value", -8192, 8191, true) + PITCH_BEND_CENTER
        out.msg2, out.msg3 = raw % 128, raw // 128
      elseif kind == "poly_aftertouch" then
        out.msg2 = M.parse_pitch(event.pitch, where)
        out.msg3 = need_number(event.value, where .. ": value", 0, 127, true)
      else
        out.msg2 = need_number(event.value, where .. ": value", 0, 127, true)
      end
      checked[i] = out
    end
    return checked
  end

  -- The latest quarter note (from the bar's start) any note or event reaches.
  local function content_end(notes, events)
    local last = 0
    for _, note in ipairs(notes) do last = math.max(last, note.start + note.length) end
    for _, event in ipairs(events) do last = math.max(last, event.start) end
    return last
  end

  -- Removes notes that start in [from, to) (project quarter notes) and
  -- shortens notes that start earlier but ring into it. Removes events in
  -- the range whose lane is in `lanes`. Returns the counts removed.
  local function clear_range(take, from, to, lanes)
    local removed_notes, removed_events = 0, 0
    local from_ppq, to_ppq = ppq_of(take, from), ppq_of(take, to)
    local _, note_count, event_count = r.MIDI_CountEvts(take)
    for n = note_count - 1, 0, -1 do   -- backwards, so indexes stay valid
      local _, _, _, start_ppq, end_ppq = r.MIDI_GetNote(take, n)
      if start_ppq >= from_ppq and start_ppq < to_ppq then
        r.MIDI_DeleteNote(take, n)
        removed_notes = removed_notes + 1
      elseif start_ppq < from_ppq and end_ppq > from_ppq then
        r.MIDI_SetNote(take, n, nil, nil, nil, from_ppq, nil, nil, nil, true)
      end
    end
    for e = event_count - 1, 0, -1 do
      local _, _, _, ppq, status, _, msg2 = r.MIDI_GetCC(take, e)
      local kind = STATUS_NAMES[status]
      local lane = kind == "cc" and ("cc:" .. msg2) or kind
      if lane and lanes[lane] and ppq >= from_ppq and ppq < to_ppq then
        r.MIDI_DeleteCC(take, e)
        removed_events = removed_events + 1
      end
    end
    return removed_notes, removed_events
  end

  -- MIDI items on `track` that overlap [from, to) in project quarter notes.
  local function items_overlapping(track, from, to)
    local found = {}
    for i = 0, r.CountTrackMediaItems(track) - 1 do
      local item = r.GetTrackMediaItem(track, i)
      if midi_take(item) then
        local start_qn, end_qn = item_extent_qn(item)
        if start_qn < to - 1e-9 and end_qn > from + 1e-9 then found[#found + 1] = item end
      end
    end
    return found
  end

  local function describe_items(items)
    local parts = {}
    for _, item in ipairs(items) do
      local start_qn, end_qn = item_extent_qn(item)
      local bar_from = bar_and_beat(start_qn)
      local bar_to = bar_and_beat(end_qn - 1e-6)
      parts[#parts + 1] = string.format("bars %d-%d", bar_from, bar_to)
    end
    return table.concat(parts, ", ")
  end

  -- The single item to edit for "add" and "replace".
  local function target_item(spec, from, to)
    if spec.item then
      local items = items_for(spec)
      if #items ~= 1 then
        error(string.format("%d MIDI items are selected: select exactly one", #items), 0)
      end
      return items[1]
    end
    local track = bridge.find_track(spec.track)
    local found = items_overlapping(track, from, to)
    if #found > 1 then
      error(string.format("bars %d-%d cross more than one MIDI item on %s (%s): "
            .. "use a smaller range or select one item",
            (spec.bar or 1), (spec.bar or 1) + (spec.bars or 1) - 1, track_name(track), describe_items(found)), 0)
    end
    return found[1], track
  end

  -- Writes notes and events. spec:
  --   track = "Piano"         -- a track number or name, or instead
  --   item = "selected"       -- the one selected MIDI item, or
  --   item = "editor"         -- the take open in the MIDI editor
  --   mode = "new"            -- "new": a new item at `bar`
  --                           -- "add": into the item at `bar`, keeping what is there
  --                           -- "replace": clear bars `bar` to `bar + bars - 1`, then write
  --   bar = 1                 -- where `start` counts from (default 1)
  --   bars = 4                -- the new item's length ("new"; default fits
  --                           -- the notes), or the bars to clear ("replace")
  --   name = "Chords"         -- names a new item
  --   notes = { { pitch = "C#4", start = 0, length = 1, velocity = 90, channel = 1 } }
  --   events = { { type = "cc", cc = 64, value = 127, start = 0, channel = 1 },
  --              { type = "pitch_bend", value = -8192..8191, start = 2 } }
  -- "replace" shortens notes that ring into the range, and clears events
  -- only on the lanes `events` writes to (so rewriting notes keeps the
  -- sustain pedal). Items grow to fit what is written.
  function bridge.write_midi(spec)
    local mode = spec.mode or "new"
    if mode ~= "new" and mode ~= "add" and mode ~= "replace" then
      error('mode must be "new", "add" or "replace", got ' .. tostring(mode), 0)
    end
    local bar = spec.bar or 1
    local origin = bar_qn(bar)
    if spec.bars ~= nil then need_number(spec.bars, "bars", 1, nil, true) end
    if mode == "replace" and not spec.bars then error('mode "replace" needs bars', 0) end
    if mode == "new" and spec.item then error('mode "new" makes an item: give track, not item', 0) end
    local notes = check_notes(spec.notes)
    local events = check_events(spec.events)

    local range_end = spec.bars and bar_qn(bar + spec.bars) or origin
    local needed_end = math.max(range_end, origin + content_end(notes, events))

    local item, track
    if mode ~= "new" then
      item, track = target_item(spec, origin, mode == "replace" and range_end or origin + 1e-6)
      if not item and mode == "add" then
        error(string.format('there is no MIDI item at bar %d to add to: use mode "new"', bar), 0)
      end
    end

    local removed_notes, removed_events = 0, 0
    if item then
      local start_qn, end_qn = item_extent_qn(item)
      if origin < start_qn - 1e-6 then
        error(string.format("bar %d is before the item, which starts at %s",
              bar, position(start_qn)), 0)
      end
      if needed_end > end_qn + 1e-6 then
        r.MIDI_SetItemExtents(item, start_qn, needed_end)
      end
    else
      -- "new", or "replace" where no item is there yet
      track = track or bridge.find_track(spec.track)
      if needed_end <= origin then error("the item would be empty: give bars or notes", 0) end
      item = r.CreateNewMIDIItemInProj(track, r.TimeMap2_QNToTime(0, origin),
                                       r.TimeMap2_QNToTime(0, needed_end), false)
    end
    local take = midi_take(item)
    if spec.name and mode ~= "add" then
      r.GetSetMediaItemTakeInfo_String(take, "P_NAME", spec.name, true)
    end

    if mode == "replace" then
      local lanes = {}
      for _, event in ipairs(events) do lanes[event.lane] = true end
      removed_notes, removed_events = clear_range(take, origin, range_end, lanes)
    end

    for _, note in ipairs(notes) do
      local start = origin + note.start
      r.MIDI_InsertNote(take, false, false, ppq_of(take, start), ppq_of(take, start + note.length),
                        note.channel - 1, note.pitch, math.tointeger(note.velocity), true)
    end
    for _, event in ipairs(events) do
      r.MIDI_InsertCC(take, false, false, ppq_of(take, origin + event.start),
                      event.status, event.channel - 1, math.tointeger(event.msg2),
                      math.tointeger(event.msg3))
    end
    r.MIDI_Sort(take)
    r.UpdateItemInProject(item)

    local start_qn, end_qn = item_extent_qn(item)
    return {
      track = track_name(r.GetMediaItem_Track(item)),
      mode = mode,
      bar = bar,
      start_seconds = r.GetMediaItemInfo_Value(item, "D_POSITION"),
      end_seconds = r.TimeMap2_QNToTime(0, end_qn),
      item_start = position(start_qn),
      note_count = #notes,
      event_count = #events,
      removed_notes = removed_notes,
      removed_events = removed_events,
    }
  end

  -- The older call: a new item on `track_ref`. Same as write_midi with
  -- mode "new".
  function bridge.insert_midi(track_ref, spec)
    local full = {}
    for key, value in pairs(spec or {}) do full[key] = value end
    full.track, full.mode = track_ref, "new"
    return bridge.write_midi(full)
  end
end

return M
