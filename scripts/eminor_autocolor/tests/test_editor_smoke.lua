-- Runs the editor's frames against fake REAPER and fake ReaImGui APIs.
-- This can't show how the window looks; it catches Lua errors, calls to
-- functions ReaImGui doesn't have, wrong argument counts, unbalanced
-- Begin/End pairs, and checks that the main actions edit the rules file.

local fake_reaper = require("fake_reaper")
local fake_imgui = require("fake_imgui")
local rules = require("lib.rules")

local T = {}

local RULES = [[return { rules = {
  { id = "g", target = "track", filter = "guitar", icon = "songs/a.png", tcp_layout = "Wide",
    colour = { mode = "fixed", rgb = "#BF0004" } },
  { id = "d", target = "track", filter = "drums", colour = { mode = "gradient", from = "#000000", to = "#FFFFFF" } },
  { id = "v", target = "region", filter = "verse", colour = { mode = "family", base = "#8AC627" } },
  { id = "c", target = "region", filter = "chorus", colour = { mode = "family", palette = { "#EA8D20", "#F8C823" } } },
  { id = "m", target = "marker", filter = "(any)", colour = { mode = "none" } },
}, palettes = { { name = "Song sections", colours = { "#EA8D20", "#8AC627" } } } }]]

-- Sets up a project, a rules file in a temporary resource folder, and the
-- editor. Returns the fake ImGui, a step() that runs one frame, and a
-- function reading the rules file back.
local function start()
  local fake = fake_reaper.install(
    { { name = "Guitar L" }, { name = "Drums", folder = 1 }, { name = "Kick", depth = 1, parent = 2 } },
    { { name = "Verse 1", region = true }, { name = "Chorus", region = true }, { name = "cue" } })

  -- A fresh folder under $TMPDIR (os.tmpname needs /tmp, which sandboxes may block).
  local base = os.getenv("TMPDIR") or "/tmp"
  local resource = string.format("%s/eminor_autocolor_test_%d_%d", base:gsub("/$", ""),
      os.time(), math.random(1, 1e9))
  os.execute("mkdir -p '" .. resource .. "/Data/eminor_autocolor' '" .. resource .. "/Scripts'")
  local path = resource .. "/Data/eminor_autocolor/rules.lua"
  assert(rules.write_file(path, RULES))

  local ext, loop, clock = {}, nil, 0
  function fake.GetResourcePath() return resource end
  function fake.GetExtState(section, key) return (ext[section .. "/" .. key]) or "" end
  function fake.SetExtState(section, key, value) ext[section .. "/" .. key] = value end
  function fake.time_precise() clock = clock + 0.04; return clock end
  function fake.defer(fn) loop = fn end
  function fake.ShowConsoleMsg(text) error("unexpected console message: " .. text) end
  function fake.MB(text) error("unexpected message box: " .. text) end
  function fake.GetProjectStateChangeCount() return 1 end
  function fake.ThemeLayout_GetLayout(section, i)
    local names = { "A", "B", "Wide" }
    if names[i + 1] then return true, names[i + 1] end
    return false, ""
  end
  local files = { ["/Data/track_icons"] = { "x.png", "notes.txt" }, ["/Data/track_icons/songs"] = { "a.png" } }
  function fake.EnumerateFiles(folder, i)
    local list = files[folder:sub(#resource + 1)] or {}
    return list[i + 1]
  end
  function fake.EnumerateSubdirectories(folder, i)
    if folder:sub(#resource + 1) == "/Data/track_icons" and i == 0 then return "songs" end
    return nil
  end

  local imgui = fake_imgui.new()
  -- Fresh copies of the UI modules, since they keep state between frames.
  for name in pairs(package.loaded) do
    if name:match("^ui%.") then package.loaded[name] = nil end
  end
  require("ui.editor").run(imgui.ImGui)
  assert(loop, "editor did not start its loop")

  local function step()
    local current = loop
    loop = nil
    current()
    fake_imgui.assert_balanced(imgui)
    assert(loop, "editor stopped")
  end
  local function file()
    local list, problems, palettes = rules.parse(rules.read_file(path))
    assert(#problems == 0, problems[1])
    return list, palettes, ext
  end
  return imgui, step, file, fake
end

local function find(list, id)
  for _, r in ipairs(list) do if r.id == id then return r end end
end

function T.frames_run_cleanly()
  local imgui, step = start()
  for _ = 1, 3 do step() end
  assert(imgui.calls.BeginTable == 9, "expected three tables per frame")
end

function T.add_rule_and_undo()
  local imgui, step, file, fake = start()
  step()
  imgui.press("+##add_marker")
  step()
  assert(#file() == 6)
  imgui.press("Undo")
  step()
  assert(#file() == 5)
  imgui.press("Redo")
  step()
  assert(#file() == 6)
end

function T.switch_pill_toggles_setting()
  local imgui, step, _, fake = start()
  step()
  imgui.press("##sw_track_layout")
  step()
  assert(fake.GetExtState("eminor_autocolor", "switch.track_layout") == "1")
end

function T.colour_popover_renders_every_mode_and_applies_a_palette_colour()
  local imgui, step, file = start()
  step()
  -- Open the guitar rule's popover; the first swatch drawn is the guitar rule's.
  imgui.press("##swatch")
  step()
  assert(imgui.opened["colour"], "popover did not open")
  imgui.press("##pal1_2")   -- "In use" row, second colour (the gradient's black)
  step()
  local rule = find(file(), "g")
  assert(rule.colour.mode == "fixed" and rule.colour.rgb == 0x000000, string.format("%06X", rule.colour.rgb))

  -- The other modes render too.
  for _, label in ipairs({ "Family (similar shades)", "Gradient", "Random", "Parent's colour",
                           "No colour (clears it)", "Ignore (leave colour alone)", "Fixed colour" }) do
    imgui.combos["##mode"] = true
    imgui.press(label)
    step()
    imgui.combos["##mode"] = nil
    step()
  end
  assert(find(file(), "g").colour.mode == "fixed")
end

function T.family_palette_toggle_and_saved_palette()
  local imgui, step, file = start()
  step()
  imgui.press("##swatch")
  step()
  imgui.combos["##mode"] = true
  imgui.press("Family (similar shades)")
  step()
  imgui.combos["##mode"] = nil
  imgui.press("Palette")
  step()
  local rule = find(file(), "g")
  assert(rule.colour.mode == "family" and rule.colour.palette and rule.colour.palette[1] == 0xEA8D20)
  imgui.press("Range")
  step()
  rule = find(file(), "g")
  assert(rule.colour.base and not rule.colour.palette)
end

function T.icon_browser_sets_icon()
  local imgui, step, file = start()
  step()
  imgui.press("##icon")
  step()
  assert(imgui.opened["Icons##browser"], "icon browser did not open")
  step()
  imgui.press("##icon_x.png")
  step()
  assert(find(file(), "g").icon == "x.png")
end

function T.layout_menu_sets_layout()
  local imgui, step, file = start()
  step()
  imgui.combos["##mcp_layout"] = true
  imgui.press("B")
  step()
  assert(find(file(), "g").mcp_layout == "B")
end

function T.settings_dialog_saves_on_ok()
  local imgui, step, _, fake = start()
  step()
  imgui.press("Settings")
  step()
  assert(imgui.opened["Settings##eminor_autocolor"], "settings did not open")
  step()
  imgui.press("Startup")
  step()
  imgui.press("OK")
  step()
  assert(not imgui.opened["Settings##eminor_autocolor"])
  assert(fake.GetExtState("eminor_autocolor", "settings.engine") == "backstop_ms=500")
end

function T.palettes_dialog_adds_a_palette()
  local imgui, step, file = start()
  step()
  imgui.press("##swatch")
  step()
  imgui.press("Edit palettes…")
  step()
  step()
  assert(imgui.opened["Palettes##eminor_autocolor"], "palettes dialog did not open")
  imgui.press("New palette")
  step()
  local _, palettes = file()
  assert(#palettes == 2 and palettes[2].name == "Palette 2")
end

function T.force_button_colours_the_project()
  local imgui, step, _, fake = start()
  step()
  imgui.press("Force")
  step()
  assert(fake.tracks[1].colour == fake_reaper.flagged(0xBF0004))
end

return T
