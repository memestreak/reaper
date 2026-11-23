local rules = require("lib.rules")
local model_module = require("lib.editor_model")

local T = {}

local TEXT = [[return { rules = {
  { id = "t1", target = "track", filter = "guitar", colour = { mode = "fixed", rgb = "#BF0004" } },
  { id = "r1", target = "region", filter = "verse", colour = { mode = "family", base = "#8AC627" } },
  { id = "t2", target = "track", filter = "drums", colour = { mode = "fixed", rgb = "#4080C2" } },
  { id = "t3", target = "track", filter = "synth", colour = { mode = "fixed", rgb = "#1B8F1B" } },
}, palettes = { { name = "Blues", colours = { "#0000FF", "#3030FF" } } } }]]

local function load()
  local list, problems, palettes = rules.parse(TEXT)
  assert(#problems == 0, problems[1])
  return model_module.new(list, palettes)
end

local function ids(list)
  local out = {}
  for i, r in ipairs(list) do out[i] = r.id end
  return table.concat(out, ",")
end

function T.groups_keep_priority_order()
  local m = load()
  assert(ids(model_module.group(m.doc, "track")) == "t1,t2,t3")
  assert(ids(model_module.group(m.doc, "region")) == "r1")
end

function T.move_within_group_leaves_other_targets_in_place()
  local m = load()
  m:edit("Move rule", function(doc) assert(model_module.move_within(doc, "track", 3, 1)) end)
  assert(ids(m.doc.rules) == "t3,r1,t1,t2")
  assert(not model_module.move_within(m.doc, "track", 1, 9))
end

function T.undo_and_redo_restore_exact_states()
  local m = load()
  local original = m:text()
  m:edit("Delete rule", function(doc) model_module.delete_rule(doc, "t2") end)
  local after_delete = m:text()
  assert(after_delete ~= original)
  assert(m:undo_label() == "Delete rule")
  assert(m:undo() and m:text() == original)
  assert(m:redo_label() == "Delete rule")
  assert(m:redo() and m:text() == after_delete)
  assert(not m:can_redo())
end

function T.new_edit_clears_redo()
  local m = load()
  m:edit("A", function(doc) model_module.delete_rule(doc, "t1") end)
  m:undo()
  m:edit("B", function(doc) model_module.delete_rule(doc, "t2") end)
  assert(not m:can_redo())
end

function T.undo_keeps_a_limit()
  local m = load()
  for i = 1, model_module.UNDO_LIMIT + 5 do
    m:edit("x", function(doc) doc.rules[1].filter = "f" .. i end)
  end
  assert(#m.undo_stack == model_module.UNDO_LIMIT)
end

function T.added_and_duplicated_rules_get_fresh_ids_and_survive_a_round_trip()
  local m = load()
  local new
  m:edit("Add rule", function(doc) new = model_module.add_rule(doc, "marker") end)
  assert(new.id and new.target == "marker")
  local copy
  m:edit("Duplicate", function(doc) copy = model_module.duplicate_rule(doc, "t1") end)
  assert(copy.id ~= "t1" and m.doc.rules[2] == copy)
  local again, problems, palettes = rules.parse(m:text())
  assert(#problems == 0, problems[1])
  assert(#again == 6 and #palettes == 1 and palettes[1].colours[2] == 0x3030FF)
end

function T.colours_in_use_are_distinct_and_ordered()
  local m = load()
  local list = model_module.colours_in_use(m.doc)
  assert(#list == 4 and list[1] == 0xBF0004 and list[2] == 0x8AC627)
end

function T.recent_colours_move_to_front_without_repeats()
  local recent = { 1, 2, 3 }
  model_module.push_recent(recent, 2, 3)
  assert(table.concat(recent, ",") == "2,1,3")
  model_module.push_recent(recent, 9, 3)
  assert(table.concat(recent, ",") == "9,2,1")
end

function T.match_counts_and_coloured_totals()
  local m = load()
  local function track(name)
    return { is_master = false, name = name, is_folder = false, depth = 0, receives = 0,
      rec_armed = false, vca_master = false, has_instrument = false, rec_input = -1,
      hw_outputs = 0, midi_hw_out = -1 }
  end
  local counts, coloured = model_module.match_counts(m.doc, {
    tracks = { track("Guitar L"), track("Guitar R"), track("Bass") },
    regions = { { name = "Verse 1" }, { name = "Chorus" } },
  })
  assert(counts.t1 == 2 and counts.t2 == 0 and counts.r1 == 1)
  assert(coloured.track == 2 and coloured.region == 1 and coloured.marker == 0)
end

return T
