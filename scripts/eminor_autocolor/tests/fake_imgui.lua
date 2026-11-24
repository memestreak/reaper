-- tests/fake_imgui.lua
--
-- A strict stand-in for the ReaImGui 0.10 API, so the editor's Lua can be
-- run outside REAPER. It knows only the functions the editor uses, with
-- the argument counts of the real API (read from ReaImGui 0.10.0.2 on
-- inky). Calling anything else, or leaving out a required argument,
-- raises an error: that is what catches mistakes before REAPER does.
--
-- It draws nothing. Widgets return "not clicked" unless a test presses
-- them with fake.press(label); popups open only after OpenPopup.

local M = {}

-- name -> { min args, max args } (counted as Lua sees them through imgui.lua)
local FUNCTIONS = {
  AcceptDragDropPayload = { 2, 3 }, AlignTextToFramePadding = { 1, 1 }, ArrowButton = { 3, 3 },
  Attach = { 2, 2 }, Begin = { 2, 4 }, BeginChild = { 2, 6 }, BeginCombo = { 3, 4 },
  BeginDisabled = { 1, 2 }, BeginDragDropSource = { 1, 2 }, BeginDragDropTarget = { 1, 1 },
  BeginPopup = { 2, 3 }, BeginPopupContextItem = { 1, 3 }, BeginPopupModal = { 2, 4 },
  BeginTable = { 3, 7 }, Button = { 2, 4 }, CalcTextSize = { 2, 4 }, Checkbox = { 3, 3 },
  CloseCurrentPopup = { 1, 1 }, ColorPicker3 = { 3, 4 }, CreateContext = { 1, 2 },
  CreateFont = { 1, 2 }, CreateImage = { 1, 2 },
  DrawList_AddCircleFilled = { 5, 6 }, DrawList_AddQuadFilled = { 10, 10 }, DrawList_AddRect = { 6, 9 }, DrawList_AddRectFilled = { 6, 8 },
  DrawList_AddRectFilledMultiColor = { 9, 9 }, DrawList_AddText = { 5, 5 },
  Dummy = { 3, 3 }, End = { 1, 1 }, EndChild = { 1, 1 }, EndCombo = { 1, 1 }, EndDisabled = { 1, 1 },
  EndDragDropSource = { 1, 1 }, EndDragDropTarget = { 1, 1 }, EndPopup = { 1, 1 }, EndTable = { 1, 1 },
  GetContentRegionAvail = { 1, 1 }, GetCursorPosX = { 1, 1 }, GetCursorScreenPos = { 1, 1 },
  GetFrameHeight = { 1, 1 }, GetFrameHeightWithSpacing = { 1, 1 }, GetStyleVar = { 2, 2 },
  GetWindowDrawList = { 1, 1 }, ImageButton = { 5, 11 }, Image_GetSize = { 1, 1 },
  InputInt = { 3, 6 }, InputText = { 3, 5 }, InputTextWithHint = { 4, 6 }, InvisibleButton = { 4, 5 },
  IsAnyItemActive = { 1, 1 }, IsItemActive = { 1, 1 }, IsItemDeactivatedAfterEdit = { 1, 1 },
  IsItemHovered = { 1, 2 }, IsKeyChordPressed = { 2, 2 }, IsKeyPressed = { 2, 3 },
  IsMouseDoubleClicked = { 2, 2 }, IsPopupOpen = { 2, 3 }, IsRectVisible = { 3, 3 },
  IsWindowAppearing = { 1, 1 }, IsWindowFocused = { 1, 2 }, MenuItem = { 2, 5 }, NewLine = { 1, 1 },
  OpenPopup = { 2, 3 }, PopFont = { 1, 1 }, PopID = { 1, 1 }, PopStyleColor = { 1, 2 },
  PopStyleVar = { 1, 2 }, PopTextWrapPos = { 1, 1 }, PushFont = { 3, 3 }, PushID = { 2, 2 },
  PushStyleColor = { 3, 3 }, PushStyleVar = { 3, 4 }, PushTextWrapPos = { 1, 2 },
  SameLine = { 1, 3 }, Selectable = { 2, 6 }, Separator = { 1, 1 }, SeparatorText = { 2, 2 },
  SetCursorPosX = { 2, 2 }, SetDragDropPayload = { 3, 4 }, SetItemTooltip = { 2, 2 },
  SetNextItemWidth = { 2, 2 }, SetNextWindowSize = { 3, 4 }, SetTooltip = { 2, 2 },
  SliderDouble = { 5, 7 }, SmallButton = { 2, 2 }, Spacing = { 1, 1 }, TableNextColumn = { 1, 1 },
  TableNextRow = { 1, 3 }, TableHeadersRow = { 1, 1 }, SetNextWindowSizeConstraints = { 5, 6 }, TableSetupColumn = { 2, 5 }, Text = { 2, 2 }, TextColored = { 3, 3 },
  TextDisabled = { 2, 2 },
}

-- Constants that exist in ReaImGui 0.10 (the ones the editor uses).
local CONSTANTS = {
  "ChildFlags_AutoResizeY", "ChildFlags_Borders", "Col_Border", "Col_Button", "Col_ButtonActive", "Col_ButtonHovered",
  "Col_CheckMark", "Col_ChildBg", "Col_DragDropTarget", "Col_FrameBg", "Col_FrameBgActive",
  "Col_FrameBgHovered", "Col_Header", "Col_HeaderActive", "Col_HeaderHovered", "Col_NavCursor",
  "Col_PopupBg", "Col_Separator", "Col_SliderGrab", "Col_SliderGrabActive", "Col_TableBorderLight",
  "Col_TableHeaderBg", "Col_TableRowBg", "Col_TableRowBgAlt", "Col_Text", "Col_TextDisabled",
  "Col_TitleBg", "Col_TitleBgActive", "Col_WindowBg", "ColorEditFlags_DisplayHex",
  "ColorEditFlags_DisplayRGB", "ColorEditFlags_NoAlpha", "ColorEditFlags_NoSidePreview",
  "ColorEditFlags_PickerHueBar", "Cond_Always", "Cond_Appearing", "Cond_FirstUseEver", "Dir_Down",
  "FocusedFlags_RootAndChildWindows", "Key_Backspace", "Key_Delete", "Key_DownArrow", "Key_Escape",
  "Key_UpArrow", "Key_Z", "Mod_Alt", "Mod_Ctrl", "Mod_Shift", "MouseButton_Left",
  "PopupFlags_AnyPopup", "SelectableFlags_AllowOverlap", "SelectableFlags_SpanAllColumns",
  "StyleVar_Alpha", "StyleVar_CellPadding", "StyleVar_ChildRounding", "StyleVar_FramePadding", "StyleVar_FrameRounding",
  "StyleVar_GrabRounding", "StyleVar_ItemSpacing", "StyleVar_PopupRounding", "StyleVar_WindowPadding",
  "TableColumnFlags_WidthFixed", "TableColumnFlags_WidthStretch", "TableFlags_PadOuterX",
  "TableFlags_RowBg", "TableFlags_SizingFixedFit", "WindowFlags_NoCollapse", "WindowFlags_NoResize", "WindowFlags_NoSavedSettings",
}

function M.new()
  local fake = { calls = {}, opened = {}, pressed = {}, combos = {}, popup_stack = {}, balance = {} }
  local ImGui = {}

  for i, name in ipairs(CONSTANTS) do ImGui[name] = 1 << (i % 24) end

  local function label_of(args)
    return type(args[2]) == "string" and args[2] or nil
  end

  local function take_press(args)
    local label = label_of(args)
    if label and fake.pressed[label] then
      fake.pressed[label] = nil
      return true
    end
    return false
  end

  local function pair(open_name, close_name)
    fake.balance[open_name] = close_name
  end
  pair("Begin", "End"); pair("BeginChild", "EndChild"); pair("BeginTable", "EndTable")
  pair("BeginPopup", "EndPopup"); pair("BeginPopupModal", "EndPopup"); pair("BeginCombo", "EndCombo")
  pair("BeginPopupContextItem", "EndPopup"); pair("BeginDisabled", "EndDisabled")
  pair("BeginDragDropSource", "EndDragDropSource"); pair("BeginDragDropTarget", "EndDragDropTarget")
  pair("PushID", "PopID"); pair("PushFont", "PopFont"); pair("PushTextWrapPos", "PopTextWrapPos")
  fake.stack, fake.closers = {}, {}
  for _, close_name in pairs(fake.balance) do fake.closers[close_name] = true end

  local behaviour = {
    Begin = function() return true, true end,
    BeginChild = function() return true end,
    BeginTable = function() return true end,
    BeginPopup = function(args)
      if fake.opened[args[2]] then
        fake.popup_stack[#fake.popup_stack + 1] = args[2]
        return true
      end
      return false
    end,
    BeginPopupModal = function(args)
      if fake.opened[args[2]] then
        fake.popup_stack[#fake.popup_stack + 1] = args[2]
        return true, true
      end
      return false, args[3]
    end,
    BeginPopupContextItem = function() return false end,
    BeginDisabled = function() return true end,
    BeginDragDropSource = function() return false end,
    BeginDragDropTarget = function() return false end,
    PushID = function() return true end,
    PushFont = function() return true end,
    PushTextWrapPos = function() return true end,
    BeginCombo = function(args) return fake.combos[args[2]] == true end,
    EndPopup = function() table.remove(fake.popup_stack) end,
    OpenPopup = function(args) fake.opened[args[2]] = true end,
    CloseCurrentPopup = function()
      local top = fake.popup_stack[#fake.popup_stack]
      if top then fake.opened[top] = nil end
    end,
    IsPopupOpen = function(args)
      if args[2] == "" then return next(fake.opened) ~= nil end
      return fake.opened[args[2]] == true
    end,
    Button = take_press, SmallButton = take_press, InvisibleButton = take_press,
    ArrowButton = take_press, ImageButton = take_press,
    Selectable = function(args) local p = take_press(args) return p, p or args[3] end,
    MenuItem = function(args) local p = take_press(args) return p, args[4] end,
    Checkbox = function(args)
      if take_press(args) then return true, not args[3] end
      return false, args[3]
    end,
    InputText = function(args) return false, args[3] end,
    InputTextWithHint = function(args) return false, args[4] end,
    InputInt = function(args) return false, args[3] end,
    SliderDouble = function(args) return false, args[3] end,
    ColorPicker3 = function(args) return false, args[3] end,
    CalcTextSize = function(args) return 7 * #args[2], 13 end,
    GetContentRegionAvail = function() return 600, 400 end,
    GetCursorScreenPos = function() return 10, 10 end,
    GetCursorPosX = function() return 10 end,
    GetFrameHeight = function() return 20 end,
    GetFrameHeightWithSpacing = function() return 26 end,
    GetStyleVar = function() return 4, 3 end,
    GetWindowDrawList = function() return {} end,
    Image_GetSize = function() return 64, 32 end,
    CreateContext = function() return {} end,
    CreateFont = function() return {} end,
    CreateImage = function() return {} end,
    IsRectVisible = function() return true end,
    IsWindowFocused = function() return true end,
    IsWindowAppearing = function() return true end,
    AcceptDragDropPayload = function() return false, "" end,
  }

  for name, counts in pairs(FUNCTIONS) do
    ImGui[name] = function(...)
      local n = select("#", ...)
      local args = { ... }
      -- Trailing nils don't count, as with optional arguments.
      while n > 0 and args[n] == nil do n = n - 1 end
      assert(n >= counts[1] and n <= counts[2], string.format(
          "ImGui.%s takes %d to %d arguments, got %d", name, counts[1], counts[2], n))
      for i = 1, counts[1] do
        assert(args[i] ~= nil, string.format("ImGui.%s: required argument %d is nil", name, i))
      end
      fake.calls[name] = (fake.calls[name] or 0) + 1
      if fake.closers[name] then
        local expected = table.remove(fake.stack)
        assert(expected == name, string.format("ImGui.%s called, but %s was expected",
            name, tostring(expected)))
      end
      local handler = behaviour[name]
      local results = handler and table.pack(handler(args)) or table.pack(nil)
      local closer = fake.balance[name]
      if closer and results[1] then fake.stack[#fake.stack + 1] = closer end
      return table.unpack(results, 1, results.n)
    end
  end

  setmetatable(ImGui, { __index = function(_, key)
    error("ImGui." .. tostring(key) .. " is not in the ReaImGui API the editor was checked against", 2)
  end })

  function fake.press(label) fake.pressed[label] = true end
  fake.ImGui = ImGui
  return fake
end

-- Checks that every Begin/Push call that succeeded was closed, in order.
function M.assert_balanced(fake)
  assert(#fake.stack == 0, "not closed: " .. table.concat(fake.stack, ", "))
end

return M
