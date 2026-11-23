local fake_reaper = require("fake_reaper")
local rules = require("lib.rules")
local colour = require("lib.colour")
local apply = require("lib.apply")
local apply_markers = require("lib.apply_markers")

local T = {}
local flagged = fake_reaper.flagged

local function rule_list(text)
  local list, problems = rules.parse("return { rules = {" .. text .. "} }")
  assert(#problems == 0, problems[1])
  return list
end

local ON = { marker_colour = true, region_colour = true }
local function pass(list) return apply_markers.run(list, ON, false) end

local VERSE = rule_list([[
  { id = "v", target = "region", filter = "verse", colour = { mode = "fixed", rgb = "#8AC627" } }]])

function T.region_rule_colours_regions_not_markers()
  local fake = fake_reaper.install({}, {
    { name = "Verse 1", region = true }, { name = "verse cue" }, { name = "Chorus", region = true } })
  assert(pass(VERSE) == 1)
  assert(fake.markers[1].colour == flagged(0x8AC627))
  assert(fake.markers[2].colour == 0)
  assert(fake.markers[3].colour == 0)
  fake.marker_writes = 0
  assert(pass(VERSE) == 0 and fake.marker_writes == 0)
end

function T.existing_colour_is_taken_over_on_first_sight()
  -- SWS always recoloured markers, so a colour found on a matching one is SWS's.
  local fake = fake_reaper.install({}, { { name = "Verse", region = true, colour = flagged(0x123456) } })
  pass(VERSE)
  assert(fake.markers[1].colour == flagged(0x8AC627))
end

function T.hand_colour_is_kept_once_seen_until_force()
  local fake = fake_reaper.install({}, { { name = "Verse", region = true } })
  pass(VERSE)
  fake.markers[1].colour = flagged(0x00FF00)
  pass(VERSE)
  assert(fake.markers[1].colour == flagged(0x00FF00))
  apply.force(VERSE)
  assert(fake.markers[1].colour == flagged(0x8AC627))
end

function T.colour_is_cleared_when_rule_stops_matching()
  local fake = fake_reaper.install({}, { { name = "Verse", region = true } })
  pass(VERSE)
  fake.markers[1].name = "Bridge"
  pass(VERSE)
  assert(fake.markers[1].colour == 0)
  assert(next(fake.proj_ext.eminor_autocolor or {}) == nil)
end

function T.clearing_falls_back_to_theme_colour_when_zero_is_ignored()
  local fake = fake_reaper.install({}, { { name = "Verse", region = true } }, { colour_zero_keeps = true })
  pass(VERSE)
  fake.markers[1].name = "Bridge"
  pass(VERSE)
  assert(fake.markers[1].colour == flagged(fake_reaper.THEME_REGION))
end

function T.none_mode_settles_after_one_write()
  local list = rule_list([[{ id = "n", target = "marker", filter = "(any)", colour = { mode = "none" } }]])
  local fake = fake_reaper.install({}, { { name = "x", colour = flagged(5) } }, { colour_zero_keeps = true })
  pass(list)
  assert(fake.markers[1].colour == flagged(fake_reaper.THEME_MARKER))
  fake.marker_writes = 0
  pass(list)
  assert(fake.marker_writes == 0, "kept rewriting a cleared colour")
end

function T.family_regions_keep_their_colours_when_a_verse_is_added()
  local list = rule_list([[
    { id = "f", target = "region", filter = "verse", colour = { mode = "family", base = "#8AC627" } }]])
  local fake = fake_reaper.install({}, {
    { name = "Verse", region = true, guid = "{A}", pos = 10 },
    { name = "Verse", region = true, guid = "{B}", pos = 20 } })
  pass(list)
  local a, b = fake.markers[1].colour, fake.markers[2].colour
  assert(a == flagged(0x8AC627) and a ~= b)

  -- A new verse is added before the others. Project ExtState carries over.
  local ext = fake.proj_ext
  local fake2 = fake_reaper.install({}, {
    { name = "Verse", region = true, guid = "{NEW}", pos = 1 },
    { name = "Verse", region = true, guid = "{A}", pos = 10, colour = a },
    { name = "Verse", region = true, guid = "{B}", pos = 20, colour = b } })
  fake2.proj_ext = ext
  pass(list)
  assert(fake2.markers[2].colour == a and fake2.markers[3].colour == b)
  assert(fake2.markers[1].colour == flagged(colour.family_colour(list[1].colour, 2)))
end

function T.state_of_deleted_markers_is_pruned()
  local fake = fake_reaper.install({}, { { name = "Verse", region = true, guid = "{A}" } })
  pass(VERSE)
  assert(fake.proj_ext.eminor_autocolor["m:{A}"])
  table.remove(fake.markers, 1)
  pass(VERSE)
  assert(fake.proj_ext.eminor_autocolor["m:{A}"] == nil)
end

function T.switches_are_separate_for_markers_and_regions()
  local list = rule_list([[
    { id = "m", target = "marker", filter = "cue", colour = { mode = "fixed", rgb = "#000001" } },
    { id = "r", target = "region", filter = "verse", colour = { mode = "fixed", rgb = "#000002" } }]])
  local fake = fake_reaper.install({}, { { name = "cue" }, { name = "verse", region = true } })
  apply_markers.run(list, { marker_colour = false, region_colour = true }, false)
  assert(fake.markers[1].colour == 0)
  assert(fake.markers[2].colour == flagged(2))
end

function T.force_covers_markers_in_one_undo_point()
  local fake = fake_reaper.install({ { name = "x" } }, { { name = "Verse", region = true } })
  apply.force(VERSE)
  assert(fake.markers[1].colour == flagged(0x8AC627))
  assert(fake.undo_blocks == 1)
end

return T
