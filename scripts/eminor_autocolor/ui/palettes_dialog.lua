-- ui/palettes_dialog.lua
--
-- Edit palettes: saved, named colour lists that the colour popover offers.
-- They are saved in the rules file with the rules, so every edit here is
-- undoable like a rule edit. A family rule copies a palette's colours when
-- you pick it, so changing a palette later doesn't change existing rules.

local W = require("ui.widgets")

local M = {}

M.POPUP = "Palettes##eminor_autocolor"

local CELL = 20
local state = nil   -- { names = {index -> text being typed}, adding = index, rgb }

function M.open(ImGui, ctx)
  state = { names = {}, rgb = 0x4080C2 }
  ImGui.OpenPopup(ctx, M.POPUP)
end

-- `context`: { palettes = list, in_use = list, edit(label, change(doc)) }
function M.draw(ImGui, ctx, context)
  if not state then return end
  ImGui.SetNextWindowSize(ctx, 460, 420, ImGui.Cond_Appearing)
  local visible, open = ImGui.BeginPopupModal(ctx, M.POPUP, true)
  if not visible then
    if not ImGui.IsPopupOpen(ctx, M.POPUP) then state = nil end
    return
  end

  local palettes = context.palettes
  if #palettes == 0 then
    ImGui.TextDisabled(ctx, "No palettes yet.")
  end
  for i, palette in ipairs(palettes) do
    ImGui.PushID(ctx, "palette" .. i)
    ImGui.SetNextItemWidth(ctx, 200)
    local _, name = ImGui.InputText(ctx, "##name", state.names[i] or palette.name)
    state.names[i] = ImGui.IsItemActive(ctx) and name or nil
    if ImGui.IsItemDeactivatedAfterEdit(ctx) and name ~= "" and name ~= palette.name then
      context.edit("Rename palette", function(doc) doc.palettes[i].name = name end)
    end
    ImGui.SameLine(ctx)
    if ImGui.SmallButton(ctx, "Delete") then
      context.edit("Delete palette", function(doc) table.remove(doc.palettes, i) end)
    end

    for j, rgb in ipairs(palette.colours) do
      if j > 1 then ImGui.SameLine(ctx, nil, 4) end
      if W.colour_cell(ImGui, ctx, "##c" .. j, rgb, CELL, false) then
        context.edit("Remove colour", function(doc) table.remove(doc.palettes[i].colours, j) end)
      end
      if ImGui.IsItemHovered(ctx) then ImGui.SetTooltip(ctx, "Click to remove") end
    end
    if #palette.colours > 0 then ImGui.SameLine(ctx, nil, 4) end
    if ImGui.Button(ctx, "+", CELL, CELL) then
      state.adding = state.adding ~= i and i or nil
    end
    if state.adding == i then
      local flags = ImGui.ColorEditFlags_NoSidePreview | ImGui.ColorEditFlags_NoAlpha
          | ImGui.ColorEditFlags_PickerHueBar | ImGui.ColorEditFlags_DisplayHex
      ImGui.SetNextItemWidth(ctx, 200)
      local _, rgb = ImGui.ColorPicker3(ctx, "##add", state.rgb, flags)
      state.rgb = rgb
      if ImGui.Button(ctx, "Add colour") then
        context.edit("Add colour", function(doc)
          local list = doc.palettes[i].colours
          list[#list + 1] = state.rgb
        end)
      end
    end
    ImGui.Separator(ctx)
    ImGui.PopID(ctx)
  end

  if ImGui.Button(ctx, "New palette") then
    context.edit("New palette", function(doc)
      doc.palettes[#doc.palettes + 1] = { name = "Palette " .. (#doc.palettes + 1), colours = {} }
    end)
  end
  ImGui.SameLine(ctx)
  ImGui.BeginDisabled(ctx, #context.in_use == 0)
  if ImGui.Button(ctx, "New palette from colours in use") then
    local colours = {}
    for k, rgb in ipairs(context.in_use) do colours[k] = rgb end
    context.edit("New palette", function(doc)
      doc.palettes[#doc.palettes + 1] = { name = "In use " .. os.date("%Y-%m-%d"), colours = colours }
    end)
  end
  ImGui.EndDisabled(ctx)

  ImGui.Spacing(ctx)
  if ImGui.Button(ctx, "Close", 80) or ImGui.IsKeyPressed(ctx, ImGui.Key_Escape)
      or W.clicked_outside(ImGui, ctx) or not open then
    ImGui.CloseCurrentPopup(ctx)
    state = nil
  end
  ImGui.EndPopup(ctx)
end

return M
