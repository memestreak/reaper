-- ui/editor.lua
--
-- The rule editor window (ReaImGui). Layout, as picked from the mocks:
--   * Header: the five on/off switches as toggle pills, then Undo/Redo,
--     Force and a gear for Settings.
--   * Rules grouped into Tracks, Regions and Markers, each in its own
--     priority order, edited inline: drag the grip to reorder, tick to
--     enable, click the swatch for colours, type the filter, click the
--     icon for the icon browser, pick layouts from menus.
--   * Footer: what is coloured, and whether the engine is running.
--
-- Every edit is saved to the rules file at once and the engine is told,
-- so it applies within a tick. Cmd+Z / Cmd+Shift+Z undo and redo rule
-- edits. The editor never changes the project itself, except through
-- Force; the engine does the colouring.
--
-- When the window is closed, its defer loop ends and nothing is left
-- running.

local rules_module = require("lib.rules")
local settings = require("lib.settings")
local engine = require("lib.engine")
local engine_action = require("lib.engine_action")
local sws_switches = require("lib.sws_switches")
local prefs = require("lib.prefs")
local match = require("lib.match")
local apply = require("lib.apply")
local model_module = require("lib.editor_model")
local W = require("ui.widgets")
local colour_popover = require("ui.colour_popover")
local icons = require("ui.icons")
local settings_dialog = require("ui.settings_dialog")
local palettes_dialog = require("ui.palettes_dialog")

local M = {}

local TITLE = "Eminor Auto Color"
local FILE_CHECK_SECONDS = 1
local COUNT_CHECK_SECONDS = 1
local RECENT_KEY = "editor.recent_colours"
local RECENT_LIMIT = 8
local SWATCH_W, SWATCH_H = 34, 16

local FADED = 0.4  -- alpha of greyed-out rules and columns

local GROUPS = {
  -- `switches`: the group is greyed while all of these are off; "Turn on"
  -- turns on the first.
  { target = "track", title = "Tracks", switches = { "track_colour", "track_icon", "track_layout" },
    off_note = "Track colour, icon and layout are off." },
  { target = "region", title = "Regions", switches = { "region_colour" },
    off_note = "Region colour is off." },
  { target = "marker", title = "Markers", switches = { "marker_colour" },
    off_note = "Marker colour is off." },
}

local function log(message)
  reaper.ShowConsoleMsg("Eminor Auto Color editor: " .. message .. "\n")
end


-- -----------------------------------------------------------------------------
-- Project info for match counts. Read only when the project changes.
-- -----------------------------------------------------------------------------

local function read_project()
  local project = { tracks = {}, markers = {}, regions = {} }
  project.tracks[1] = match.track_info(reaper.GetMasterTrack(0), true)
  for i = 0, reaper.CountTracks(0) - 1 do
    project.tracks[#project.tracks + 1] = match.track_info(reaper.GetTrack(0, i), false)
  end
  local index = 0
  while true do
    local retval, is_region, _, _, name = reaper.EnumProjectMarkers3(0, index)
    if retval == 0 then break end
    local list = is_region and project.regions or project.markers
    list[#list + 1] = { name = name or "" }
    index = index + 1
  end
  return project
end

-- The theme's layout names for "tcp" or "mcp".
local function theme_layouts(section)
  local names = {}
  local i = 0
  while true do
    local ok, name = reaper.ThemeLayout_GetLayout(section, i)
    if not ok then break end
    if name ~= "" then names[#names + 1] = name end
    i = i + 1
  end
  return names
end


-- -----------------------------------------------------------------------------
-- Recent colours (a viewer convenience, in ExtState)
-- -----------------------------------------------------------------------------

local function read_recent()
  local list = {}
  for hex in reaper.GetExtState(settings.SECTION, RECENT_KEY):gmatch("#%x%x%x%x%x%x") do
    list[#list + 1] = tonumber(hex:sub(2), 16)
  end
  return list
end

local function write_recent(list)
  local parts = {}
  for i, rgb in ipairs(list) do parts[i] = string.format("#%06X", rgb) end
  reaper.SetExtState(settings.SECTION, RECENT_KEY, table.concat(parts, ","), true)
end


-- -----------------------------------------------------------------------------
-- The editor
-- -----------------------------------------------------------------------------

function M.run(ImGui)
  local ctx = ImGui.CreateContext(TITLE)
  local font = ImGui.CreateFont("Helvetica Neue")
  ImGui.Attach(ctx, font)

  local path = rules_module.file_path()
  local last_text = rules_module.read_file(path)
  if not last_text then
    -- First run: create the rules file (copying SWS's rules, if any), as
    -- the engine would.
    engine.create_rules_file(path)
    last_text = rules_module.read_file(path)
    if not last_text then
      reaper.MB("Couldn't create the rules file:\n" .. path, TITLE, 0)
      return
    end
  end
  -- Make sure the engine is in the Action List, so it can be started from
  -- here, from toolbars, and from Settings › Startup.
  engine_action.command_id()
  local rules, problems, palettes = rules_module.parse(last_text)
  for _, p in ipairs(problems) do log(p) end
  local model = model_module.new(rules, palettes)

  local ui = {
    selected = nil,            -- id of the selected rule
    filter_buffers = {},       -- rule id -> text being typed
    popover = nil,             -- state of the open colour popover
    icon_target = nil,         -- rule id the icon browser is choosing for
    icon_state = {},
    open_request = nil,        -- "settings", "palettes" or "icons", opened at window level
    layouts = {},              -- section -> names, refreshed when a menu opens
    recent = read_recent(),
    counts = {}, coloured = { track = 0, marker = 0, region = 0 },
    project_count = nil, next_count_check = 0, next_file_check = 0,
    sws_on = {}, next_sws_check = 0,  -- SWS's own switches, read once a second
  }

  -- Esc closes the open popover (and only it: see handle_keys).
  local function close_popup_on_esc()
    if ImGui.IsKeyPressed(ctx, ImGui.Key_Escape) then ImGui.CloseCurrentPopup(ctx) end
  end

  -- Saving -----------------------------------------------------------------

  local function save()
    local text = model:text()
    local ok, err = rules_module.write_file(path, text)
    if not ok then
      log("could not save the rules file: " .. tostring(err))
      return
    end
    last_text = text
    settings.bump_rules_version()
    ui.next_count_check = 0
  end

  local function edit(label, change)
    model:edit(label, change)
    save()
  end

  local function undo() if model:undo() then save() end end
  local function redo() if model:redo() then save() end end

  -- The file can change behind the editor (edited by hand). Reload it then.
  local function check_file(now)
    if now < ui.next_file_check then return end
    ui.next_file_check = now + FILE_CHECK_SECONDS
    local text = rules_module.read_file(path)
    if text and text ~= last_text then
      last_text = text
      local new_rules, new_problems, new_palettes = rules_module.parse(text)
      for _, p in ipairs(new_problems) do log(p) end
      model:replace(new_rules, new_palettes)
    end
  end

  local function check_counts(now)
    local count = reaper.GetProjectStateChangeCount(0)
    if count == ui.project_count and now < ui.next_count_check then return end
    ui.project_count = count
    ui.next_count_check = now + COUNT_CHECK_SECONDS
    ui.counts, ui.coloured = model_module.match_counts(model.doc, read_project())
  end

  local function check_sws(now)
    if now < ui.next_sws_check then return end
    ui.next_sws_check = now + COUNT_CHECK_SECONDS
    ui.sws_on = sws_switches.read()
  end

  -- Header -----------------------------------------------------------------

  local function draw_header()
    local switches = settings.read_switches()
    -- Pills wrap onto a second line when the window is narrow.
    for i, switch in ipairs(settings.SWITCHES) do
      if i > 1 then
        ImGui.SameLine(ctx, nil, 6)
        if ImGui.GetContentRegionAvail(ctx) < W.pill_width(ImGui, ctx, switch.label) then
          ImGui.NewLine(ctx)
        end
      end
      if W.pill(ImGui, ctx, "##sw_" .. switch.key, switch.label, switches[switch.key]) then
        settings.set_switch(switch.key, not switches[switch.key])
      end
    end

    local right_w = 220
    ImGui.SameLine(ctx)
    local avail = ImGui.GetContentRegionAvail(ctx)
    if avail > right_w then
      ImGui.SetCursorPosX(ctx, ImGui.GetCursorPosX(ctx) + avail - right_w)
    else
      ImGui.NewLine(ctx)
    end

    ImGui.BeginDisabled(ctx, not model:can_undo())
    if ImGui.Button(ctx, "Undo") then undo() end
    ImGui.EndDisabled(ctx)
    if model:can_undo() then ImGui.SetItemTooltip(ctx, "Undo " .. model:undo_label() .. " (Cmd+Z)") end
    ImGui.SameLine(ctx, nil, 4)
    ImGui.BeginDisabled(ctx, not model:can_redo())
    if ImGui.Button(ctx, "Redo") then redo() end
    ImGui.EndDisabled(ctx)
    if model:can_redo() then ImGui.SetItemTooltip(ctx, "Redo " .. model:redo_label() .. " (Cmd+Shift+Z)") end

    ImGui.SameLine(ctx)
    if ImGui.Button(ctx, "Force") then apply.force(model.doc.rules) end
    ImGui.SetItemTooltip(ctx, "Apply every rule now, overwriting colours set by hand (one undo point in REAPER)")
    ImGui.SameLine(ctx)
    if ImGui.Button(ctx, "Settings") then ui.open_request = "settings" end
  end

  -- Rule rows --------------------------------------------------------------

  local function set_field(rule_id, label, field, value)
    edit(label, function(doc)
      local rule = model_module.find(doc, rule_id)
      if rule then rule[field] = value end
    end)
  end

  local function draw_filter(rule)
    local id = rule.id
    local arrow_w = ImGui.GetFrameHeight(ctx)
    ImGui.SetNextItemWidth(ctx, -arrow_w - 4)
    local buffer = ui.filter_buffers[id] or rule.filter
    local _, text = ImGui.InputText(ctx, "##filter", buffer)
    ui.filter_buffers[id] = ImGui.IsItemActive(ctx) and text or nil
    if ImGui.IsItemDeactivatedAfterEdit(ctx) and text ~= "" and text ~= rule.filter then
      set_field(id, "Change filter", "filter", text)
    end
    ImGui.SameLine(ctx, nil, 4)
    if ImGui.ArrowButton(ctx, "##specials", ImGui.Dir_Down) then ImGui.OpenPopup(ctx, "specials") end
    ImGui.SetItemTooltip(ctx, "Special filters")
    if ImGui.BeginPopup(ctx, "specials") then
      close_popup_on_esc()
      local names = {}
      local source = rule.target == "track" and match.TRACK_FILTERS or match.MARKER_FILTERS
      for name in pairs(source) do names[#names + 1] = name end
      if rule.target == "track" then names[#names + 1] = match.MASTER_FILTER end
      table.sort(names, function(a, b) return a:lower() < b:lower() end)
      for _, name in ipairs(names) do
        if ImGui.Selectable(ctx, name, name == rule.filter) then
          set_field(id, "Change filter", "filter", name)
        end
      end
      ImGui.EndPopup(ctx)
    end
  end

  local function draw_colour(rule)
    if W.swatch(ImGui, ctx, "##swatch", rule.colour, SWATCH_W, SWATCH_H) then
      ui.popover = { rule_id = rule.id }
      ImGui.OpenPopup(ctx, "colour")
    end
    ImGui.SetItemTooltip(ctx, W.describe(rule.colour))
    if ImGui.BeginPopup(ctx, "colour") then
      close_popup_on_esc()
      if ui.popover and ui.popover.rule_id == rule.id then
        colour_popover.draw(ImGui, ctx, rule, ui.popover, {
          palettes = model.doc.palettes,
          in_use = model_module.colours_in_use(model.doc),
          recent = ui.recent,
          set_colour = function(spec, label, used_rgb)
            set_field(rule.id, label, "colour", spec)
            if used_rgb then
              model_module.push_recent(ui.recent, used_rgb, RECENT_LIMIT)
              write_recent(ui.recent)
            end
          end,
          edit_palettes = function() ui.open_request = "palettes" end,
        })
      end
      ImGui.EndPopup(ctx)
    end
  end

  local function draw_layout(rule, field, section)
    local value = rule[field]
    local preview = value == "" and "—" or value
    ImGui.SetNextItemWidth(ctx, -1)
    if ImGui.BeginCombo(ctx, "##" .. field, preview) then
      if ImGui.IsWindowAppearing(ctx) then ui.layouts[section] = theme_layouts(section) end
      local choices = { { "", "— (theme default)" }, { "(hide)", "(hide) the track here" } }
      for _, name in ipairs(ui.layouts[section] or {}) do choices[#choices + 1] = { name, name } end
      for _, choice in ipairs(choices) do
        if ImGui.Selectable(ctx, choice[2], choice[1] == value) and choice[1] ~= value then
          set_field(rule.id, "Change layout", field, choice[1])
        end
      end
      ImGui.EndCombo(ctx)
    end
  end

  local function row_menu(rule, position, group_size)
    if ImGui.BeginPopupContextItem(ctx, "row_menu") then
      if ImGui.MenuItem(ctx, "Duplicate") then
        edit("Duplicate rule", function(doc)
          local copy = model_module.duplicate_rule(doc, rule.id)
          if copy then ui.selected = copy.id end
        end)
      end
      if ImGui.MenuItem(ctx, "Move up", nil, false, position > 1) then
        edit("Move rule", function(doc) model_module.move_within(doc, rule.target, position, position - 1) end)
      end
      if ImGui.MenuItem(ctx, "Move down", nil, false, position < group_size) then
        edit("Move rule", function(doc) model_module.move_within(doc, rule.target, position, position + 1) end)
      end
      ImGui.Separator(ctx)
      if ImGui.MenuItem(ctx, "Delete") then
        edit("Delete rule", function(doc) model_module.delete_rule(doc, rule.id) end)
      end
      ImGui.EndPopup(ctx)
    end
  end

  -- The grip: selects the row, drags to reorder, right-click for the menu.
  local function draw_grip(rule, position, group_size, row_h)
    local selected = ui.selected == rule.id
    local flags = ImGui.SelectableFlags_SpanAllColumns | ImGui.SelectableFlags_AllowOverlap
    if ImGui.Selectable(ctx, "::##grip", selected, flags, 0, row_h) then
      ui.selected = rule.id
    end
    row_menu(rule, position, group_size)
    local payload_type = "eminor_autocolor_" .. rule.target
    if ImGui.BeginDragDropSource(ctx) then
      ImGui.SetDragDropPayload(ctx, payload_type, tostring(position))
      ImGui.Text(ctx, rule.filter)
      ImGui.EndDragDropSource(ctx)
    end
    if ImGui.BeginDragDropTarget(ctx) then
      local ok, payload = ImGui.AcceptDragDropPayload(ctx, payload_type)
      if ok then
        local from = tonumber(payload)
        edit("Move rule", function(doc) model_module.move_within(doc, rule.target, from, position) end)
      end
      ImGui.EndDragDropTarget(ctx)
    end
  end

  local function draw_group(group, thumb)
    local rules = model_module.group(model.doc, group.target)
    local is_track = group.target == "track"

    ImGui.Spacing(ctx)
    ImGui.AlignTextToFramePadding(ctx)
    ImGui.Text(ctx, group.title)
    ImGui.SameLine(ctx)
    ImGui.TextDisabled(ctx, tostring(#rules))
    ImGui.SameLine(ctx)
    if ImGui.SmallButton(ctx, "+##add_" .. group.target) then
      edit("Add rule", function(doc)
        local rule = model_module.add_rule(doc, group.target)
        ui.selected = rule.id
      end)
    end
    ImGui.SetItemTooltip(ctx, "Add a " .. group.target .. " rule")

    -- While the group's switches are all off, its rules do nothing: say so
    -- and grey the list (it can still be edited).
    local switches = settings.read_switches()
    local off = true
    for _, key in ipairs(group.switches) do
      if switches[key] then off = false end
    end
    if off then
      ImGui.SameLine(ctx)
      ImGui.TextDisabled(ctx, group.off_note)
      ImGui.SameLine(ctx)
      if ImGui.SmallButton(ctx, "Turn on##on_" .. group.target) then
        settings.set_switch(group.switches[1], true)
      end
    end
    if #rules == 0 then return end  -- just the title line: nothing to list

    local columns = is_track and 10 or 7
    local flags = ImGui.TableFlags_RowBg | ImGui.TableFlags_SizingFixedFit | ImGui.TableFlags_PadOuterX
    if not ImGui.BeginTable(ctx, "##table_" .. group.target, columns, flags) then return end
    -- Fixed columns are at least as wide as their title.
    local function column(name, width)
      if width then
        if name:sub(1, 2) ~= "##" then width = math.max(width, (ImGui.CalcTextSize(ctx, name))) end
        ImGui.TableSetupColumn(ctx, name, ImGui.TableColumnFlags_WidthFixed, width)
      else
        ImGui.TableSetupColumn(ctx, name, ImGui.TableColumnFlags_WidthStretch)
      end
    end
    column("##grip", 14)
    column("On", ImGui.GetFrameHeight(ctx))
    column("Colour", SWATCH_W)
    column("Filter")
    column("##mode", 96)
    if is_track then
      column("Icon", thumb + 10)
      column("TCP layout", 90)
      column("MCP layout", 90)
    end
    column("Matches", 34)
    column("##delete", ImGui.GetFrameHeight(ctx))
    ImGui.TableHeadersRow(ctx)

    local row_h = math.max(ImGui.GetFrameHeight(ctx), is_track and thumb + 6 or 0)
    -- Greyed (still editable): the whole list while the group's switches
    -- are off, a row while its rule is off, and a track column while the
    -- switch it belongs to is off.
    local colour_off = is_track and not switches.track_colour
    local icon_off = not switches.track_icon
    local layout_off = not switches.track_layout
    local function cell(dim, draw)
      ImGui.TableNextColumn(ctx)
      if dim then ImGui.PushStyleVar(ctx, ImGui.StyleVar_Alpha, FADED) end
      draw()
      if dim then ImGui.PopStyleVar(ctx) end
    end

    for position, rule in ipairs(rules) do
      ImGui.PushID(ctx, rule.id)
      ImGui.TableNextRow(ctx, nil, row_h)
      local row_off = off or not rule.enabled

      cell(row_off, function() draw_grip(rule, position, #rules, row_h) end)

      -- The rule's own on/off box stays bright, so it's easy to turn back on.
      cell(off, function()
        local changed, on = ImGui.Checkbox(ctx, "##on", rule.enabled)
        if changed then set_field(rule.id, on and "Enable rule" or "Disable rule", "enabled", on) end
        ImGui.SetItemTooltip(ctx, on and "Rule on" or "Rule off")
      end)

      cell(row_off or colour_off, function() draw_colour(rule) end)
      cell(row_off, function() draw_filter(rule) end)
      cell(row_off or colour_off, function()
        ImGui.AlignTextToFramePadding(ctx)
        ImGui.TextDisabled(ctx, W.describe(rule.colour))
      end)

      if is_track then
        cell(row_off or icon_off, function()
          if icons.thumbnail(ImGui, ctx, "##icon", rule.icon, thumb) then
            ui.icon_target = rule.id
            ui.open_request = "icons"
          end
          ImGui.SetItemTooltip(ctx, rule.icon == "" and "Choose an icon" or rule.icon)
        end)
        cell(row_off or layout_off, function() draw_layout(rule, "tcp_layout", "tcp") end)
        cell(row_off or layout_off, function() draw_layout(rule, "mcp_layout", "mcp") end)
      end

      cell(row_off, function()
        ImGui.AlignTextToFramePadding(ctx)
        ImGui.TextDisabled(ctx, tostring(ui.counts[rule.id] or 0))
        ImGui.SetItemTooltip(ctx, "Items this rule's filter matches")
      end)

      cell(off, function()
        if W.trash_button(ImGui, ctx, "##delete", ImGui.GetFrameHeight(ctx)) then
          edit("Delete rule", function(doc) model_module.delete_rule(doc, rule.id) end)
          if ui.selected == rule.id then ui.selected = nil end
        end
        ImGui.SetItemTooltip(ctx, "Delete rule (Cmd+Z brings it back)")
      end)

      ImGui.PopID(ctx)
    end
    ImGui.EndTable(ctx)
  end

  -- Footer -----------------------------------------------------------------

  local function draw_footer()
    ImGui.Separator(ctx)
    -- What the rules colour now, for the kinds whose colour switch is on.
    local c, switches = ui.coloured, settings.read_switches()
    local counted, switched_off = {}, {}
    for _, kind in ipairs({
      { target = "track", key = "track_colour", word = "track", label = "Track colour" },
      { target = "region", key = "region_colour", word = "region", label = "Region colour" },
      { target = "marker", key = "marker_colour", word = "marker", label = "Marker colour" },
    }) do
      if switches[kind.key] then
        local n = c[kind.target]
        counted[#counted + 1] = n .. " " .. kind.word .. (n == 1 and "" or "s")
      else
        switched_off[#switched_off + 1] = kind.label
      end
    end
    local n_rules = #model.doc.rules
    local parts = { n_rules .. (n_rules == 1 and " rule" or " rules") }
    if #counted > 0 then parts[#parts + 1] = "colouring " .. table.concat(counted, ", ") end
    if #switched_off > 0 then
      parts[#parts + 1] = table.concat(switched_off, " and ")
          .. (#switched_off == 1 and " is off" or " are off")
    end
    ImGui.TextDisabled(ctx, table.concat(parts, " · "))
    if #counted > 0 then
      ImGui.SetItemTooltip(ctx, "Items a rule gives a colour to (hand-set colours are kept unless you Force).")
    end
    if not engine_action.is_running() then
      ImGui.SameLine(ctx)
      ImGui.TextColored(ctx, W.WARN, "Engine is off: rules apply only when it runs.")
      ImGui.SameLine(ctx)
      if ImGui.SmallButton(ctx, "Start engine") then
        local ok, err = engine_action.start()
        if not ok then log(err) end
      end
    end
    -- SWS doing the same job undoes ours (and the other way round).
    local switches, clashes = settings.read_switches(), {}
    for _, switch in ipairs(sws_switches.LIST) do
      if switches[switch.key] and ui.sws_on[switch.key] then clashes[#clashes + 1] = switch.label end
    end
    if #clashes > 0 then
      ImGui.SameLine(ctx)
      ImGui.TextColored(ctx, W.WARN, "SWS Auto Color is also on.")
      ImGui.SetItemTooltip(ctx, "On in SWS too: " .. table.concat(clashes, ", ")
          .. ".\nTurn them off in Settings › SWS.")
    end
  end

  -- Keyboard ---------------------------------------------------------------

  local function selected_position()
    local rule = ui.selected and model_module.find(model.doc, ui.selected)
    if not rule then return nil end
    for position, r in ipairs(model_module.group(model.doc, rule.target)) do
      if r.id == rule.id then return rule, position end
    end
  end

  local function handle_keys()
    -- A popup or a field being typed in gets keys first. Esc closes them
    -- before this runs, so also look at whether one was open last frame:
    -- otherwise the same Esc would close the editor too.
    local busy = ImGui.IsAnyItemActive(ctx) or ImGui.IsPopupOpen(ctx, "", ImGui.PopupFlags_AnyPopup)
    local was_busy = ui.busy_last_frame
    ui.busy_last_frame = busy
    if busy or was_busy then return end
    if not ImGui.IsWindowFocused(ctx, ImGui.FocusedFlags_RootAndChildWindows) then return end
    -- Esc closes the editor when nothing else is using it.
    if ImGui.IsKeyPressed(ctx, ImGui.Key_Escape) then ui.close_requested = true return end
    local ctrl, shift, alt = ImGui.Mod_Ctrl, ImGui.Mod_Shift, ImGui.Mod_Alt
    if ImGui.IsKeyChordPressed(ctx, ctrl | shift | ImGui.Key_Z) then redo() return end
    if ImGui.IsKeyChordPressed(ctx, ctrl | ImGui.Key_Z) then undo() return end

    local rule, position = selected_position()
    if not rule then return end
    local group = model_module.group(model.doc, rule.target)
    if ImGui.IsKeyPressed(ctx, ImGui.Key_Delete) or ImGui.IsKeyPressed(ctx, ImGui.Key_Backspace) then
      edit("Delete rule", function(doc) model_module.delete_rule(doc, rule.id) end)
      local next_rule = group[position + 1] or group[position - 1]
      ui.selected = next_rule and next_rule.id
    elseif ImGui.IsKeyChordPressed(ctx, alt | ImGui.Key_UpArrow) and position > 1 then
      edit("Move rule", function(doc) model_module.move_within(doc, rule.target, position, position - 1) end)
    elseif ImGui.IsKeyChordPressed(ctx, alt | ImGui.Key_DownArrow) and position < #group then
      edit("Move rule", function(doc) model_module.move_within(doc, rule.target, position, position + 1) end)
    elseif ImGui.IsKeyPressed(ctx, ImGui.Key_UpArrow) and position > 1 then
      ui.selected = group[position - 1].id
    elseif ImGui.IsKeyPressed(ctx, ImGui.Key_DownArrow) and position < #group then
      ui.selected = group[position + 1].id
    end
  end

  -- Window-level popups ----------------------------------------------------

  local function draw_window_popups()
    local request = ui.open_request
    ui.open_request = nil
    if request == "settings" then settings_dialog.open(ImGui, ctx) end
    if request == "palettes" then palettes_dialog.open(ImGui, ctx) end
    if request == "icons" then ImGui.OpenPopup(ctx, "Icons##browser") end

    settings_dialog.draw(ImGui, ctx, { rules = model.doc.rules, edit = edit })
    palettes_dialog.draw(ImGui, ctx, {
      palettes = model.doc.palettes,
      in_use = model_module.colours_in_use(model.doc),
      edit = edit,
    })

    if ImGui.BeginPopup(ctx, "Icons##browser") then
      close_popup_on_esc()
      local rule = ui.icon_target and model_module.find(model.doc, ui.icon_target)
      if rule then
        local chosen = icons.browser(ImGui, ctx, ui.icon_state, rule.icon)
        if chosen then
          if chosen ~= rule.icon then set_field(rule.id, "Change icon", "icon", chosen) end
          ImGui.CloseCurrentPopup(ctx)
        end
      else
        ImGui.CloseCurrentPopup(ctx)
      end
      ImGui.EndPopup(ctx)
    end
  end

  -- Frame ------------------------------------------------------------------

  local function frame()
    local now = reaper.time_precise()
    check_file(now)
    check_counts(now)
    check_sws(now)
    icons.new_frame()
    local thumb = prefs.read("appearance").thumb_size

    local pop_theme = W.push_theme(ImGui, ctx)
    ImGui.PushFont(ctx, font, 13)
    ImGui.SetNextWindowSize(ctx, 760, 520, ImGui.Cond_FirstUseEver)
    local visible, open = ImGui.Begin(ctx, TITLE, true, ImGui.WindowFlags_NoCollapse)
    if visible then
      draw_header()
      ImGui.Spacing(ctx)
      -- The rules area is as tall as its rules (so the footer sits right
      -- under them), and scrolls once they don't fit in the window.
      local footer_h = ImGui.GetFrameHeightWithSpacing(ctx) + 6
      local _, avail_h = ImGui.GetContentRegionAvail(ctx)
      ImGui.SetNextWindowSizeConstraints(ctx, 0, 0, 1e6, math.max(40, avail_h - footer_h))
      if ImGui.BeginChild(ctx, "##rules", 0, 0, ImGui.ChildFlags_AutoResizeY) then
        for _, group in ipairs(GROUPS) do draw_group(group, thumb) end
        ImGui.EndChild(ctx)
      end
      draw_footer()
      draw_window_popups()
      handle_keys()
      ImGui.End(ctx)
    end
    ImGui.PopFont(ctx)
    pop_theme()
    return open and not ui.close_requested
  end

  local function loop()
    if frame() then reaper.defer(loop) end
  end
  reaper.defer(loop)
end

return M
