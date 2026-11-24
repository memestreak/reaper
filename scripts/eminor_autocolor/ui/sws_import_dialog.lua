-- ui/sws_import_dialog.lua
--
-- Import from SWS: copies the rules in sws-autocoloricon.ini into yours,
-- either after them or in their place. It opens over Settings. The import
-- is one edit, so the editor's Undo takes it back.

local rules_module = require("lib.rules")
local sws_import = require("lib.sws_import")
local W = require("ui.widgets")

local M = {}

M.POPUP = "Import from SWS##eminor_autocolor"

local state = nil  -- { imported = rules, problems = list, how = "add"|"replace" }

local function ini_path()
  local sep = package.config:sub(1, 1)
  return reaper.GetResourcePath() .. sep .. "sws-autocoloricon.ini"
end

local function from_native(native)
  local r, g, b = reaper.ColorFromNative(native)
  return (r << 16) | (g << 8) | b
end

-- Reads SWS's rules now, so the dialog shows what is there at this moment.
function M.open(ImGui, ctx)
  local text = rules_module.read_file(ini_path())
  local imported, problems = {}, {}
  if text then imported, problems = sws_import.convert(text, from_native) end
  state = { found_file = text ~= nil, imported = imported, problems = problems, how = "add" }
  ImGui.OpenPopup(ctx, M.POPUP)
end

local function plural(n, word)
  return n .. " " .. word .. (n == 1 and "" or "s")
end

local function summary(counts)
  return string.format("%s, %s, %s", plural(counts.track, "track rule"),
      plural(counts.region, "region rule"), plural(counts.marker, "marker rule"))
end

-- `context`: { rules = your current rules, edit(label, change(doc)) }.
-- Call between the Begin/End of the window that opened it.
function M.draw(ImGui, ctx, context)
  if not state then return end
  ImGui.SetNextWindowSize(ctx, 440, 0, ImGui.Cond_Always)
  local flags = ImGui.WindowFlags_NoResize | ImGui.WindowFlags_NoSavedSettings
  local visible, open = ImGui.BeginPopupModal(ctx, M.POPUP, true, flags)
  if not visible then
    if not ImGui.IsPopupOpen(ctx, M.POPUP) then state = nil end
    return
  end

  local close = false
  local imported = state.imported
  ImGui.PushTextWrapPos(ctx, 0)
  if not state.found_file then
    ImGui.Text(ctx, "No SWS rules found.")
    ImGui.TextDisabled(ctx, "SWS keeps them in sws-autocoloricon.ini in REAPER's resource folder, "
        .. "and there isn't one.")
  elseif #imported == 0 then
    ImGui.Text(ctx, "SWS has no rules to import.")
  else
    ImGui.Text(ctx, "SWS has " .. summary(sws_import.count(imported)) .. ".")
    ImGui.Spacing(ctx)
    state.how = W.segmented(ImGui, ctx, "how", {
      { label = "Add to my rules", value = "add" },
      { label = "Replace my rules", value = "replace" },
    }, state.how)
    local result, skipped = sws_import.merge(context.rules, imported, state.how)
    if state.how == "add" then
      local added = #result - #context.rules
      local text = "Adds " .. plural(added, "rule") .. " after yours."
      if skipped > 0 then
        text = text .. " " .. plural(skipped, "rule") .. " with a type and filter you already have "
            .. (skipped == 1 and "is" or "are") .. " left out."
      end
      ImGui.TextDisabled(ctx, text)
    else
      ImGui.TextDisabled(ctx, "Your " .. plural(#context.rules, "rule") .. " are replaced by SWS's "
          .. #imported .. ".")
    end
    ImGui.TextDisabled(ctx, "Undo in the editor takes it back.")
  end
  if #state.problems > 0 then
    ImGui.Spacing(ctx)
    ImGui.TextColored(ctx, W.WARN, plural(#state.problems, "line") .. " couldn't be read:")
    for i = 1, math.min(5, #state.problems) do ImGui.TextDisabled(ctx, state.problems[i]) end
  end
  ImGui.PopTextWrapPos(ctx)

  ImGui.Spacing(ctx)
  local can_import = #imported > 0
  if can_import then
    local result = sws_import.merge(context.rules, imported, state.how)
    ImGui.BeginDisabled(ctx, #result == #context.rules and state.how == "add")
    if ImGui.Button(ctx, "Import", 80) then
      local label = state.how == "add" and "Import rules from SWS" or "Replace rules with SWS's"
      context.edit(label, function(doc)
        -- The imported rules go in as they are: the dialog drops its own
        -- list when it closes, so nothing else holds them.
        local list = sws_import.merge(doc.rules, imported, state.how)
        doc.rules = list
        rules_module.assign_ids(doc.rules)
      end)
      close = true
    end
    ImGui.EndDisabled(ctx)
    ImGui.SameLine(ctx)
  end
  if ImGui.Button(ctx, can_import and "Cancel" or "Close", 80) then close = true end
  if ImGui.IsKeyPressed(ctx, ImGui.Key_Escape) or W.clicked_outside(ImGui, ctx) then close = true end

  if close or not open then
    ImGui.CloseCurrentPopup(ctx)
    state = nil
  end
  ImGui.EndPopup(ctx)
end

return M
