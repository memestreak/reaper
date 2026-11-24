local runner = require("lib.runner")
local fake_reaper = require("fake_reaper")

local T = {}

local function run(text, r)
  r = r or fake_reaper.new()
  return runner.run(runner.parse(text), r, {}), r
end

function T.parse_reads_the_header_lines()
  local request = runner.parse("--@id abc-1\n--@undo Add chords\nreturn 1")
  assert(request.id == "abc-1")
  assert(request.undo == "Add chords")
  assert(runner.parse("return 1").id == "unknown")
  assert(runner.parse("return 1").undo == nil)
end

function T.returns_the_scripts_value_and_print_output()
  local response = run("--@id a\nprint('hi', 2)\nreturn { n = 1 + 1 }")
  assert(response.ok and response.id == "a")
  assert(response.result.n == 2)
  assert(response.output == "hi\t2")
end

function T.undo_block_only_when_asked()
  local _, r = run("return 1")
  assert(#r.fake.undo == 0)
  _, r = run("--@undo Add chords\nreturn 1")
  assert(r.fake.undo[1] == "Add chords" and r.fake.undo_open == 0)
end

function T.an_error_is_reported_and_the_undo_block_is_closed()
  local response, r = run("--@undo Try\nerror('boom')")
  assert(not response.ok and response.error:find("boom"))
  assert(response.error:find("request:2"), "the line number should be the file's")
  assert(r.fake.undo[1] == "Try" and r.fake.undo_open == 0)
  assert(r.fake.ui_refresh == 0)
end

function T.a_syntax_error_is_reported()
  local response = run("return (")
  assert(not response.ok and response.error:find("Syntax error"))
end

function T.nothing_runs_while_recording()
  local r = fake_reaper.new()
  r.fake.play_state = 5
  local response = run("--@undo X\nran = true\nreturn 1", r)
  assert(not response.ok and response.error:find("recording"))
  assert(#r.fake.undo == 0)
end

function T.script_globals_do_not_leak()
  run("leaked = 1")
  assert(leaked == nil)
  local response = run("return leaked == nil")
  assert(response.result == true)
end

function T.the_script_sees_reaper_and_bridge()
  local r = fake_reaper.new({ "Piano" })
  local response = runner.run(runner.parse("return reaper.CountTracks(0) + bridge.two"), r, { two = 2 })
  assert(response.result == 3)
end

function T.a_runaway_script_is_stopped()
  local r = fake_reaper.new()
  r.fake.clock_step = 2   -- every look at the clock moves it 2 seconds
  local response = run("--@undo Loop\nwhile true do end", r)
  assert(not response.ok and response.error:find("stopped after"))
  assert(r.fake.undo_open == 0)
end

return T
