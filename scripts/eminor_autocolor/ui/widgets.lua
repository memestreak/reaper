-- ui/widgets.lua
--
-- The editor's look (Jeremy's REAPER theme) and a few small widgets that
-- ReaImGui doesn't have: toggle pills and rule swatches.
--
-- All colours here are ImGui's 0xRRGGBBAA form.

local colour = require("lib.colour")

local M = {}

M.ACCENT = 0x00B0F9FF       -- toolbar blue (0, 176, 249)
M.SELECTED = 0x0080B8FF     -- list selection blue (0, 128, 184)
M.TEXT = 0xE4E4E4FF
M.DIM = 0x9C9C9CFF
M.WARN = 0xE0B040FF

function M.rgba(rgb)
  return (rgb << 8) | 0xFF
end

-- Pushes the theme. Returns a function that pops it again.
function M.push_theme(ImGui, ctx)
  local colours = {
    { ImGui.Col_WindowBg, 0x333333FF },
    { ImGui.Col_ChildBg, 0x2B2C2CFF },
    { ImGui.Col_PopupBg, 0x2A2B2BFF },
    { ImGui.Col_Border, 0x474747FF },
    { ImGui.Col_Text, M.TEXT },
    { ImGui.Col_TextDisabled, M.DIM },
    { ImGui.Col_FrameBg, 0x252626FF },
    { ImGui.Col_FrameBgHovered, 0x2E2F2FFF },
    { ImGui.Col_FrameBgActive, 0x2E2F2FFF },
    { ImGui.Col_Button, 0x444545FF },
    { ImGui.Col_ButtonHovered, 0x505151FF },
    { ImGui.Col_ButtonActive, M.SELECTED },
    { ImGui.Col_Header, M.SELECTED },
    { ImGui.Col_HeaderHovered, 0x3C3D3DFF },
    { ImGui.Col_HeaderActive, M.SELECTED },
    { ImGui.Col_CheckMark, M.ACCENT },
    { ImGui.Col_SliderGrab, M.ACCENT },
    { ImGui.Col_SliderGrabActive, M.ACCENT },
    { ImGui.Col_TitleBg, 0x262727FF },
    { ImGui.Col_TitleBgActive, 0x262727FF },
    { ImGui.Col_TableHeaderBg, 0x262727FF },
    { ImGui.Col_TableRowBg, 0x2B2C2CFF },
    { ImGui.Col_TableRowBgAlt, 0x2F3030FF },
    { ImGui.Col_TableBorderLight, 0x3A3B3BFF },
    { ImGui.Col_Separator, 0x474747FF },
    { ImGui.Col_DragDropTarget, M.ACCENT },
    { ImGui.Col_NavCursor, M.ACCENT },
  }
  for _, c in ipairs(colours) do ImGui.PushStyleColor(ctx, c[1], c[2]) end
  local vars = {
    { ImGui.StyleVar_FrameRounding, 4 },
    { ImGui.StyleVar_PopupRounding, 6 },
    { ImGui.StyleVar_GrabRounding, 4 },
    { ImGui.StyleVar_ChildRounding, 4 },
    { ImGui.StyleVar_WindowPadding, 10, 10 },
    { ImGui.StyleVar_ItemSpacing, 8, 6 },
    { ImGui.StyleVar_CellPadding, 6, 3 },
  }
  for _, v in ipairs(vars) do ImGui.PushStyleVar(ctx, v[1], v[2], v[3]) end
  return function()
    ImGui.PopStyleVar(ctx, #vars)
    ImGui.PopStyleColor(ctx, #colours)
  end
end

function M.pill_width(ImGui, ctx, label)
  local text_w = ImGui.CalcTextSize(ctx, label)
  return 4 + 22 + 6 + text_w + 9
end

-- A labelled on/off pill, as in the mocks. Returns true when clicked.
function M.pill(ImGui, ctx, id, label, on)
  local _, text_h = ImGui.CalcTextSize(ctx, label)
  local h = ImGui.GetFrameHeight(ctx)
  local w = M.pill_width(ImGui, ctx, label)
  local x, y = ImGui.GetCursorScreenPos(ctx)
  local clicked = ImGui.InvisibleButton(ctx, id, w, h)
  local hovered = ImGui.IsItemHovered(ctx)
  local dl = ImGui.GetWindowDrawList(ctx)
  ImGui.DrawList_AddRectFilled(dl, x, y, x + w, y + h, hovered and 0x48494AFF or 0x3C3D3DFF, h / 2)
  local sx, sy = x + 4, y + (h - 12) / 2
  ImGui.DrawList_AddRectFilled(dl, sx, sy, sx + 22, sy + 12, on and M.ACCENT or 0x555555FF, 6)
  ImGui.DrawList_AddCircleFilled(dl, on and sx + 16 or sx + 6, sy + 6, 4, on and 0xFFFFFFFF or 0xBBBBBBFF)
  ImGui.DrawList_AddText(dl, sx + 28, y + (h - text_h) / 2, M.TEXT, label)
  return clicked
end

-- A row of equal swatches drawn into a rectangle.
local function strip(ImGui, dl, x, y, w, h, colours)
  local n = #colours
  for i, rgb in ipairs(colours) do
    local x0 = x + (i - 1) * w / n
    local x1 = x + i * w / n
    ImGui.DrawList_AddRectFilled(dl, x0, y, x1, y + h, M.rgba(rgb))
  end
end

-- Some sample colours for a colour spec (what its matches could look like).
function M.sample_colours(spec, count)
  local list = {}
  if spec.mode == "fixed" then
    list[1] = spec.rgb
  elseif spec.mode == "family" then
    for slot = 0, count - 1 do list[#list + 1] = colour.family_colour(spec, slot) end
  elseif spec.mode == "gradient" then
    for i = 1, count do list[i] = colour.gradient(spec.from, spec.to, i, count) end
  elseif spec.mode == "random" then
    for i = 1, count do list[i] = colour.random_for("sample" .. i) end
  end
  return list
end

-- The swatch for a rule's colour. Special modes get a small pattern.
-- Returns true when clicked.
function M.swatch(ImGui, ctx, id, spec, w, h)
  local x, y = ImGui.GetCursorScreenPos(ctx)
  local clicked = ImGui.InvisibleButton(ctx, id, w, h)
  local dl = ImGui.GetWindowDrawList(ctx)
  local mode = spec.mode
  if mode == "fixed" or mode == "family" or mode == "random" then
    strip(ImGui, dl, x, y, w, h, M.sample_colours(spec, mode == "fixed" and 1 or 4))
  elseif mode == "gradient" then
    local a, b = M.rgba(spec.from), M.rgba(spec.to)
    ImGui.DrawList_AddRectFilledMultiColor(dl, x, y, x + w, y + h, a, b, b, a)
  else
    ImGui.DrawList_AddRectFilled(dl, x, y, x + w, y + h, 0x252626FF, 3)
    local glyph = ({ parent = "^", none = "/", ignore = "-" })[mode] or "?"
    local gw, gh = ImGui.CalcTextSize(ctx, glyph)
    ImGui.DrawList_AddText(dl, x + (w - gw) / 2, y + (h - gh) / 2, M.DIM, glyph)
  end
  local hovered = ImGui.IsItemHovered(ctx)
  ImGui.DrawList_AddRect(dl, x, y, x + w, y + h, hovered and 0xFFFFFFAA or 0xFFFFFF22, 3)
  return clicked
end

-- A plain colour square (palette entries). Returns true when clicked.
function M.colour_cell(ImGui, ctx, id, rgb, size, picked)
  local x, y = ImGui.GetCursorScreenPos(ctx)
  local clicked = ImGui.InvisibleButton(ctx, id, size, size)
  local dl = ImGui.GetWindowDrawList(ctx)
  ImGui.DrawList_AddRectFilled(dl, x, y, x + size, y + size, M.rgba(rgb), 4)
  if picked then
    ImGui.DrawList_AddRect(dl, x - 1, y - 1, x + size + 1, y + size + 1, 0xFFFFFFFF, 4, nil, 2)
  elseif ImGui.IsItemHovered(ctx) then
    ImGui.DrawList_AddRect(dl, x, y, x + size, y + size, 0xFFFFFFAA, 4)
  end
  if ImGui.IsItemHovered(ctx) then ImGui.SetTooltip(ctx, colour.to_hex(rgb)) end
  return clicked
end

-- A small trash-can button: handle, lid, and a tapered bin with three
-- slots, drawn as shapes (no icon font needed). Returns true when clicked.
function M.trash_button(ImGui, ctx, id, size)
  local x, y = ImGui.GetCursorScreenPos(ctx)
  local clicked = ImGui.InvisibleButton(ctx, id, size, size)
  local hovered = ImGui.IsItemHovered(ctx)
  local dl = ImGui.GetWindowDrawList(ctx)
  local col = hovered and 0xE06060FF or M.DIM
  local function px(f) return x + f * size end
  local function py(f) return y + f * size end

  ImGui.DrawList_AddRect(dl, px(0.40), py(0.12), px(0.60), py(0.24), col, size * 0.04, nil,
      math.max(1, size * 0.06))                                                    -- handle
  ImGui.DrawList_AddRectFilled(dl, px(0.18), py(0.22), px(0.82), py(0.30), col, size * 0.03)  -- lid

  -- The bin narrows from top to bottom. It is drawn as four bars joined by
  -- a strip at each end, so the gaps between the bars are the slots.
  local top_y, bottom_y = 0.34, 0.88
  local function x_at(across, down)
    local t = (down - top_y) / (bottom_y - top_y)
    local left = 0.23 + (0.31 - 0.23) * t
    local right = 0.77 + (0.69 - 0.77) * t
    return left + (right - left) * across
  end
  local function band(a, b, y0, y1)
    ImGui.DrawList_AddQuadFilled(dl, px(x_at(a, y0)), py(y0), px(x_at(b, y0)), py(y0),
        px(x_at(b, y1)), py(y1), px(x_at(a, y1)), py(y1), col)
  end
  local bar, gap = 0.16, 0.12
  for i = 0, 3 do
    local a = i * (bar + gap)
    band(a, a + bar, top_y, bottom_y)
  end
  band(0, 1, top_y, top_y + 0.06)
  band(0, 1, bottom_y - 0.06, bottom_y)
  return clicked
end

-- True when the mouse was clicked outside the current window (and its
-- child windows): dialogs close on it, the same as Esc.
-- AllowWhenBlockedByActiveItem matters: a click on a button or list entry
-- makes it the active item that same frame, and without the flag
-- IsWindowHovered then reports false, so the click looked like it was outside.
function M.clicked_outside(ImGui, ctx)
  local inside = ImGui.HoveredFlags_RootAndChildWindows
      | ImGui.HoveredFlags_AllowWhenBlockedByActiveItem
  return ImGui.IsMouseClicked(ctx, ImGui.MouseButton_Left)
      and not ImGui.IsWindowHovered(ctx, inside)
end

-- Two-way "segmented" choice, as in the Family mock. Returns the new value.
function M.segmented(ImGui, ctx, id, options, value)
  ImGui.PushID(ctx, id)
  for i, option in ipairs(options) do
    if i > 1 then ImGui.SameLine(ctx, nil, 2) end
    local on = option.value == value
    if on then ImGui.PushStyleColor(ctx, ImGui.Col_Button, M.SELECTED) end
    if ImGui.Button(ctx, option.label) then value = option.value end
    if on then ImGui.PopStyleColor(ctx) end
  end
  ImGui.PopID(ctx)
  return value
end

-- A short description of a colour spec, for the rule list.
function M.describe(spec)
  local mode = spec.mode
  if mode == "fixed" then return colour.to_hex(spec.rgb) end
  if mode == "family" then return spec.palette and "Family (palette)" or "Family" end
  return ({ gradient = "Gradient", random = "Random", parent = "Parent",
            none = "No colour", ignore = "Ignore" })[mode] or mode
end

return M
