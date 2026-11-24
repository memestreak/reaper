local startup = require("lib.startup")
local prefs = require("lib.prefs")

local T = {}

function T.adds_line_without_touching_the_rest()
  local text = "-- mine\nreaper.ShowConsoleMsg('hi')\n"
  local added = startup.add_line(text, "RSabc")
  assert(added:sub(1, #text) == text)
  assert(startup.has_line(added))
  assert(added:find('NamedCommandLookup("_RSabc")', 1, true))
  assert(startup.remove_line(added) == text)
end

function T.adding_twice_keeps_one_line_with_the_new_id()
  local once = startup.add_line("", "RSold")
  local twice = startup.add_line(once, "RSnew")
  local _, count = twice:gsub("Eminor Auto Color", "")
  assert(count == 1)
  assert(twice:find("RSnew", 1, true) and not twice:find("RSold", 1, true))
end

function T.recognises_and_replaces_the_old_lowercase_marker()
  local old = "x = 1\n-- eminor Auto Color: start the engine (added by its editor)\n"
      .. 'reaper.Main_OnCommand(reaper.NamedCommandLookup("_RSold"), 0)\n'
  assert(startup.has_line(old))
  assert(startup.remove_line(old) == "x = 1\n")
  local new = startup.add_line(old, "RSnew")
  assert(not new:find("eminor Auto Color", 1, true) and not new:find("RSold", 1, true))
  assert(new:find("Eminor Auto Color", 1, true))
end

function T.handles_a_missing_final_newline()
  local added = startup.add_line("x = 1", "RSabc")
  assert(added:sub(1, 6) == "x = 1\n")
  assert(startup.remove_line(added) == "x = 1\n")
end

function T.finds_engine_command_in_keymap()
  local kb = 'ACT 0 0 "abc" "Custom: x" 40001\n'
    .. 'SCR 4 0 RS9f8e7d6c "Custom: eminor_autocolor_force.lua" "/r/eminor_autocolor_force.lua"\n'
    .. 'SCR 4 0 RS1a2b3c4d "Custom: eminor_autocolor_engine.lua" "/r/eminor_autocolor_engine.lua"\n'
  assert(startup.engine_command_in_keymap(kb) == "RS1a2b3c4d")
  assert(startup.engine_command_in_keymap("KEY 1 2 3 0\n") == nil)
end

function T.prefs_parse_defaults_and_bounds()
  local v = prefs.parse("engine", "backstop_ms=99999;junk=1")
  assert(v.backstop_ms == 500)
  v = prefs.parse("engine", "backstop_ms=250")
  assert(v.backstop_ms == 250)
  assert(prefs.format("engine", v) == "backstop_ms=250")
  assert(prefs.parse("appearance", nil).thumb_size == 20)
end

return T
