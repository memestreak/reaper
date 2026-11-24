-- eminor_autocolor_force.lua
--
-- Action: apply every Eminor Auto Color rule now, overwriting colours set
-- by hand, as one undo point. Works whether or not the engine is running,
-- and regardless of the on/off switches (as SWS's Force does).

local here = debug.getinfo(1, "S").source:match("^@?(.*[/\\])")
package.path = here .. "?.lua;" .. package.path

local rules = require("lib.rules")
local apply = require("lib.apply")

local text = rules.read_file(rules.file_path())
if not text then
  reaper.MB("No rules yet. Run the Eminor Auto Color engine once to create "
      .. "the rules file.", "Eminor Auto Color", 0)
  return
end

local rule_list, problems = rules.parse(text)
for _, problem in ipairs(problems) do
  reaper.ShowConsoleMsg("Eminor Auto Color: " .. problem .. "\n")
end
apply.force(rule_list)
