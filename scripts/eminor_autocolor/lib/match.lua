-- lib/match.lua
--
-- Decides whether a rule's filter matches a track, marker or region.
--
-- Matching works on plain "info" tables, so it can be tested outside
-- REAPER. track_info() builds one from a real track.
--
-- Filters behave as in SWS:
--   * Name filters are a case-insensitive "contains" match, not wildcards:
--     "gtr" matches "Gtr L" and "Bass gtr DI".
--   * Special filters, written in brackets, match track properties.
--   * Only "(master)" matches the master track; every other filter skips it.

local M = {}

-- Special track filters, mapped to the test each one makes on a track info
-- table. Names are the same as in SWS so imported rules keep working.
M.TRACK_FILTERS = {
  ["(any)"]           = function(info) return true end,
  ["(unnamed)"]       = function(info) return info.name == "" end,
  ["(folder)"]        = function(info) return info.is_folder end,
  ["(children)"]      = function(info) return info.depth > 0 end,
  ["(receive)"]       = function(info) return info.receives > 0 end,
  ["(record armed)"]  = function(info) return info.rec_armed end,
  ["(vca master)"]    = function(info) return info.vca_master end,
  ["(instrument)"]    = function(info) return info.has_instrument end,
  ["(audio input)"]   = function(info) return info.rec_input >= 0 and info.rec_input & 4096 == 0 end,
  ["(audio output)"]  = function(info) return info.hw_outputs > 0 end,
  ["(MIDI input)"]    = function(info) return info.rec_input >= 0 and info.rec_input & 4096 ~= 0 end,
  ["(MIDI output)"]   = function(info) return info.midi_hw_out >= 0 end,
}
M.MASTER_FILTER = "(master)"

-- Special filters for markers and regions.
M.MARKER_FILTERS = {
  ["(any)"]     = function(info) return true end,
  ["(unnamed)"] = function(info) return info.name == "" end,
}

local function name_contains(name, filter)
  return name:lower():find(filter:lower(), 1, true) ~= nil
end

-- True when `filter` matches a track described by `info`.
function M.track_matches(filter, info)
  if info.is_master then
    return filter == M.MASTER_FILTER
  end
  if filter == M.MASTER_FILTER then
    return false
  end
  local special = M.TRACK_FILTERS[filter]
  if special then
    return special(info)
  end
  return name_contains(info.name, filter)
end

-- True when `filter` matches a marker or region described by `info`
-- (which only needs a `name`).
function M.marker_matches(filter, info)
  local special = M.MARKER_FILTERS[filter]
  if special then
    return special(info)
  end
  return name_contains(info.name, filter)
end


-- -----------------------------------------------------------------------------
-- Reading a real track. Needs REAPER.
-- -----------------------------------------------------------------------------

-- Receive and hardware-output categories for reaper.GetTrackNumSends.
local SEND_CATEGORY_RECEIVES = -1
local SEND_CATEGORY_HARDWARE_OUTPUTS = 1

local function int(value)
  return math.tointeger(value) or math.floor(value)
end

-- Builds the info table match.track_matches needs for one track.
function M.track_info(track, is_master)
  if is_master then
    return { is_master = true, name = "" }
  end
  local _, name = reaper.GetSetMediaTrackInfo_String(track, "P_NAME", "", false)
  local vca_low = reaper.GetSetTrackGroupMembership(track, "VOLUME_VCA_MASTER", 0, 0)
  local vca_high = reaper.GetSetTrackGroupMembershipHigh(track, "VOLUME_VCA_MASTER", 0, 0)
  return {
    is_master = false,
    name = name or "",
    is_folder = reaper.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH") == 1,
    depth = reaper.GetTrackDepth(track),
    receives = reaper.GetTrackNumSends(track, SEND_CATEGORY_RECEIVES),
    rec_armed = reaper.GetMediaTrackInfo_Value(track, "I_RECARM") ~= 0,
    vca_master = vca_low ~= 0 or vca_high ~= 0,
    has_instrument = reaper.TrackFX_GetInstrument(track) >= 0,
    rec_input = int(reaper.GetMediaTrackInfo_Value(track, "I_RECINPUT")),
    hw_outputs = reaper.GetTrackNumSends(track, SEND_CATEGORY_HARDWARE_OUTPUTS),
    midi_hw_out = int(reaper.GetMediaTrackInfo_Value(track, "I_MIDIHWOUT")),
  }
end

return M
