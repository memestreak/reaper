local fake_reaper = require("fake_reaper")
local rules = require("lib.rules")
local apply = require("lib.apply")
local apply_tracks = require("lib.apply_tracks")

local T = {}
local ICONS = fake_reaper.ICONS

local function rule_list(text)
  local list, problems = rules.parse("return { rules = {" .. text .. "} }")
  assert(#problems == 0, problems[1])
  return list
end

local function icon_pass(list)
  return apply_tracks.run(list, { track_icon = true }, false)
end

local function layout_pass(list)
  return apply_tracks.run(list, { track_layout = true }, false)
end

local GTR_ICON = rule_list([[{ id = "g", filter = "guitar", icon = "gtr.png" }]])

function T.icon_is_set_with_full_path_and_remembered()
  local fake = fake_reaper.install({ { name = "Guitar" }, { name = "Bass" } })
  assert(icon_pass(GTR_ICON) == 1)
  assert(fake.tracks[1].icon == ICONS .. "gtr.png")
  assert(fake.tracks[2].icon == "")
  assert(fake.tracks[1].ext.eminor_autocolor == "i=gtr.png")
  fake.writes = 0
  assert(icon_pass(GTR_ICON) == 0 and fake.writes == 0)
end

function T.icon_rule_does_not_need_a_colour()
  -- A rule with only an icon leaves colour to lower rules.
  local list = rule_list([[
    { id = "i", filter = "guitar", icon = "gtr.png" },
    { id = "c", filter = "guitar", colour = { mode = "fixed", rgb = "#BF0004" } }]])
  local fake = fake_reaper.install({ { name = "Guitar" } })
  apply.run_pass(list, { track_colour = true, track_icon = true }, false)
  assert(fake.tracks[1].icon == ICONS .. "gtr.png")
  assert(fake.tracks[1].colour == fake_reaper.flagged(0xBF0004))
end

function T.hand_set_icon_is_kept_until_force()
  local fake = fake_reaper.install({ { name = "Guitar", icon = "/elsewhere/mine.png" } })
  icon_pass(GTR_ICON)
  assert(fake.tracks[1].icon == "/elsewhere/mine.png")
  apply.force(GTR_ICON)
  assert(fake.tracks[1].icon == ICONS .. "gtr.png")
end

function T.icon_is_removed_when_rule_stops_matching()
  local fake = fake_reaper.install({ { name = "Guitar" } })
  icon_pass(GTR_ICON)
  fake.tracks[1].name = "Bass"
  icon_pass(GTR_ICON)
  assert(fake.tracks[1].icon == "")
  assert(fake.tracks[1].ext.eminor_autocolor == "")
end

function T.icon_changed_by_hand_survives_rule_stopping_to_match()
  local fake = fake_reaper.install({ { name = "Guitar" } })
  icon_pass(GTR_ICON)
  fake.tracks[1].icon = ICONS .. "other.png"
  fake.tracks[1].name = "Bass"
  icon_pass(GTR_ICON)
  assert(fake.tracks[1].icon == ICONS .. "other.png")
end

function T.icon_name_compare_ignores_case()
  local fake = fake_reaper.install({ { name = "Guitar", icon = ICONS .. "GTR.PNG" } })
  icon_pass(GTR_ICON)
  assert(fake.tracks[1].icon == ICONS .. "GTR.PNG")  -- already right; not rewritten
end

function T.tcp_and_mcp_layouts_come_from_separate_rules()
  local list = rule_list([[
    { id = "a", filter = "vox", tcp_layout = "Wide" },
    { id = "b", filter = "vox", tcp_layout = "Narrow", mcp_layout = "Strip" }]])
  local fake = fake_reaper.install({ { name = "Vox" } })
  layout_pass(list)
  assert(fake.tracks[1].tcp_layout == "Wide")
  assert(fake.tracks[1].mcp_layout == "Strip")
end

function T.layout_is_cleared_when_rule_stops_matching_unless_changed()
  local list = rule_list([[{ id = "a", filter = "vox", tcp_layout = "Wide", mcp_layout = "Strip" }]])
  local fake = fake_reaper.install({ { name = "Vox" } })
  layout_pass(list)
  fake.tracks[1].mcp_layout = "Mine"  -- changed by hand
  fake.tracks[1].name = "Bass"
  layout_pass(list)
  assert(fake.tracks[1].tcp_layout == "")
  assert(fake.tracks[1].mcp_layout == "Mine")
end

function T.hide_hides_and_unhides_only_what_it_hid()
  local list = rule_list([[{ id = "h", filter = "ref", tcp_layout = "(hide)", mcp_layout = "(hide)" }]])
  local fake = fake_reaper.install({ { name = "Ref mix" }, { name = "Ref 2", show_tcp = 0 } })
  layout_pass(list)
  assert(fake.tracks[1].show_tcp == 0 and fake.tracks[1].show_mcp == 0)
  assert(fake.tracks[1].tcp_layout == "")  -- "(hide)" is not a layout name
  -- Track 2 was already hidden in the TCP by hand: not ours to unhide later.
  fake.tracks[1].name, fake.tracks[2].name = "Mix", "Two"
  layout_pass(list)
  assert(fake.tracks[1].show_tcp == 1 and fake.tracks[1].show_mcp == 1)
  assert(fake.tracks[2].show_tcp == 0)
  assert(fake.tracks[2].show_mcp == 1)
end

function T.track_unhidden_by_hand_stays_visible()
  local list = rule_list([[{ id = "h", filter = "ref", tcp_layout = "(hide)" }]])
  local fake = fake_reaper.install({ { name = "Ref" } })
  layout_pass(list)
  fake.tracks[1].show_tcp = 1  -- you show it again
  layout_pass(list)
  assert(fake.tracks[1].show_tcp == 1)
end

function T.master_is_never_hidden()
  local list = rule_list([[{ id = "h", filter = "(master)", tcp_layout = "(hide)" }]])
  local fake = fake_reaper.install({})
  layout_pass(list)
  assert(fake.master.show_tcp == 1)
end

function T.layout_switch_off_by_default_leaves_layouts()
  local list = rule_list([[{ id = "a", filter = "vox", tcp_layout = "Wide" }]])
  local fake = fake_reaper.install({ { name = "Vox" } })
  apply.run_pass(list, { track_colour = true, track_icon = true, track_layout = false }, false)
  assert(fake.tracks[1].tcp_layout == "")
end

function T.colour_and_icon_state_live_side_by_side()
  local list = rule_list([[{ id = "g", filter = "guitar", icon = "g;1.png", colour = { mode = "fixed", rgb = "#000001" } }]])
  local fake = fake_reaper.install({ { name = "Guitar" } })
  apply.run_pass(list, { track_colour = true, track_icon = true }, false)
  fake.tracks[1].name = "Bass"
  apply.run_pass(list, { track_colour = true, track_icon = false }, false)
  -- Colour undone; icon untouched while its switch is off, and still remembered.
  assert(fake.tracks[1].colour == 0)
  assert(fake.tracks[1].icon == ICONS .. "g;1.png")
  apply.run_pass(list, { track_colour = true, track_icon = true }, false)
  assert(fake.tracks[1].icon == "")
end

return T
