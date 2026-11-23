local fake_reaper = require("fake_reaper")
local sws_switches = require("lib.sws_switches")

local T = {}

local function with_sws(states)
  local fake = fake_reaper.install({})
  fake.sws = states
  return fake
end

function T.missing_sws_reads_nothing()
  local fake = fake_reaper.install({})
  assert(not sws_switches.installed())
  assert(next(sws_switches.read()) == nil)
  assert(sws_switches.set("track_colour", false) == false)
  assert(#fake.commands_run == 0)
end

function T.reads_and_sets_switches()
  local fake = with_sws({
    ["_SWSAUTOCOLOR_ENABLE"] = 1, ["_S&MAUTOICON_ENABLE"] = 0, ["_S&MAUTOLAYOUT_ENABLE"] = 0,
    ["_S&MAUTOCOLOR_MKR_ENABLE"] = 1, ["_S&MAUTOCOLOR_RGN_ENABLE"] = 1,
  })
  assert(sws_switches.installed())
  local states = sws_switches.read()
  assert(states.track_colour and not states.track_icon and states.region_colour)

  -- Only runs the action when the state must change.
  assert(sws_switches.set("track_icon", false))
  assert(#fake.commands_run == 0)
  assert(sws_switches.set("track_colour", false))
  assert(fake.commands_run[1] == "_SWSAUTOCOLOR_ENABLE")
  assert(sws_switches.read().track_colour == false)
end

return T
