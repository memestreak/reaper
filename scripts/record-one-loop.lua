-- record_one_loop.lua
--
-- Starts recording and switches to playback after one loop region loop
-- has been executed.
--
-- Prerequisites:
--   * A region has been selected, somewhere ahead of the play cursor. If no
--     region is selected, this script creates one ahead of the cursor.
--   * In Reaper settings, loop recording is set to discard non-complete takes,
--     where completion threshold is > 50%.
--   * Record mode is set to time selection auto-punch. This script enables it
--     if it isn't already on.


local DIALOG_TYPE_OK = 0
local COMMAND_TRANPORT_PLAY = 1007
local COMMAND_TRANPORT_RECORD = 1013

-- Record: Set record mode to time selection auto-punch
local COMMAND_RECORD_MODE_AUTO_PUNCH = 40076

local TOGGLE_STATE_ON = 1

-- These are guesses based on chatgpt.
local EXEC_MODE_NORMAL = 0
local EXEC_MODE_KEYBOARD_SHORTCUT = -1
local EXEC_MODE_MIDI_EDITOR = 1

local PLAY_STATE_PLAYING = 1
local PLAY_STATE_PAUSED = 2
local PLAY_STATE_RECORDING = 4

local LOOP_MODE_ON = 1

-- Shape of the time selection created when none exists: how far ahead of the
-- cursor it starts, and how long it runs.
local LEAD_IN_MEASURES = 1
local SELECTION_LENGTH_MEASURES = 4

local playback_reached_marker = false
local a_bit_after_loop_start  -- Global


-- -----------------------------------------------------------------------------
-- Returns the loop start and end positions.
-- -----------------------------------------------------------------------------
function getLoopRegion()
  return reaper.GetSet_LoopTimeRange(
      false,  -- isSet
      true,   -- isLoop
      0,      -- startOut. NA for get.
      0,      -- endOut. NA for get.
      false)  -- allowautoseek. NA for get.
end


-- -----------------------------------------------------------------------------
-- Returns a position a specified percentage into the loop.
-- -----------------------------------------------------------------------------
function getPosInLoopRegion(percentage)
  local loopStart, loopEnd = reaper.GetSet_LoopTimeRange(
      false,  -- isSet
      true,   -- isLoop
      0,      -- startOut. NA for get.
      0,      -- endOut. NA for get.
      false)  -- allowautoseek. NA for get.

  return loopStart + ((loopEnd - loopStart) * percentage)
end


-- -----------------------------------------------------------------------------
-- Switches from record to play transport once we've passed the specified region
-- twice.
-- -----------------------------------------------------------------------------
function stopRecordingAfterOneLoop()
  -- Exit early if we can.
  local play_state = reaper.GetPlayState()
  if play_state ~= PLAY_STATE_RECORDING and
     (play_state == PLAY_STATE_PLAYING and playback_reached_marker) then
     return
  end

  local play_position = reaper.GetPlayPosition()

  if playback_reached_marker and play_position < a_bit_after_loop_start then
     -- Switch from record to play mode, as we're not in our first loop.
     reaper.Main_OnCommand(COMMAND_TRANPORT_PLAY, EXEC_MODE_NORMAL)
    return
  elseif play_position >= a_bit_after_loop_start then
    playback_reached_marker = true
  end

  reaper.defer(stopRecordingAfterOneLoop)
end


-- -----------------------------------------------------------------------------
-- Creates a time selection SELECTION_LENGTH_MEASURES long, beginning
-- LEAD_IN_MEASURES after the measure holding the cursor. Both edges land on
-- measure boundaries. Returns the new start and end positions.
-- -----------------------------------------------------------------------------
function createLoopRegionAheadOfCursor(cursor_position)
  local _, cursor_measure = reaper.TimeMap2_timeToBeats(
      0,                 -- proj. 0 is the active project.
      cursor_position)

  -- Passing a measure makes the second argument beats within that measure, so
  -- 0 beats is the downbeat.
  local start_measure = cursor_measure + LEAD_IN_MEASURES
  local start_pos = reaper.TimeMap2_beatsToTime(0, 0, start_measure)
  local end_pos = reaper.TimeMap2_beatsToTime(
      0, 0, start_measure + SELECTION_LENGTH_MEASURES)

  reaper.GetSet_LoopTimeRange(
      true,       -- isSet
      true,       -- isLoop
      start_pos,  -- startOut
      end_pos,    -- endOut
      false)      -- allowautoseek

  return start_pos, end_pos
end


-- -----------------------------------------------------------------------------
-- Returns true if a time/loop selection exists.
-- -----------------------------------------------------------------------------
function regionSelectionExists(start_pos, end_pos)
   return start_pos ~= end_pos
end

loop_start, loop_end = getLoopRegion()
local cursor_position = reaper.GetCursorPosition()

-- Create a time selection ahead of the cursor if there isn't one already.
if not regionSelectionExists(loop_start, loop_end) then
   loop_start, loop_end = createLoopRegionAheadOfCursor(cursor_position)
end

-- Verify that the region is ahead of the play cursor.
if cursor_position > loop_start then
   reaper.ShowMessageBox(
      "This action expected the time selection to be ahead of the play cursor.",
      "Time selection behind cursor.",
      DIALOG_TYPE_OK)
   return
end

-- Enable repeat if it isn't already on. GetSetRepeat(1) sets rather than
-- toggles, so this is a no-op when repeat is already enabled.
reaper.GetSetRepeat(1)

-- Enable time selection auto-punch record mode if it isn't already on.
if reaper.GetToggleCommandState(COMMAND_RECORD_MODE_AUTO_PUNCH) ~= TOGGLE_STATE_ON
then
  reaper.Main_OnCommand(COMMAND_RECORD_MODE_AUTO_PUNCH, EXEC_MODE_NORMAL)
end

a_bit_after_loop_start = getPosInLoopRegion(0.05)
reaper.Main_OnCommand(COMMAND_TRANPORT_RECORD, EXEC_MODE_NORMAL)
stopRecordingAfterOneLoop()
