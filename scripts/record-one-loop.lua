-- record_one_loop.lua
--
-- Starts recording and switches to playback after one loop region loop
-- has been executed.
--
-- Prerequisites:
--   * A region has been selected.
--   * Record mode is set to auto punch
--   * In Reaper settings, loop recording is set to discard non-complete takes,
--     where completion threshold is > 50%.

local DIALOG_TYPE_OK = 0
local COMMAND_TRANPORT_PLAY = 1007
local COMMAND_TRANPORT_RECORD = 1013

-- These are guesses based on chatgpt.
local EXEC_MODE_NORMAL = 0
local EXEC_MODE_KEYBOARD_SHORTCUT = -1
local EXEC_MODE_MIDI_EDITOR = 1

local PLAY_STATE_PLAYING = 1
local PLAY_STATE_PAUSED = 2
local PLAY_STATE_RECORDING = 4

local LOOP_MODE_ON = 1

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
-- Returns true if a time/loop selection exists.
-- -----------------------------------------------------------------------------
function regionSelectionExists(start_pos, end_pos)
   return start_pos ~= end_pos
end


loop_start, loop_end = getLoopRegion()

-- Verify that a time selection exists.
if not regionSelectionExists(loop_start, loop_end) then
   reaper.ShowMessageBox(
      "This action expected a region to be selected, but none was found.",
      "No loop region found",
      DIALOG_TYPE_OK)
   return
end

local play_position = reaper.GetPlayPosition()

-- Verify that the region is ahead of the play cursor.
if play_position > loop_start then
   reaper.ShowMessageBox(
      "This action expected the time selection to be ahead of the play cursor.",
      "Time selection behind cursor.",
      DIALOG_TYPE_OK)
   return
end

-- Verify loop mode is enabled.
reaper.GetSetRepeat(1)
a_bit_after_loop_start = getPosInLoopRegion(0.05)
reaper.Main_OnCommand(COMMAND_TRANPORT_RECORD, EXEC_MODE_NORMAL)
stopRecordingAfterOneLoop()


