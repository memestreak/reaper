-- tests/run.lua
--
-- Runs every test file. From the repository root:
--   lua scripts/eminor_autocolor/tests/run.lua
--
-- Each test file returns a table of name -> function. A test fails by
-- raising an error (assert).

local here = debug.getinfo(1, "S").source:match("^@?(.*[/\\])") or "./"
package.path = here .. "../?.lua;" .. here .. "?.lua;" .. package.path

local FILES = {
  "test_colour", "test_rules", "test_match", "test_state", "test_apply",
  "test_icons_layouts", "test_markers", "test_sws_import", "test_watch", "test_timing",
}

local passed, failed = 0, 0
for _, file in ipairs(FILES) do
  local tests = require(file)
  local names = {}
  for name in pairs(tests) do names[#names + 1] = name end
  table.sort(names)
  for _, name in ipairs(names) do
    local ok, err = pcall(tests[name])
    if ok then
      passed = passed + 1
    else
      failed = failed + 1
      print(string.format("FAIL %s: %s\n  %s", file, name, err))
    end
  end
end
print(string.format("%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
