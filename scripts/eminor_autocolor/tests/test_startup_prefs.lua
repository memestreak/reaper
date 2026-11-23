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
  local _, count = twice:gsub("eminor Auto Color", "")
  assert(count == 1)
  assert(twice:find("RSnew", 1, true) and not twice:find("RSold", 1, true))
end

function T.handles_a_missing_final_newline()
  local added = startup.add_line("x = 1", "RSabc")
  assert(added:sub(1, 6) == "x = 1\n")
  assert(startup.remove_line(added) == "x = 1\n")
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
