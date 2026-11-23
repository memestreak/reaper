local match = require("lib.match")

local T = {}

local function info(fields)
  local base = { is_master = false, name = "", is_folder = false, depth = 0,
    receives = 0, rec_armed = false, vca_master = false, has_instrument = false,
    rec_input = -1, hw_outputs = 0, midi_hw_out = -1 }
  for k, v in pairs(fields) do base[k] = v end
  return base
end

function T.name_is_case_insensitive_contains()
  assert(match.track_matches("gtr", info({ name = "Bass Gtr DI" })))
  assert(not match.track_matches("gtr", info({ name = "Guitar" })))
end

function T.name_filter_is_not_a_pattern()
  assert(match.track_matches("a.b", info({ name = "x a.b y" })))
  assert(not match.track_matches("a.b", info({ name = "axb" })))
  assert(match.track_matches("(", info({ name = "Vox (dbl)" })))
end

function T.only_master_filter_matches_master()
  local master = { is_master = true, name = "" }
  assert(match.track_matches("(master)", master))
  assert(not match.track_matches("(any)", master))
  assert(not match.track_matches("(master)", info({ name = "x" })))
end

function T.special_filters()
  assert(match.track_matches("(unnamed)", info({})))
  assert(match.track_matches("(folder)", info({ is_folder = true })))
  assert(match.track_matches("(children)", info({ depth = 1 })))
  assert(match.track_matches("(receive)", info({ receives = 2 })))
  assert(match.track_matches("(record armed)", info({ rec_armed = true })))
  assert(match.track_matches("(vca master)", info({ vca_master = true })))
  assert(match.track_matches("(instrument)", info({ has_instrument = true })))
  assert(match.track_matches("(audio input)", info({ rec_input = 0 })))
  assert(not match.track_matches("(audio input)", info({ rec_input = 4096 })))
  assert(match.track_matches("(MIDI input)", info({ rec_input = 4096 + 63 })))
  assert(match.track_matches("(audio output)", info({ hw_outputs = 1 })))
  assert(match.track_matches("(MIDI output)", info({ midi_hw_out = 0 })))
  assert(not match.track_matches("(MIDI output)", info({ midi_hw_out = -1 })))
end

function T.marker_filters()
  assert(match.marker_matches("(any)", { name = "x" }))
  assert(match.marker_matches("(unnamed)", { name = "" }))
  assert(match.marker_matches("verse", { name = "Verse 2" }))
end

return T
