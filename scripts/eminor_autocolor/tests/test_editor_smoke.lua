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

function T.escape_closes_the_editor()
  local imgui, step = start()
  step()
  local real = imgui.ImGui.IsKeyPressed
  rawset(imgui.ImGui, "IsKeyPressed", function(ctx, key, ...)
    real(ctx, key, ...)
    return key == imgui.ImGui.Key_Escape
  end)
  local ok, err = pcall(step)
  assert(not ok and err:find("editor stopped"), "editor kept running after Esc")
end

function T.force_button_colours_the_project()
  local imgui, step, _, fake = start()
  step()
  imgui.press("Force")
  step()
  assert(fake.tracks[1].colour == fake_reaper.flagged(0xBF0004))
end

-- Jeremy's SWS rules, shortened: two tracks (one he already has) and a region.
local SWS_INI = [[
[SWS]
AutoColor 1=0 guitar 46071812 "" "" ""
AutoColor 2=0 synth 35360539 "" "" ""
AutoColor 3=2 bridge 41943104 "" "" ""
AutoColorEnable=1
]]

local function install_sws(fake)
  fake.sws = {
    ["_SWSAUTOCOLOR_ENABLE"] = 1, ["_S&MAUTOICON_ENABLE"] = 0, ["_S&MAUTOLAYOUT_ENABLE"] = 0,
    ["_S&MAUTOCOLOR_MKR_ENABLE"] = 0, ["_S&MAUTOCOLOR_RGN_ENABLE"] = 0,
  }
  assert(rules.write_file(fake.GetResourcePath() .. "/sws-autocoloricon.ini", SWS_INI))
end

local function open_sws_settings(imgui, step)
  step()
  imgui.press("Settings")
  step()
  imgui.press("SWS")
  step()
end

function T.settings_turns_sws_switches_off_on_ok()
  local imgui, step, _, fake = start()
  install_sws(fake)
  open_sws_settings(imgui, step)
  imgui.press("##sws_track_colour")
  step()
  assert(#fake.commands_run == 0, "changed before OK")
  imgui.press("OK")
  step()
  assert(fake.commands_run[1] == "_SWSAUTOCOLOR_ENABLE" and #fake.commands_run == 1)
  assert(fake.sws["_SWSAUTOCOLOR_ENABLE"] == 0)
end

function T.import_from_sws_adds_new_rules_and_undoes()
  local imgui, step, file, fake = start()
  install_sws(fake)
  open_sws_settings(imgui, step)
  imgui.press("Import rules from SWS…")
  step()
  assert(imgui.opened["Import from SWS##eminor_autocolor"], "import did not open")
  step()
  imgui.press("Import")
  step()
  assert(not imgui.opened["Import from SWS##eminor_autocolor"])
  assert(imgui.opened["Settings##eminor_autocolor"], "settings should stay open")
  local list = file()
  assert(#list == 7, #list)  -- 5 + synth + bridge; guitar is already there
  assert(list[6].filter == "synth" and list[7].filter == "bridge")
  imgui.press("Cancel")
  step()
  imgui.press("Undo")
  step()
  assert(#file() == 5)
end

function T.esc_in_import_closes_only_import()
  local imgui, step, _, fake = start()
  install_sws(fake)
  open_sws_settings(imgui, step)
  imgui.press("Import rules from SWS…")
  step()
  local real = imgui.ImGui.IsKeyPressed
  rawset(imgui.ImGui, "IsKeyPressed", function(ctx, key, ...)
    real(ctx, key, ...)
    return key == imgui.ImGui.Key_Escape
  end)
  step()
  rawset(imgui.ImGui, "IsKeyPressed", real)
  assert(not imgui.opened["Import from SWS##eminor_autocolor"])
  assert(imgui.opened["Settings##eminor_autocolor"])
end

function T.footer_warns_when_sws_does_the_same_job()
  local imgui, step, _, fake = start()
  install_sws(fake)
  fake.SetExtState("eminor_autocolor", "switch.track_colour", "1")
  local shown = {}
  local real = imgui.ImGui.TextColored
  rawset(imgui.ImGui, "TextColored", function(ctx, col, text)
    real(ctx, col, text)
    shown[text] = true
  end)
  step()
  assert(shown["SWS Auto Color is also on."], "no warning")
  fake.sws["_SWSAUTOCOLOR_ENABLE"] = 0
  for _ = 1, 30 do step() end  -- the SWS state is read once a second
  shown = {}
  step()
  assert(not shown["SWS Auto Color is also on."], "warning stayed")
end

function T.switched_off_group_is_greyed_and_footer_says_so()
  local imgui, step, _, fake = start()
  fake.SetExtState("eminor_autocolor", "switch.region_colour", "0")
  fake.SetExtState("eminor_autocolor", "switch.marker_colour", "0")
  local shown, alpha_pushes = {}, 0
  local real_text, real_push = imgui.ImGui.TextDisabled, imgui.ImGui.PushStyleVar
  rawset(imgui.ImGui, "TextDisabled", function(ctx, text)
    real_text(ctx, text)
    shown[text] = true
  end)
  rawset(imgui.ImGui, "PushStyleVar", function(ctx, var, ...)
    real_push(ctx, var, ...)
    if var == imgui.ImGui.StyleVar_Alpha then alpha_pushes = alpha_pushes + 1 end
  end)
  step()
  assert(shown["Region colour is off."] and shown["Marker colour is off."])
  -- Regions (2 rules) and markers (1 rule): all 7 cells of each row.
  -- Tracks (2 rules): only the TCP and MCP cells, as Track layout is off.
  assert(alpha_pushes == 3 * 7 + 2 * 2, alpha_pushes)
  local footer
  for text in pairs(shown) do if text:match("^5 rules") then footer = text end end
  assert(footer == "5 rules · colouring 2 tracks · Region colour and Marker colour are off", footer)

  imgui.press("Turn on##on_region")
  step()
  assert(fake.GetExtState("eminor_autocolor", "switch.region_colour") == "1")
end

function T.unchecked_rule_greys_its_row_but_not_its_box()
  local imgui, step, file, fake = start()
  fake.SetExtState("eminor_autocolor", "switch.track_layout", "1")
  step()
  imgui.press("##on")  -- the first rule's box (guitar)
  step()
  assert(find(file(), "g").enabled == false)

  local dim, faded_cells, faded_boxes = false, 0, 0
  local real_push, real_pop = imgui.ImGui.PushStyleVar, imgui.ImGui.PopStyleVar
  local real_check = imgui.ImGui.Checkbox
  rawset(imgui.ImGui, "PushStyleVar", function(ctx, var, ...)
    real_push(ctx, var, ...)
    if var == imgui.ImGui.StyleVar_Alpha then dim, faded_cells = true, faded_cells + 1 end
  end)
  rawset(imgui.ImGui, "PopStyleVar", function(ctx, ...) real_pop(ctx, ...) dim = false end)
  rawset(imgui.ImGui, "Checkbox", function(ctx, label, value)
    if dim then faded_boxes = faded_boxes + 1 end
    return real_check(ctx, label, value)
  end)
  step()
  assert(faded_boxes == 0, "the on/off box should stay bright")
  -- Every switch is on, so only the unchecked rule's cells fade: all but
  -- its on/off box and its delete button.
  assert(faded_cells == 8, faded_cells)
end

function T.trash_button_deletes_the_row()
  local imgui, step, file = start()
  step()
  imgui.press("##delete")  -- the first rule's (guitar)
  step()
  assert(#file() == 4 and not find(file(), "g"))
  imgui.press("Undo")
  step()
  assert(find(file(), "g"))
end
-- Esc closes an open popover, and that same Esc must not also close the
-- editor (it is already closed by the time the editor looks at keys).
function T.esc_closing_a_popover_leaves_the_editor_open()
  local imgui, step = start()
  step()
  imgui.press("##swatch")
  step()
  assert(imgui.opened["colour"], "popover did not open")
  step()
  local real = imgui.ImGui.IsKeyPressed
  rawset(imgui.ImGui, "IsKeyPressed", function(ctx, key, ...)
    real(ctx, key, ...)
    return key == imgui.ImGui.Key_Escape
  end)
  step()  -- Esc: the popover closes, and the editor keeps running
  assert(not imgui.opened["colour"], "Esc did not close the popover")
  rawset(imgui.ImGui, "IsKeyPressed", real)
  step()
end

function T.click_outside_closes_settings_but_a_click_inside_does_not()
  local imgui, step = start()
  step()
  imgui.press("Settings")
  step()
  local hovered = true
  rawset(imgui.ImGui, "IsMouseClicked", function() return true end)
  rawset(imgui.ImGui, "IsWindowHovered", function() return hovered end)
  step()
  assert(imgui.opened["Settings##eminor_autocolor"], "a click inside closed it")
  hovered = false
  step()
  assert(not imgui.opened["Settings##eminor_autocolor"], "a click outside didn't close it")
end

return T
