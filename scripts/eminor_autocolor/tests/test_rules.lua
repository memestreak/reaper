local rules = require("lib.rules")

local T = {}

local SAMPLE = [[
return {
  version = 1,
  rules = {
    { target = "track", filter = "guitar", colour = { mode = "fixed", rgb = "#BF0004" } },
    { id = "v", target = "region", filter = "verse",
      colour = { mode = "family", base = "#8AC627", hue = 8, light = 0.12 } },
    { target = "track", filter = "(folder)", colour = { mode = "parent" }, enabled = false },
    { target = "region", filter = "pads", colour = { mode = "parent" } },
    { target = "track", filter = "", colour = { mode = "none" } },
    { target = "track", filter = "bad", colour = { mode = "fixed", rgb = "red" } },
    { target = "track", filter = "pal", colour = { mode = "family", palette = { "#111111", "#222222" } } },
  },
}
]]

function T.parse_keeps_good_rules_and_reports_bad_ones()
  local list, problems = rules.parse(SAMPLE)
  assert(#list == 4, "expected 4 good rules, got " .. #list)
  assert(#problems == 3, "expected 3 problems, got " .. #problems)
  assert(list[1].colour.rgb == 0xBF0004)
  assert(list[2].id == "v")
  assert(list[2].colour.base == 0x8AC627)
  assert(list[3].enabled == false)
  assert(list[4].colour.palette[2] == 0x222222)
end

function T.ids_are_unique_and_generated()
  local list = rules.parse([[return { rules = {
    { id = "r1", filter = "a" }, { id = "r1", filter = "b" }, { filter = "c" } } }]])
  local seen = {}
  for _, rule in ipairs(list) do
    assert(rule.id and not seen[rule.id], "duplicate or missing id")
    seen[rule.id] = true
  end
  assert(list[1].id == "r1")
end

function T.missing_colour_means_ignore()
  local list = rules.parse([[return { rules = { { filter = "drums", icon = "drums.png" } } }]])
  assert(list[1].colour.mode == "ignore")
  assert(list[1].target == "track")
end

function T.serialize_round_trips()
  local list = rules.parse(SAMPLE)
  local text = rules.serialize(list)
  local again = rules.parse(text)
  assert(rules.serialize(again) == text)
  assert(#again == #list)
end

function T.file_cannot_call_functions()
  local list, problems = rules.parse([[os.remove("x") return { rules = {} }]])
  assert(#list == 0 and #problems == 1)
end

function T.syntax_errors_are_reported()
  local list, problems = rules.parse("return {")
  assert(#list == 0 and problems[1]:find("syntax error"))
end

return T
