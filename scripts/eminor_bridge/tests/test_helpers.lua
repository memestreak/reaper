local helpers = require("lib.helpers")
local fake_reaper = require("fake_reaper")

local T = {}

local function setup(names)
  local r = fake_reaper.new(names or { "Drums", "Piano", "Piano 2" })
  return helpers.new(r), r
end

local function fails_with(pattern, fn, ...)
  local ok, err = pcall(fn, ...)
  assert(not ok and tostring(err):find(pattern), "expected error with " .. pattern .. ", got " .. tostring(err))
end

function T.find_track_by_number_and_name()
  local bridge, r = setup()
  assert(bridge.find_track(2) == r.fake.tracks[2])
  assert(bridge.find_track("piano") == r.fake.tracks[2], "exact match wins over partial")
  assert(bridge.find_track("dru") == r.fake.tracks[1])
end

function T.find_track_errors_name_the_tracks()
  local bridge = setup()
  fails_with("no track is named", bridge.find_track, "Bass")
  fails_with("Drums, Piano, Piano 2", bridge.find_track, "Bass")
  fails_with("more than one", bridge.find_track, "pian")
  fails_with("no track 9", bridge.find_track, 9)
end

function T.set_time_signature_keeps_the_tempo()
  local bridge, r = setup()
  r.fake.bpm = 96
  local result = bridge.set_time_signature(5, 4)
  assert(result.time_signature == "5/4" and result.bpm == 96)
  assert(#r.fake.tempo_markers == 1)
  -- A second change edits the same marker instead of adding one.
  bridge.set_time_signature(7, 8, { bpm = 140 })
  assert(#r.fake.tempo_markers == 1)
  assert(r.fake.numerator == 7 and r.fake.bpm == 140)
end

function T.insert_midi_places_notes_by_bar_in_five_four()
  local bridge, r = setup()
  bridge.set_time_signature(5, 4)
  local result = bridge.insert_midi("Piano", {
    bar = 2, bars = 2, name = "Chords",
    notes = {
      { pitch = 61, start = 5, length = 5, velocity = 80 },
      { pitch = 49, start = 0, length = 5 },
    },
  })
  -- 120 bpm: a 5/4 bar lasts 2.5 seconds, so bar 2 starts at 2.5.
  assert(result.start_seconds == 2.5 and result.end_seconds == 7.5)
  assert(result.track == "Piano" and result.note_count == 2)

  local take = r.fake.tracks[2].items[1].take
  assert(take.name == "Chords")
  local first, second = take.notes[1], take.notes[2]
  assert(first.pitch == 49 and first.start_ppq == 0 and first.end_ppq == 5 * 960)
  assert(first.velocity == 96 and first.channel == 0)
  assert(second.pitch == 61 and second.start_ppq == 5 * 960 and second.velocity == 80)
end

function T.insert_midi_fits_the_notes_when_no_length_is_given()
  local bridge = setup()
  local result = bridge.insert_midi(1, { notes = { { pitch = 36, start = 1, length = 2 } } })
  assert(result.start_seconds == 0 and result.end_seconds == 1.5)
end

function T.insert_midi_rejects_bad_notes_before_changing_anything()
  local bridge, r = setup()
  fails_with("note 2: pitch", bridge.insert_midi, 1, { notes = {
    { pitch = 60, start = 0, length = 1 }, { pitch = 200, start = 0, length = 1 } } })
  fails_with("length is 0", bridge.insert_midi, 1, { notes = { { pitch = 60, start = 0, length = 0 } } })
  fails_with("empty", bridge.insert_midi, 1, {})
  fails_with("bar must be", bridge.insert_midi, 1, { bar = 0, bars = 1 })
  assert(#r.fake.tracks[1].items == 0)
end

function T.read_midi_returns_what_insert_midi_wrote()
  local bridge = setup()
  bridge.set_time_signature(5, 4)
  bridge.insert_midi("Piano", { bar = 3, bars = 1, name = "C#",
    notes = { { pitch = 61, start = 2.5, length = 1.5, velocity = 70, channel = 2 } } })
  local items = bridge.read_midi("Piano")
  assert(#items == 1 and items[1].name == "C#" and items[1].start_qn == 10)
  local note = items[1].notes[1]
  assert(note.pitch == 61 and note.start == 2.5 and note.length == 1.5)
  assert(note.velocity == 70 and note.channel == 2)
end

function T.project_summary_lists_tracks()
  local bridge, r = setup()
  r.fake.tracks[2].fx = { "VSTi: Pianoteq" }
  local summary = bridge.project_summary()
  assert(summary.time_signature == "4/4" and summary.tempo_bpm == 120)
  assert(#summary.tracks == 3)
  assert(summary.tracks[2].name == "Piano" and summary.tracks[2].has_instrument)
  assert(summary.tracks[2].fx[1] == "VSTi: Pianoteq")
  assert(not summary.tracks[1].has_instrument)
end

return T
