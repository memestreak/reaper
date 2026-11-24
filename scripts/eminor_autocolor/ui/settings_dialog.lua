-- ui/settings_dialog.lua
--
-- Settings, shaped like REAPER's Preferences (Jeremy's settings rules):
-- a fixed-size modal with sections on the left, the selected section on
-- the right, and OK / Apply / Cancel. Changes are staged until OK or
-- Apply. Double-clicking a field's label resets it to its default. Esc, a
-- click outside, or the close button is the same as Cancel.
--
-- The five on/off switches are live controls, so they live in the
-- editor's header and the Action List, not here. SWS's own switches are
-- here (staged like the rest), with Import from SWS, which opens over this
-- dialog and is an undoable edit of the rules rather than a setting.

local prefs = require("lib.prefs")
local startup = require("lib.startup")
local settings = require("lib.settings")
local sws_switches = require("lib.sws_switches")
local sws_import_dialog = require("ui.sws_import_dialog")
local W = require("ui.widgets")

local M = {}

M.POPUP = "Settings##eminor_autocolor"

local SECTIONS = {
  { key = "engine", label = "Engine" },
  { key = "appearance", label = "Appearance" },
  { key = "startup", label = "Startup" },
  { key = "sws", label = "SWS" },
}

local WIDTH, HEIGHT = 600, 340
local LIST_WIDTH = 140

local state = nil  -- { section, saved = {...}, staged = {...}, message }

local function load()
  return {
    engine = prefs.read("engine"),
    appearance = prefs.read("appearance"),
    startup = { enabled = startup.is_enabled() },
    sws = sws_switches.read(),
  }
end

local function copy(t)
  local c = {}
  for k, v in pairs(t) do c[k] = type(v) == "table" and copy(v) or v end
  return c
end

local function differs(a, b)
  for section, values in pairs(a) do
    for key, value in pairs(values) do
      if b[section][key] ~= value then return true end
    end
  end
  return false
end

local function save()
  local staged = state.staged
  prefs.write("engine", staged.engine)
  prefs.write("appearance", staged.appearance)
  state.message = nil
  if staged.startup.enabled ~= state.saved.startup.enabled then
    local named = reaper.GetExtState(settings.SECTION, "toggle_cmd." .. settings.ENGINE)
    if named == "" then named = startup.find_engine_command() end
    local ok, err = startup.set_enabled(staged.startup.enabled, named)
    if not ok then
      state.message = err
      staged.startup.enabled = state.saved.startup.enabled
    end
  end
  for key, on in pairs(staged.sws) do
    if on ~= state.saved.sws[key] then sws_switches.set(key, on) end
  end
  settings.notify_engine()
  state.saved = load()
  state.staged = copy(state.saved)
end

function M.open(ImGui, ctx)
  local saved = load()
  state = { section = "engine", saved = saved, staged = copy(saved) }
  ImGui.OpenPopup(ctx, M.POPUP)
end

-- A field label that resets the field on double-click.
local function label(ImGui, ctx, text, reset)
  ImGui.AlignTextToFramePadding(ctx)
  ImGui.Text(ctx, text)
  if ImGui.IsItemHovered(ctx) then
    ImGui.SetTooltip(ctx, "Double-click to reset")
    if ImGui.IsMouseDoubleClicked(ctx, ImGui.MouseButton_Left) then reset() end
  end
  ImGui.SameLine(ctx, 200)
end

local function draw_number_fields(ImGui, ctx, section)
  local values = state.staged[section]
  for _, f in ipairs(prefs.FIELDS[section]) do
    label(ImGui, ctx, f.label, function() values[f.key] = f.default end)
    ImGui.SetNextItemWidth(ctx, 120)
    local step = f.max >= 1000 and 50 or 1
    local _, v = ImGui.InputInt(ctx, "##" .. f.key, values[f.key], step, step * 10)
    values[f.key] = math.max(f.min, math.min(f.max, v))
    ImGui.SameLine(ctx)
    ImGui.TextDisabled(ctx, f.unit)
    ImGui.PushTextWrapPos(ctx, 0)
    ImGui.TextDisabled(ctx, f.help)
    ImGui.PopTextWrapPos(ctx)
    ImGui.Spacing(ctx)
  end
end

local function draw_startup(ImGui, ctx)
  local values = state.staged.startup
  label(ImGui, ctx, "Start the engine with REAPER", function() values.enabled = false end)
  local _, on = ImGui.Checkbox(ctx, "##startup", values.enabled)
  values.enabled = on
  if state.message then
    ImGui.PushTextWrapPos(ctx, 0)
    ImGui.TextColored(ctx, W.WARN, state.message)
    ImGui.PopTextWrapPos(ctx)
  end
  ImGui.PushTextWrapPos(ctx, 0)
  ImGui.TextDisabled(ctx, "Adds one line to Scripts/__startup.lua, or removes it. "
      .. "The rest of that file is left as it is.")
  ImGui.PopTextWrapPos(ctx)
end

local function help(ImGui, ctx, text)
  ImGui.PushTextWrapPos(ctx, 0)
  ImGui.TextDisabled(ctx, text)
  ImGui.PopTextWrapPos(ctx)
end

local function draw_sws(ImGui, ctx)
  local values = state.staged.sws
  if not sws_switches.installed() then
    help(ImGui, ctx, "SWS isn't installed, so there is nothing to switch off.")
  else
    for _, switch in ipairs(sws_switches.LIST) do
      if values[switch.key] ~= nil then
        label(ImGui, ctx, switch.label, function() values[switch.key] = false end)
        local _, on = ImGui.Checkbox(ctx, "##sws_" .. switch.key, values[switch.key])
        values[switch.key] = on
      end
    end
    help(ImGui, ctx, "SWS's own Auto Color switches. Leave them off: when SWS and "
        .. "eminor Auto Color both colour the same things, they undo each other's work.")
  end
  ImGui.Spacing(ctx)
  ImGui.Separator(ctx)
  ImGui.Spacing(ctx)
  -- Opened after the pane ends: a popup's ID depends on the window it is
  -- opened from, and Import is drawn from the dialog, not the pane.
  if ImGui.Button(ctx, "Import rules from SWS…") then state.open_import = true end
  help(ImGui, ctx, "Copies the rules from SWS Auto Color into yours. "
      .. "This changes your rules at once (not on OK), and Undo in the editor takes it back.")
end

-- Draws the dialog when open. Call every frame. `context` is passed on to
-- Import from SWS: { rules = the current rules, edit(label, change(doc)) }.
function M.draw(ImGui, ctx, context)
  if not state then return end
  ImGui.SetNextWindowSize(ctx, WIDTH, HEIGHT, ImGui.Cond_Always)
  local flags = ImGui.WindowFlags_NoResize | ImGui.WindowFlags_NoSavedSettings
  local visible, open = ImGui.BeginPopupModal(ctx, M.POPUP, true, flags)
  if not visible then
    if not ImGui.IsPopupOpen(ctx, M.POPUP) then state = nil end
    return
  end

  -- Esc while Import is open closes only Import.
  local import_open = ImGui.IsPopupOpen(ctx, sws_import_dialog.POPUP)
  local footer_h = ImGui.GetFrameHeightWithSpacing(ctx) + 8
  if ImGui.BeginChild(ctx, "##sections", LIST_WIDTH, -footer_h, ImGui.ChildFlags_Borders) then
    for _, section in ipairs(SECTIONS) do
      if ImGui.Selectable(ctx, section.label, state.section == section.key) then
        state.section = section.key
      end
    end
    ImGui.EndChild(ctx)
  end
  ImGui.SameLine(ctx)
  if ImGui.BeginChild(ctx, "##pane", 0, -footer_h, ImGui.ChildFlags_Borders) then
    for _, section in ipairs(SECTIONS) do
      if section.key == state.section then ImGui.SeparatorText(ctx, section.label) end
    end
    if state.section == "startup" then
      draw_startup(ImGui, ctx)
    elseif state.section == "sws" then
      draw_sws(ImGui, ctx)
    else
      draw_number_fields(ImGui, ctx, state.section)
    end
    ImGui.EndChild(ctx)
  end

  local button_w = 80
  local avail = ImGui.GetContentRegionAvail(ctx)
  ImGui.SetCursorPosX(ctx, ImGui.GetCursorPosX(ctx) + avail - 3 * button_w - 16)
  local close = false
  if ImGui.Button(ctx, "OK", button_w) then
    save()
    -- Stay open to show a problem; it is shown in the section it belongs to.
    if state.message then state.section = "startup" else close = true end
  end
  ImGui.SameLine(ctx)
  ImGui.BeginDisabled(ctx, not differs(state.staged, state.saved))
  if ImGui.Button(ctx, "Apply", button_w) then save() end
  ImGui.EndDisabled(ctx)
  ImGui.SameLine(ctx)
  if ImGui.Button(ctx, "Cancel", button_w) then close = true end
  -- Esc or a click outside is Cancel (but while Import is open, it's Import's).
  if not import_open and (ImGui.IsKeyPressed(ctx, ImGui.Key_Escape) or W.clicked_outside(ImGui, ctx)) then
    close = true
  end
  if state.open_import then
    state.open_import = nil
    sws_import_dialog.open(ImGui, ctx)
  end
  sws_import_dialog.draw(ImGui, ctx, context)

  if close or not open then
    ImGui.CloseCurrentPopup(ctx)
    state = nil
  end
  ImGui.EndPopup(ctx)
end

return M
