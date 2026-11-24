-- ui/colour_popover.lua
--
-- What opens when you click a rule's swatch: the colour mode, then saved
-- palettes first with "Custom colour…" for the full picker (the mock Jeremy
-- picked). Family colours get a Range / Palette toggle, hue and lightness
-- sliders and a preview strip.
--
-- Discrete choices (a palette click, a mode) are saved at once. Sliders and
-- the picker are saved when you let go, so dragging doesn't write the rules
-- file on every frame.

local colour = require("lib.colour")
local W = require("ui.widgets")

local M = {}

local MODES = {
  { mode = "fixed",    label = "Fixed colour" },
  { mode = "family",   label = "Family (similar shades)" },
  { mode = "gradient", label = "Gradient" },
  { mode = "random",   label = "Random" },
  { mode = "parent",   label = "Parent's colour", tracks_only = true },
  { mode = "none",     label = "No colour (clears it)" },
  { mode = "ignore",   label = "Ignore (leave colour alone)" },
}

local HELP = {
  random = "Each item gets its own colour, picked from its GUID, so it stays the same.",
  parent = "Tracks take their folder's colour.",
  none = "Matching items have their colour cleared.",
  ignore = "This rule leaves colour alone, so a rule below it can set it. Use it for icon or layout rules.",
}

local CELL = 20
local PER_ROW = 8
local PREVIEW_COUNT = 8
-- Popups size themselves to their contents, so widths here are fixed
-- rather than "fill the space", which would collapse to nothing.
local CONTENT_W = PER_ROW * (CELL + 4) - 4 + 90
local FIELD_W = CONTENT_W - 90

local function copy(t)
  if type(t) ~= "table" then return t end
  local c = {}
  for k, v in pairs(t) do c[k] = copy(v) end
  return c
end

local function base_of(spec)
  return spec.rgb or spec.base or spec.from or (spec.palette and spec.palette[1]) or 0x4080C2
end

-- A fresh spec for `mode`, keeping the current colour where it makes sense.
local function spec_for_mode(mode, old)
  local base = base_of(old)
  if mode == "fixed" then return { mode = mode, rgb = base } end
  if mode == "family" then return { mode = mode, base = base, hue = 8, light = 0.12 } end
  if mode == "gradient" then
    return { mode = mode, from = old.from or base, to = old.to or 0x8FC1E8 }
  end
  return { mode = mode }
end

-- Settings a rule had before a switch, so switching back restores them
-- (Range -> Palette -> Range keeps the base colour, and so on).
-- rule id -> { variant -> spec }. Kept while the editor is open.
local remembered = {}

-- Remembers `old` and returns the remembered spec for `variant`, or
-- `fresh()` if there is none. Variants are the modes, plus "family_range"
-- and "family_palette" for the two kinds of family ("family" is whichever
-- was used last).
local function switch_spec(rule_id, old, variant, fresh)
  local mine = remembered[rule_id] or {}
  remembered[rule_id] = mine
  mine[old.mode] = copy(old)
  if old.mode == "family" then
    mine[old.palette and "family_palette" or "family_range"] = copy(old)
  end
  return copy(mine[variant]) or fresh()
end

-- One row of colour cells. Returns the clicked colour, or nil.
local function palette_row(ImGui, ctx, id, colours, picked)
  local clicked
  for i, rgb in ipairs(colours) do
    if (i - 1) % PER_ROW ~= 0 then ImGui.SameLine(ctx, nil, 4) end
    if W.colour_cell(ImGui, ctx, id .. i, rgb, CELL, rgb == picked) then clicked = rgb end
  end
  return clicked
end

-- The hex field. Returns a parsed colour once you finish typing, or nil.
local function hex_field(ImGui, ctx, state, key, rgb)
  ImGui.SetNextItemWidth(ctx, 80)
  local buffer = state.hex and state.hex[key] or colour.to_hex(rgb)
  local _, text = ImGui.InputText(ctx, "##hex" .. key, buffer)
  state.hex = state.hex or {}
  state.hex[key] = ImGui.IsItemActive(ctx) and text or nil
  if ImGui.IsItemDeactivatedAfterEdit(ctx) then
    local clean = text:gsub("%s", "")
    if not clean:find("^#") then clean = "#" .. clean end
    return colour.parse_hex(clean:upper())
  end
end

-- The full picker for one colour field. Returns (value, finished).
local function picker(ImGui, ctx, key, rgb)
  local flags = ImGui.ColorEditFlags_NoSidePreview | ImGui.ColorEditFlags_NoAlpha
      | ImGui.ColorEditFlags_PickerHueBar | ImGui.ColorEditFlags_DisplayRGB
  ImGui.SetNextItemWidth(ctx, 220)
  local _, value = ImGui.ColorPicker3(ctx, "##picker" .. key, rgb, flags)
  return value, ImGui.IsItemDeactivatedAfterEdit(ctx)
end

-- A colour field: swatch, hex, and a "Custom colour…" picker under it.
-- `apply(rgb, finished)` receives every change.
local function colour_field(ImGui, ctx, state, key, label, rgb, apply)
  ImGui.AlignTextToFramePadding(ctx)
  ImGui.Text(ctx, label)
  ImGui.SameLine(ctx, 90)
  if W.colour_cell(ImGui, ctx, "##sw" .. key, rgb, ImGui.GetFrameHeight(ctx), false) then
    state.picker = state.picker ~= key and key or nil
  end
  ImGui.SameLine(ctx)
  local typed = hex_field(ImGui, ctx, state, key, rgb)
  if typed then apply(typed, true) end
  if state.picker == key then
    local value, finished = picker(ImGui, ctx, key, rgb)
    if value ~= rgb or finished then apply(value, finished) end
  end
end

local function palette_sources(palettes, in_use, recent)
  local rows = {}
  if #in_use > 0 then rows[#rows + 1] = { name = "In use", colours = in_use } end
  for _, palette in ipairs(palettes) do rows[#rows + 1] = palette end
  if #recent > 0 then rows[#rows + 1] = { name = "Recent", colours = recent } end
  return rows
end

local function draw_fixed(ImGui, ctx, state, work, sources, change)
  for i, source in ipairs(sources) do
    ImGui.TextDisabled(ctx, source.name)
    local clicked = palette_row(ImGui, ctx, "##pal" .. i .. "_", source.colours, work.rgb)
    if clicked then
      work.rgb = clicked
      change(work, true, clicked)
    end
  end
  if #sources == 0 then
    ImGui.TextDisabled(ctx, "No palettes yet. Pick a custom colour, or make a palette with Edit palettes.")
  end
  ImGui.Spacing(ctx)
  if ImGui.Button(ctx, state.picker == "rgb" and "Hide custom colour" or "Custom colour…") then
    state.picker = state.picker ~= "rgb" and "rgb" or nil
  end
  ImGui.SameLine(ctx)
  local typed = hex_field(ImGui, ctx, state, "rgb", work.rgb)
  if typed then
    work.rgb = typed
    change(work, true, typed)
  end
  if state.picker == "rgb" then
    local value, finished = picker(ImGui, ctx, "rgb", work.rgb)
    if value ~= work.rgb or finished then
      work.rgb = value
      change(work, finished, finished and value or nil)
    end
  end
end

local function draw_family(ImGui, ctx, state, work, palettes, in_use, change, rule_id)
  local kind = work.palette and "palette" or "range"
  local new_kind = W.segmented(ImGui, ctx, "kind", {
    { label = "Range", value = "range" }, { label = "Palette", value = "palette" } }, kind)
  if new_kind ~= kind then
    local spec = switch_spec(rule_id, work, "family_" .. new_kind, function()
      if new_kind == "palette" then
        local first = palettes[1]
        return { mode = "family",
                 palette = copy(first and first.colours or (#in_use > 0 and in_use) or { base_of(work) }) }
      end
      return { mode = "family", base = base_of(work), hue = 8, light = 0.12 }
    end)
    change(spec, true)
    return
  end

  if kind == "range" then
    colour_field(ImGui, ctx, state, "base", "Base", work.base, function(rgb, finished)
      work.base = rgb
      change(work, finished, finished and rgb or nil)
    end)
    ImGui.AlignTextToFramePadding(ctx)
    ImGui.Text(ctx, "Hue drift")
    ImGui.SameLine(ctx, 90)
    ImGui.SetNextItemWidth(ctx, FIELD_W)
    local _, hue = ImGui.SliderDouble(ctx, "##hue", work.hue, 0, 45, "±%.0f°")
    if hue ~= work.hue then work.hue = hue; change(work, false) end
    if ImGui.IsItemDeactivatedAfterEdit(ctx) then change(work, true) end

    ImGui.AlignTextToFramePadding(ctx)
    ImGui.Text(ctx, "Lightness")
    ImGui.SameLine(ctx, 90)
    ImGui.SetNextItemWidth(ctx, FIELD_W)
    local _, light = ImGui.SliderDouble(ctx, "##light", work.light * 100, 0, 50, "±%.0f%%")
    if light / 100 ~= work.light then work.light = light / 100; change(work, false) end
    if ImGui.IsItemDeactivatedAfterEdit(ctx) then change(work, true) end
  else
    ImGui.TextDisabled(ctx, "Matches use these colours in turn:")
    palette_row(ImGui, ctx, "##cur", work.palette, nil)
    ImGui.Spacing(ctx)
    ImGui.TextDisabled(ctx, "Use a saved palette:")
    local choices = {}
    if #in_use > 0 then choices[#choices + 1] = { name = "Colours in use", colours = in_use } end
    for _, p in ipairs(palettes) do choices[#choices + 1] = p end
    for i, choice in ipairs(choices) do
      if ImGui.Selectable(ctx, choice.name .. "##choice" .. i, false) then
        work.palette = copy(choice.colours)
        change(work, true)
      end
    end
  end

  ImGui.Spacing(ctx)
  ImGui.TextDisabled(ctx, "Preview, in timeline or track order")
  local x, y = ImGui.GetCursorScreenPos(ctx)
  local w = CONTENT_W
  local dl = ImGui.GetWindowDrawList(ctx)
  local samples = W.sample_colours(work, PREVIEW_COUNT)
  local cell = w / #samples
  for i, rgb in ipairs(samples) do
    ImGui.DrawList_AddRectFilled(dl, x + (i - 1) * cell + 1, y, x + i * cell - 1, y + 24, W.rgba(rgb), 3)
  end
  ImGui.Dummy(ctx, w, 24)
  ImGui.TextDisabled(ctx, "New matches keep earlier colours. Force spreads them again.")
end

local function draw_gradient(ImGui, ctx, state, work, change)
  colour_field(ImGui, ctx, state, "from", "From", work.from, function(rgb, finished)
    work.from = rgb
    change(work, finished, finished and rgb or nil)
  end)
  colour_field(ImGui, ctx, state, "to", "To", work.to, function(rgb, finished)
    work.to = rgb
    change(work, finished, finished and rgb or nil)
  end)
  ImGui.TextDisabled(ctx, "Matches are spread evenly from the first colour to the second.")
end

-- Draws the popover body for `rule` (call between BeginPopup/EndPopup).
--   state     a table kept while this popover is open
--   context   { palettes, in_use, recent, set_colour(spec, label, used_rgb),
--               edit_palettes() }
function M.draw(ImGui, ctx, rule, state, context)
  local work = state.work or copy(rule.colour)

  -- `finished` false: still dragging; keep the working copy and save later.
  local function change(spec, finished, used_rgb)
    if finished then
      state.work = nil
      context.set_colour(copy(spec), "Change colour", used_rgb)
    else
      state.work = spec
    end
  end

  ImGui.AlignTextToFramePadding(ctx)
  ImGui.Text(ctx, "Mode")
  ImGui.SameLine(ctx, 90)
  ImGui.SetNextItemWidth(ctx, FIELD_W)
  local current_label = work.mode
  for _, m in ipairs(MODES) do if m.mode == work.mode then current_label = m.label end end
  if ImGui.BeginCombo(ctx, "##mode", current_label) then
    for _, m in ipairs(MODES) do
      if not m.tracks_only or rule.target == "track" then
        if ImGui.Selectable(ctx, m.label, m.mode == work.mode) and m.mode ~= work.mode then
          state.picker = nil
          local fresh = function() return spec_for_mode(m.mode, work) end
          change(switch_spec(rule.id, work, m.mode, fresh), true)
        end
      end
    end
    ImGui.EndCombo(ctx)
  end
  ImGui.Separator(ctx)

  local sources = palette_sources(context.palettes, context.in_use, context.recent)
  if work.mode == "fixed" then
    draw_fixed(ImGui, ctx, state, work, sources, change)
  elseif work.mode == "family" then
    draw_family(ImGui, ctx, state, work, context.palettes, context.in_use, change, rule.id)
  elseif work.mode == "gradient" then
    draw_gradient(ImGui, ctx, state, work, change)
  else
    ImGui.PushTextWrapPos(ctx, ImGui.GetCursorPosX(ctx) + CONTENT_W)
    ImGui.TextDisabled(ctx, HELP[work.mode] or "")
    ImGui.PopTextWrapPos(ctx)
  end

  ImGui.Separator(ctx)
  if ImGui.SmallButton(ctx, "Edit palettes…") then
    ImGui.CloseCurrentPopup(ctx)
    context.edit_palettes()
  end
end

return M
