-- lib/watch.lua
--
-- Decides when the engine should run a pass, cheaply enough that it never
-- gets in the way of REAPER's time-sensitive work.
--
-- The engine only runs on REAPER's main (UI) thread, never the audio
-- thread, so it cannot cause dropouts. What it must avoid is spending UI
-- time at the wrong moment. So:
--   * Most ticks only compare two numbers and return.
--   * A full look at the tracks, markers and regions (the "signature")
--     happens only when the project's change counter moves, or every
--     backstop interval (Settings › Engine, default BACKSTOP_SECONDS) as a
--     fallback for changes that add no undo point (such as rec-arm).
--   * A pass waits until edits have been quiet for SETTLE_SECONDS, never
--     runs while recording, and never runs in the TRANSPORT_GUARD_SECONDS
--     after Play, Record or Stop.

local M = {}

M.BACKSTOP_SECONDS = 0.5
M.SETTLE_SECONDS = 0.15
M.TRANSPORT_GUARD_SECONDS = 0.3

local PLAY_STATE_RECORDING = 4


-- -----------------------------------------------------------------------------
-- Timing rules (pure, tested outside REAPER)
-- -----------------------------------------------------------------------------

-- A Gate tracks the timing rules. Feed it events, then ask may_run(now).
function M.new_gate()
  return {
    last_change = -math.huge,     -- when a change was last seen
    last_transport = -math.huge,  -- when the play state last changed
    play_state = nil,
    recording = false,
  }
end

function M.note_change(gate, now)
  gate.last_change = now
end

function M.note_play_state(gate, now, play_state)
  if play_state ~= gate.play_state then
    if gate.play_state ~= nil then
      gate.last_transport = now
    end
    gate.play_state = play_state
  end
  gate.recording = play_state & PLAY_STATE_RECORDING ~= 0
end

function M.may_run(gate, now)
  if gate.recording then return false end
  if now - gate.last_transport < M.TRANSPORT_GUARD_SECONDS then return false end
  if now - gate.last_change < M.SETTLE_SECONDS then return false end
  return true
end


-- -----------------------------------------------------------------------------
-- Track signature. Needs REAPER.
-- -----------------------------------------------------------------------------

-- Everything a rule can depend on, for every track, joined into one string.
-- Two equal signatures mean no pass is needed.
-- The colour is included so "parent" rules follow a parent's new colour.
function M.track_signature()
  local proj = 0
  local count = reaper.CountTracks(proj)
  local parts = { tostring(count) }
  local get = reaper.GetMediaTrackInfo_Value
  for i = 0, count - 1 do
    local track = reaper.GetTrack(proj, i)
    local _, name = reaper.GetSetMediaTrackInfo_String(track, "P_NAME", "", false)
    parts[#parts + 1] = table.concat({
      reaper.GetTrackGUID(track),
      name,
      get(track, "I_FOLDERDEPTH"),
      reaper.GetTrackDepth(track),
      reaper.GetTrackNumSends(track, -1),
      get(track, "I_RECARM"),
      get(track, "I_RECINPUT"),
      reaper.GetTrackNumSends(track, 1),
      get(track, "I_MIDIHWOUT"),
      reaper.TrackFX_GetInstrument(track),
      reaper.GetSetTrackGroupMembership(track, "VOLUME_VCA_MASTER", 0, 0),
      reaper.GetSetTrackGroupMembershipHigh(track, "VOLUME_VCA_MASTER", 0, 0),
      get(track, "I_CUSTOMCOLOR"),
    }, "\1")
  end
  return table.concat(parts, "\2")
end

-- The same for markers and regions: their names, colours and order.
function M.marker_signature()
  local parts = {}
  local index = 0
  while true do
    local retval, is_region, pos, _, name, number, colour = reaper.EnumProjectMarkers3(0, index)
    if retval == 0 then break end
    parts[#parts + 1] = table.concat({
      is_region and "R" or "M", number, pos, name, colour,
    }, "\1")
    index = index + 1
  end
  return table.concat(parts, "\2")
end

-- Everything any rule can depend on.
function M.project_signature()
  return M.track_signature() .. "\3" .. M.marker_signature()
end

return M
