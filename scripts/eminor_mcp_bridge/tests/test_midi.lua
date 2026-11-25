local helpers = require("lib.helpers")
local midi = require("lib.midi")
local fake_reaper = require("fake_reaper")

local T = {}

-- 4/4 at 120 bpm unless a test changes it: a bar is 4 quarter notes.
local function setup()
  local r = fake_reaper.new({ "Drums", "Piano" })
  return helpers.new(r), r
end

local function fails_with(pattern, fn, ...)
  local ok, err = pcall(fn, ...)
  assert(not ok and tostring(err):find(pattern, 1, true),
         "expected error with " .. pattern .. ", got " .. tostring(err))
end

local function chord(start, length, ...)
  local notes = {}
  for _, pitch in ipairs({ ... }) do
    notes[#notes + 1] = { pitch = pitch, start = start, length = length }
  end
  return notes
end

function T.pitch_names_both_ways()
  assert(midi.note_name(60) == "C4" and midi.note_name(61) == "C#4")
  assert(midi.note_name(0) == "C-1" and midi.note_name(127) == "G9")
  assert(midi.parse_pitch("C#4") == 61 and midi.parse_pitch("Db4") == 61)
  assert(midi.parse_pitch("c-1") == 0 and midi.parse_pitch(64) == 64)
  assert(midi.parse_pitch(64.0) == 64)
  fails_with("pitch must be", midi.parse_pitch, "H2", "note 1")
  fails_with("pitch must be", midi.parse_pitch, "G#9", "note 1")
  fails_with("pitch must be", midi.parse_pitch, 60.5, "note 1")
end

function T.write_new_takes_note_names_and_events()
  local bridge, r = setup()
  local result = bridge.write_midi({
    track = "Piano", bar = 3, bars = 2, name = "Intro",
    notes = { { pitch = "E4", start = 1, length = 1, velocity = 100, channel = 2 } },
    events = {
      { cc = 64, value = 127, start = 0 },
      { type = "pitch_bend", value = -8192, start = 2 },
      { type = "pitch_bend", value = 8191, start = 3 },
      { type = "program", value = 5, start = 0 },
    },
  })
  assert(result.start_seconds == 4 and result.end_seconds == 8, "bars 3-4")
  assert(result.note_count == 1 and result.event_count == 4 and result.item_start == "3.1")
  local take = r.fake.tracks[2].items[1].take
  assert(take.name == "Intro")
  assert(take.notes[1].pitch == 64 and take.notes[1].channel == 1 and take.notes[1].start_ppq == 960)
  local bends = {}
  for _, cc in ipairs(take.ccs) do if cc.status == 0xE0 then bends[#bends + 1] = cc end end
  assert(bends[1].msg2 == 0 and bends[1].msg3 == 0, "lowest bend")
  assert(bends[2].msg2 == 127 and bends[2].msg3 == 127, "highest bend")
end

function T.read_gives_back_what_was_written_relative_to_the_bar()
  local bridge = setup()
  bridge.write_midi({ track = "Piano", bar = 2, bars = 2,
    notes = { { pitch = 61, start = 4.5, length = 0.5, velocity = 70 } },
    events = { { cc = 1, value = 40, start = 4 }, { type = "pitch_bend", value = 100, start = 5 } } })
  local items = bridge.read_midi({ track = "Piano" })
  assert(#items == 1 and items[1].bar == 2 and items[1].item_start == "2.1")
  local note = items[1].notes[1]
  assert(note.pitch == 61 and note.name == "C#4" and note.start == 4.5 and note.length == 0.5)
  assert(note.velocity == 70 and note.channel == 1 and note.at == "3.1.5")
  local cc, bend = items[1].events[1], items[1].events[2]
  assert(cc.type == "cc" and cc.cc == 1 and cc.value == 40 and cc.start == 4)
  assert(bend.type == "pitch_bend" and bend.value == 100)

  -- From bar 3, starts count from bar 3, and earlier events are left out.
  items = bridge.read_midi({ track = "Piano", from_bar = 3, to_bar = 3, events = false })
  assert(items[1].bar == 3 and items[1].notes[1].start == 0.5)
  assert(#items[1].events == 0)
  assert(#bridge.read_midi({ track = "Piano", from_bar = 5 }) == 0, "no item there")
end

function T.read_still_takes_a_bare_track()
  local bridge = setup()
  bridge.insert_midi("Piano", { bar = 1, notes = chord(0, 4, 60, 64, 67) })
  local items = bridge.read_midi("Piano")
  assert(#items == 1 and #items[1].notes == 3)
end

function T.replace_clears_only_the_range_and_shortens_ringing_notes()
  local bridge, r = setup()
  local notes = {}
  for bar = 0, 3 do
    for _, note in ipairs(chord(bar * 4, 4, 48, 60)) do notes[#notes + 1] = note end
  end
  notes[#notes + 1] = { pitch = 36, start = 0, length = 8 }   -- rings through bar 2
  bridge.write_midi({ track = "Piano", bar = 1, bars = 4, notes = notes,
    events = { { cc = 64, value = 127, start = 4 }, { cc = 1, value = 10, start = 4 } } })

  local result = bridge.write_midi({ track = "Piano", mode = "replace", bar = 2, bars = 2,
    notes = { { pitch = "G4", start = 0, length = 8 } },
    events = { { cc = 1, value = 90, start = 0 } } })
  assert(result.removed_notes == 4 and result.removed_events == 1, "two chords and one cc 1")
  assert(#r.fake.tracks[2].items == 1, "edited in place")

  local item = bridge.read_midi("Piano")[1]
  local by_bar = {}
  for _, note in ipairs(item.notes) do
    local bar = math.floor(note.start / 4) + 1
    by_bar[bar] = (by_bar[bar] or 0) + 1
    if note.pitch == 36 then assert(note.length == 4, "shortened to the range start") end
  end
  assert(by_bar[1] == 3 and by_bar[2] == 1 and by_bar[3] == nil and by_bar[4] == 2)
  local sustain_kept, mod_values = false, {}
  for _, event in ipairs(item.events) do
    if event.cc == 64 then sustain_kept = true end
    if event.cc == 1 then mod_values[#mod_values + 1] = event.value end
  end
  assert(sustain_kept, "replace leaves lanes it does not write")
  assert(#mod_values == 1 and mod_values[1] == 90)
end

function T.replace_with_nothing_there_makes_an_item()
  local bridge, r = setup()
  local result = bridge.write_midi({ track = 1, mode = "replace", bar = 5, bars = 1,
    notes = { { pitch = 36, start = 0, length = 1 } } })
  assert(result.start_seconds == 8 and result.end_seconds == 10)
  assert(#r.fake.tracks[1].items == 1)
end

function T.add_keeps_notes_and_grows_the_item()
  local bridge, r = setup()
  bridge.write_midi({ track = "Piano", bar = 1, bars = 1, notes = chord(0, 1, 60) })
  local result = bridge.write_midi({ track = "Piano", mode = "add", bar = 1,
    notes = { { pitch = 62, start = 6, length = 2 } } })
  assert(result.removed_notes == 0 and result.end_seconds == 4, "grown to bar 2's end")
  local item = r.fake.tracks[2].items[1]
  assert(#item.take.notes == 2 and #r.fake.tracks[2].items == 1)
  fails_with('no MIDI item at bar 5', bridge.write_midi,
    { track = "Piano", mode = "add", bar = 5, notes = chord(0, 1, 60) })
end

function T.selected_and_editor_items()
  local bridge, r = setup()
  bridge.write_midi({ track = "Drums", bar = 1, bars = 1, name = "Beat", notes = chord(0, 1, 36) })
  bridge.write_midi({ track = "Piano", bar = 1, bars = 1, name = "Keys", notes = chord(0, 1, 60) })
  local drums, piano = r.fake.tracks[1].items[1], r.fake.tracks[2].items[1]

  fails_with("no MIDI items are selected", bridge.read_midi, { item = "selected" })
  fails_with("no MIDI editor is open", bridge.read_midi, { item = "editor" })

  r.fake.selected_items = { drums, piano }
  local items = bridge.read_midi({ item = "selected" })
  assert(#items == 2 and items[1].name == "Beat" and items[2].track == "Piano")
  fails_with("select exactly one", bridge.write_midi,
    { item = "selected", mode = "add", notes = chord(0, 1, 38) })

  r.fake.editor_take = piano.take
  bridge.write_midi({ item = "editor", mode = "add", notes = chord(2, 1, 64) })
  assert(#piano.take.notes == 2 and #drums.take.notes == 1)
  fails_with('mode "new" makes an item', bridge.write_midi, { item = "editor", notes = chord(0, 1, 60) })

  local summary = bridge.project_summary()
  assert(#summary.selected.items == 2 and summary.selected.items[1].name == "Beat")
  assert(summary.selected.items[1].start == "1.1" and summary.selected.items[1].midi)
  assert(summary.selected.midi_editor.name == "Keys" and summary.selected.midi_editor.track_number == 2)
end

function T.replace_across_two_items_says_which()
  local bridge = setup()
  bridge.write_midi({ track = "Piano", bar = 1, bars = 2, notes = chord(0, 1, 60) })
  bridge.write_midi({ track = "Piano", bar = 3, bars = 2, notes = chord(0, 1, 60) })
  fails_with("bars 1-2, bars 3-4", bridge.write_midi,
    { track = "Piano", mode = "replace", bar = 2, bars = 2, notes = chord(0, 1, 60) })
end

function T.bad_input_changes_nothing()
  local bridge, r = setup()
  local function nothing_written(spec, pattern)
    fails_with(pattern, bridge.write_midi, spec)
    assert(#r.fake.tracks[2].items == 0, pattern)
  end
  nothing_written({ track = "Piano", mode = "move" }, 'mode must be')
  nothing_written({ track = "Piano", mode = "replace", notes = chord(0, 1, 60) }, 'needs bars')
  nothing_written({ track = "Piano", notes = { { pitch = 60, start = 0, length = 1, velocity = 0 } } },
                  "note 1: velocity must be")
  nothing_written({ track = "Piano", notes = { { pitch = 60, start = 0, length = 1, channel = 17 } } },
                  "note 1: channel must be")
  nothing_written({ track = "Piano", bars = 1, events = { { cc = 128, value = 1, start = 0 } } },
                  "event 1: cc must be")
  nothing_written({ track = "Piano", bars = 1, events = { { type = "aftertouch", value = 1, start = 0 } } },
                  "event 1: type must be")
  nothing_written({ track = "Piano", bars = 1, events = { { type = "pitch_bend", value = 9000, start = 0 } } },
                  "event 1: value must be")
  nothing_written({ track = "Piano" }, "the item would be empty")
  fails_with("to_bar must not be before", bridge.read_midi, { track = "Piano", from_bar = 3, to_bar = 2 })
  fails_with('give track, or item', bridge.read_midi, {})
end

function T.five_four_positions()
  local bridge = setup()
  bridge.set_time_signature(5, 4)
  bridge.write_midi({ track = "Piano", bar = 2, bars = 1, notes = { { pitch = 60, start = 4.5, length = 0.5 } } })
  local note = bridge.read_midi("Piano")[1].notes[1]
  assert(note.at == "2.5.5" and note.start == 4.5)
end

return T
