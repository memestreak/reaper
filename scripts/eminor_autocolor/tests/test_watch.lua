local watch = require("lib.watch")

local T = {}

function T.runs_after_edits_settle()
  local gate = watch.new_gate()
  watch.note_play_state(gate, 0, 0)
  watch.note_change(gate, 10)
  assert(not watch.may_run(gate, 10.05))
  assert(watch.may_run(gate, 10.2))
end

function T.waits_after_transport_changes()
  local gate = watch.new_gate()
  watch.note_play_state(gate, 0, 0)
  watch.note_play_state(gate, 20, 1)  -- Play pressed
  assert(not watch.may_run(gate, 20.1))
  assert(watch.may_run(gate, 20.4))
end

function T.never_runs_while_recording()
  local gate = watch.new_gate()
  watch.note_play_state(gate, 0, 0)
  watch.note_play_state(gate, 5, 5)  -- recording
  assert(not watch.may_run(gate, 100))
  watch.note_play_state(gate, 101, 0)  -- Stop
  assert(not watch.may_run(gate, 101.1))
  assert(watch.may_run(gate, 101.5))
end

function T.first_play_state_is_not_a_transport_change()
  local gate = watch.new_gate()
  watch.note_play_state(gate, 50, 1)  -- engine started during playback
  assert(watch.may_run(gate, 50))
end

return T
