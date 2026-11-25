-- eminor_toggle_unused_note_rows.lua
--
-- Toggle the active MIDI editor between hiding unused note rows and
-- showing all note rows. Any view other than "show all" (for example
-- hiding unused and unnamed rows) counts as hidden, so the first press
-- from there shows all rows. Meant for a toolbar button: the button lights
-- up while unused rows are hidden.
--
-- Works from the MIDI editor's toolbar or the main toolbar. It acts on
-- the most recently focused MIDI editor and does nothing if none is open.

-- Native MIDI editor actions (section "MIDI Editor").
SHOW_ALL_NOTE_ROWS = 40452     -- View: Show all note rows
HIDE_UNUSED_NOTE_ROWS = 40453  -- View: Hide unused note rows

MIDI_EDITOR_SECTION = 32060
TOGGLE_ON = 1
TOGGLE_OFF = 0

local editor = reaper.MIDIEditor_GetActive()

if editor then
  local showing_all =
    reaper.GetToggleCommandStateEx(MIDI_EDITOR_SECTION, SHOW_ALL_NOTE_ROWS)
      == TOGGLE_ON
  local rows_hidden = not showing_all

  if rows_hidden then
    reaper.MIDIEditor_OnCommand(editor, SHOW_ALL_NOTE_ROWS)
  else
    reaper.MIDIEditor_OnCommand(editor, HIDE_UNUSED_NOTE_ROWS)
  end

  -- Light this script's own toolbar button to match.
  local _, _, section_id, command_id = reaper.get_action_context()
  local new_state = rows_hidden and TOGGLE_OFF or TOGGLE_ON
  reaper.SetToggleCommandState(section_id, command_id, new_state)
  reaper.RefreshToolbar2(section_id, command_id)
end

-- A view change, not an edit: keep it out of the undo history.
reaper.defer(function() end)
