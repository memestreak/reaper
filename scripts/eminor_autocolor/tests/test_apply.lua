local fake_reaper = require("fake_reaper")
local rules = require("lib.rules")
local colour = require("lib.colour")
local apply = require("lib.apply")
local apply_tracks = require("lib.apply_tracks")

local T = {}
local flagged = fake_reaper.flagged

local function rule_list(text)
  local list, problems = rules.parse("return { rules = {" .. text .. "} }")
  assert(#problems == 0, problems[1])
  return list
end

-- One engine pass with only track colouring switched on.
local function colour_pass(list)
  return apply_tracks.run(list, { track_colour = true }, false)
end

local GUITAR_RED = rule_list([[{ id = "g", filter = "guitar", colour = { mode = "fixed", rgb = "#BF0004" } }]])

function T.colours_matching_tracks_only()
  local fake = fake_reaper.install({ { name = "Guitar L" }, { name = "Bass" } })
  assert(colour_pass(GUITAR_RED) == 1)
  assert(fake.tracks[1].colour == flagged(0xBF0004))
  assert(fake.tracks[2].colour == 0)
  assert(fake.tracks[1].ext.eminor_autocolor == "c=" .. flagged(0xBF0004) .. ";r=g")
end

function T.second_pass_writes_nothing()
  local fake = fake_reaper.install({ { name = "Guitar" } })
  colour_pass(GUITAR_RED)
  fake.writes = 0
  assert(colour_pass(GUITAR_RED) == 0)
  assert(fake.writes == 0)
end

function T.first_matching_rule_wins()
  local list = rule_list([[
    { id = "a", filter = "gtr", colour = { mode = "fixed", rgb = "#000001" } },
    { id = "b", filter = "gtr", colour = { mode = "fixed", rgb = "#000002" } }]])
  local fake = fake_reaper.install({ { name = "gtr" } })
  colour_pass(list)
  assert(fake.tracks[1].colour == flagged(1))
end

function T.ignore_and_disabled_rules_let_lower_rules_colour()
  local list = rule_list([[
    { id = "a", filter = "gtr", colour = { mode = "ignore" } },
    { id = "b", filter = "gtr", enabled = false, colour = { mode = "fixed", rgb = "#000002" } },
    { id = "c", filter = "gtr", colour = { mode = "fixed", rgb = "#000003" } }]])
  local fake = fake_reaper.install({ { name = "gtr" } })
  colour_pass(list)
  assert(fake.tracks[1].colour == flagged(3))
end

function T.hand_set_colour_is_kept_until_force()
  local fake = fake_reaper.install({ { name = "Guitar" } })
  colour_pass(GUITAR_RED)
  fake.tracks[1].colour = flagged(0x00FF00)  -- you recolour it by hand
  colour_pass(GUITAR_RED)
  assert(fake.tracks[1].colour == flagged(0x00FF00))
  apply.force(GUITAR_RED)
  assert(fake.tracks[1].colour == flagged(0xBF0004))
  assert(fake.undo_blocks == 1)
end

function T.track_coloured_by_hand_before_any_rule_is_kept()
  local fake = fake_reaper.install({ { name = "Guitar", colour = flagged(0x123456) } })
  colour_pass(GUITAR_RED)
  assert(fake.tracks[1].colour == flagged(0x123456))
end

function T.colour_is_cleared_when_rule_stops_matching()
  local fake = fake_reaper.install({ { name = "Guitar" } })
  colour_pass(GUITAR_RED)
  fake.tracks[1].name = "Bass"
  colour_pass(GUITAR_RED)
  assert(fake.tracks[1].colour == 0)
  assert(fake.tracks[1].ext.eminor_autocolor == "")
end

function T.hand_colour_survives_rule_stopping_to_match()
  local fake = fake_reaper.install({ { name = "Guitar" } })
  colour_pass(GUITAR_RED)
  fake.tracks[1].colour = flagged(0x00FF00)
  fake.tracks[1].name = "Bass"
  colour_pass(GUITAR_RED)
  assert(fake.tracks[1].colour == flagged(0x00FF00))
end

function T.none_clears_colour()
  local list = rule_list([[{ id = "n", filter = "(any)", colour = { mode = "none" } }]])
  local fake = fake_reaper.install({ { name = "x", colour = flagged(5) } })
  apply.force(list)
  assert(fake.tracks[1].colour == 0)
end

function T.gradient_spreads_over_matches()
  local list = rule_list([[{ id = "g", filter = "vox", colour = { mode = "gradient", from = "#000000", to = "#FFFFFF" } }]])
  local fake = fake_reaper.install({ { name = "vox 1" }, { name = "bass" }, { name = "vox 2" }, { name = "vox 3" } })
  colour_pass(list)
  assert(fake.tracks[1].colour == flagged(0x000000))
  assert(fake.tracks[3].colour == flagged(0x808080))
  assert(fake.tracks[4].colour == flagged(0xFFFFFF))
end

function T.family_slots_stay_put_when_a_match_is_added()
  local list = rule_list([[{ id = "f", filter = "verse", colour = { mode = "family", base = "#8AC627", hue = 8, light = 0.12 } }]])
  local fake = fake_reaper.install({ { name = "verse a" }, { name = "verse b" } })
  colour_pass(list)
  local a, b = fake.tracks[1].colour, fake.tracks[2].colour
  assert(a ~= b)
  assert(a == flagged(0x8AC627))

  -- A new matching track appears above the others.
  local new_specs = { { name = "verse new" }, { name = "verse a" }, { name = "verse b" } }
  local fake2 = fake_reaper.install(new_specs)
  fake2.tracks[2].colour, fake2.tracks[2].ext = a, fake.tracks[1].ext
  fake2.tracks[3].colour, fake2.tracks[3].ext = b, fake.tracks[2].ext
  colour_pass(list)
  assert(fake2.tracks[2].colour == a, "verse a changed colour")
  assert(fake2.tracks[3].colour == b, "verse b changed colour")
  assert(fake2.tracks[1].colour ~= a and fake2.tracks[1].colour ~= b)
  assert(fake2.tracks[1].colour == flagged(colour.family_colour(list[1].colour, 2)))
end

function T.force_respreads_family()
  local list = rule_list([[{ id = "f", filter = "verse", colour = { mode = "family", palette = { "#000001", "#000002", "#000003" } } }]])
  local fake = fake_reaper.install({ { name = "verse a" }, { name = "verse b" } })
  fake.tracks[1].ext.eminor_autocolor = "c=0;r=f;s=2"
  colour_pass(list)
  assert(fake.tracks[1].colour == flagged(3))
  assert(fake.tracks[2].colour == flagged(1))
  apply.force(list)
  assert(fake.tracks[1].colour == flagged(1))
  assert(fake.tracks[2].colour == flagged(2))
end

function T.parent_follows_folder_colour()
  local list = rule_list([[
    { id = "d", filter = "drums", colour = { mode = "fixed", rgb = "#4080C2" } },
    { id = "p", filter = "(children)", colour = { mode = "parent" } }]])
  local fake = fake_reaper.install({
    { name = "Drums", folder = 1 },
    { name = "Kick", depth = 1, parent = 1 },
    { name = "Snare", depth = 1, parent = 1 },
  })
  colour_pass(list)
  assert(fake.tracks[2].colour == flagged(0x4080C2))
  assert(fake.tracks[3].colour == flagged(0x4080C2))
end

function T.parent_without_colour_changes_nothing()
  local list = rule_list([[{ id = "p", filter = "(children)", colour = { mode = "parent" } }]])
  local fake = fake_reaper.install({ { name = "Folder", folder = 1 }, { name = "Kid", depth = 1, parent = 1, colour = flagged(7) } })
  colour_pass(list)
  assert(fake.tracks[2].colour == flagged(7))
  assert(fake.tracks[2].ext.eminor_autocolor == nil)
end

function T.master_only_with_master_filter()
  local list = rule_list([[
    { id = "a", filter = "(any)", colour = { mode = "fixed", rgb = "#000001" } },
    { id = "m", filter = "(master)", colour = { mode = "fixed", rgb = "#000002" } }]])
  local fake = fake_reaper.install({ { name = "x" } })
  colour_pass(list)
  assert(fake.master.colour == flagged(2))
  assert(fake.tracks[1].colour == flagged(1))
end

function T.switch_off_skips_pass_but_force_runs()
  local fake = fake_reaper.install({ { name = "Guitar" } })
  apply.run_pass(GUITAR_RED, { track_colour = false }, false)
  assert(fake.tracks[1].colour == 0)
  apply.force(GUITAR_RED)
  assert(fake.tracks[1].colour == flagged(0xBF0004))
end

function T.colour_sws_set_is_taken_over_on_first_sight()
  -- Under SWS this track was red as a "guitar"; it is now renamed "bass".
  local list = rule_list([[
    { id = "g", filter = "guitar", colour = { mode = "fixed", rgb = "#BF0004" } },
    { id = "b", filter = "bass", colour = { mode = "fixed", rgb = "#0000FF" } }]])
  local fake = fake_reaper.install({ { name = "bass", colour = flagged(0xBF0004) } })
  colour_pass(list)
  assert(fake.tracks[1].colour == flagged(0x0000FF))
end

function T.colour_unlike_any_rule_is_not_taken_over()
  local list = rule_list([[{ id = "b", filter = "bass", colour = { mode = "fixed", rgb = "#0000FF" } }]])
  local fake = fake_reaper.install({ { name = "bass", colour = flagged(0x123456) } })
  colour_pass(list)
  assert(fake.tracks[1].colour == flagged(0x123456))
end

function T.hand_colour_matching_a_rule_is_kept_once_seen()
  -- Seen once, then given a rule's colour by hand: that is a hand change.
  local list = rule_list([[
    { id = "g", filter = "guitar", colour = { mode = "fixed", rgb = "#BF0004" } },
    { id = "b", filter = "bass", colour = { mode = "fixed", rgb = "#0000FF" } }]])
  local fake = fake_reaper.install({ { name = "bass" } })
  colour_pass(list)
  fake.tracks[1].colour = flagged(0xBF0004)
  colour_pass(list)
  assert(fake.tracks[1].colour == flagged(0xBF0004))
end

function T.colour_switch_off_leaves_colour_but_runs_others()
  local list = rule_list([[{ id = "g", filter = "guitar", icon = "gtr.png", colour = { mode = "fixed", rgb = "#BF0004" } }]])
  local fake = fake_reaper.install({ { name = "guitar" } })
  apply.run_pass(list, { track_colour = false, track_icon = true }, false)
  assert(fake.tracks[1].colour == 0)
  assert(fake.tracks[1].icon == fake_reaper.ICONS .. "gtr.png")
end

return T
