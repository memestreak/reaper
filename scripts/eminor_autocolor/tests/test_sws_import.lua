local sws_import = require("lib.sws_import")
local rules = require("lib.rules")

local T = {}

-- Jeremy's sws-autocoloricon.ini as read on 2026-11-23.
local INI = [[
[SWS]
AutoColor 1=0 backing 41975812 "" "" ""
AutoColor 10=2 buildup 49858595 "" "" ""
AutoColor 11=2 break 40265471 "" "" ""
AutoColor 12=0 drums 37781698 "" "" ""
AutoColor 13=2 refrain 34570495 "" "" ""
AutoColor 14=0 (name) -4 "" "" ""
AutoColor 2=0 guitar 46071812 "" "" ""
AutoColor 3=0 synth 35360539 "" "" ""
AutoColor 4=0 reverb 46159122 "" "" ""
AutoColor 5=2 chorus 48925984 "" "" ""
AutoColor 6=2 verse 42649127 "" "" ""
AutoColor 7=2 bridge 41943104 "" "" ""
AutoColor 8=2 outro 44152790 "" "" ""
AutoColor 9=2 intro 35041535 "" "" ""
AutoColorCount=14
AutoColorEnable=1
AutoColorMarkerEnable=1
AutoColorRegionEnable=1
AutoIconEnable=1
AutoLayoutEnable=0
]]

function T.reads_rules_in_priority_order()
  local raw = sws_import.parse(INI)
  assert(#raw == 14)
  local order = {}
  for i, r in ipairs(raw) do order[i] = r.filter end
  assert(table.concat(order, ",") ==
    "backing,guitar,synth,reverb,chorus,verse,bridge,outro,intro,buildup,break,drums,refrain,(name)")
end

function T.converts_colours_and_targets()
  local raw = sws_import.parse(INI)
  assert(raw[1].target == "track" and raw[1].colour.rgb == "#808004")
  assert(raw[6].target == "region" and raw[6].colour.rgb == "#8AC627")
  assert(raw[11].colour.rgb == "#6666FF")
  assert(raw[14].colour.mode == "none")
end

function T.reads_switches()
  local _, switches = sws_import.parse(INI)
  assert(switches.track_colour == true and switches.track_layout == false)
  assert(switches.region_colour == true and switches.track_icon == true)
end

function T.all_rules_pass_checks_and_placeholder_is_spotted()
  local raw = sws_import.parse(INI)
  for i, r in ipairs(raw) do
    local rule, err = rules.check_rule(r)
    assert(rule, "rule " .. i .. ": " .. tostring(err))
    assert(sws_import.is_unused_placeholder(rule) == (i == 14))
  end
end

function T.quoted_filters_and_modes()
  local raw = sws_import.parse([[
[SWS]
AutoColor 1=0 "lead vox" -2 "vox.png" "" ""
AutoColor 2=0 '"odd"' -5 "" "" ""
AutoColor 3=0 x -6 "" "Wide" "(hide)"
]])
  assert(raw[1].filter == "lead vox" and raw[1].colour.mode == "gradient" and raw[1].icon == "vox.png")
  assert(raw[2].filter == '"odd"' and raw[2].colour.mode == "parent")
  assert(raw[3].colour.mode == "ignore" and raw[3].tcp_layout == "Wide" and raw[3].mcp_layout == "(hide)")
end

return T
