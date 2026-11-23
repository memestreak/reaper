-- ui/icons.lua
--
-- Track icon thumbnails and the icon browser: a grid over
-- <resource>/Data/track_icons and its subfolders (songs/ included), with a
-- search box and a "No icon" button.
--
-- Images load lazily: only when on screen, and only a few per frame, so
-- opening the browser on a big folder never stalls REAPER's UI.

local M = {}

local LOADS_PER_FRAME = 6
local EXTENSIONS = { png = true, jpg = true, jpeg = true, gif = true, bmp = true, ico = true }
local GRID_CELL = 44

local sep = package.config:sub(1, 1)

local cache = {}          -- full path -> image, or false if it failed to load
local loads_this_frame = 0
local files = nil         -- relative paths, sorted; nil until scanned

function M.folder()
  return reaper.GetResourcePath() .. sep .. "Data" .. sep .. "track_icons"
end

-- Rule icons are relative to the icon folder (with "/" between folders),
-- or absolute.
function M.full_path(name)
  if name:sub(1, 1) == "/" or name:match("^%a:") then return name end
  return M.folder() .. sep .. name:gsub("/", sep)
end

function M.new_frame()
  loads_this_frame = 0
end

-- The image for an icon, or nil while it isn't loaded (or can't be).
function M.image(ImGui, ctx, name)
  local path = M.full_path(name)
  local image = cache[path]
  if image == nil then
    if loads_this_frame >= LOADS_PER_FRAME then return nil end
    loads_this_frame = loads_this_frame + 1
    local ok, created = pcall(ImGui.CreateImage, path)
    if ok and created then
      ImGui.Attach(ctx, created)  -- keeps it alive between frames
      image = created
    else
      image = false
    end
    cache[path] = image
  end
  return image or nil
end

-- Draws a thumbnail (or an empty dashed box). Returns true when clicked.
function M.thumbnail(ImGui, ctx, id, name, size)
  if name ~= "" and ImGui.IsRectVisible(ctx, size, size) then
    local image = M.image(ImGui, ctx, name)
    if image then
      -- Crop to a centred square so artwork that isn't square keeps its shape.
      local w, h = ImGui.Image_GetSize(image)
      local u0, v0, u1, v1 = 0, 0, 1, 1
      if w > h then
        local margin = (1 - h / w) / 2
        u0, u1 = margin, 1 - margin
      elseif h > w then
        local margin = (1 - w / h) / 2
        v0, v1 = margin, 1 - margin
      end
      return ImGui.ImageButton(ctx, id, image, size, size, u0, v0, u1, v1)
    end
  end
  -- Same outer size as an ImageButton, so rows and the grid line up.
  local pad_x, pad_y = ImGui.GetStyleVar(ctx, ImGui.StyleVar_FramePadding)
  local x, y = ImGui.GetCursorScreenPos(ctx)
  local clicked = ImGui.InvisibleButton(ctx, id, size + 2 * pad_x, size + 2 * pad_y)
  local dl = ImGui.GetWindowDrawList(ctx)
  local hovered = ImGui.IsItemHovered(ctx)
  ImGui.DrawList_AddRect(dl, x + pad_x, y + pad_y, x + pad_x + size, y + pad_y + size,
      hovered and 0xAAAAAAFF or 0x555555FF, 4)
  if name ~= "" then
    ImGui.DrawList_AddText(dl, x + pad_x + 3, y + pad_y, 0x9C9C9CFF, "…")
  end
  return clicked
end

local function scan(folder, prefix, out)
  local i = 0
  while true do
    local file = reaper.EnumerateFiles(folder, i)
    if not file then break end
    local ext = file:match("%.([^.]+)$")
    if ext and EXTENSIONS[ext:lower()] then out[#out + 1] = prefix .. file end
    i = i + 1
  end
  i = 0
  while true do
    local sub = reaper.EnumerateSubdirectories(folder, i)
    if not sub then break end
    scan(folder .. sep .. sub, prefix .. sub .. "/", out)
    i = i + 1
  end
end

function M.files(refresh)
  if refresh or not files then
    files = {}
    reaper.EnumerateFiles(M.folder(), -1)  -- clears REAPER's directory cache
    scan(M.folder(), "", files)
    table.sort(files, function(a, b) return a:lower() < b:lower() end)
  end
  return files
end

-- The browser body (call between BeginPopup/EndPopup).
-- `state` keeps the search text. Returns the chosen icon name, "" for
-- "No icon", or nil.
function M.browser(ImGui, ctx, state, current)
  local chosen
  ImGui.SetNextItemWidth(ctx, 200)
  local _, search = ImGui.InputTextWithHint(ctx, "##search", "Search icons", state.search or "")
  state.search = search
  ImGui.SameLine(ctx)
  if ImGui.Button(ctx, "No icon") then chosen = "" end
  ImGui.SameLine(ctx)
  local refresh = ImGui.Button(ctx, "Rescan")

  local list = M.files(refresh)
  local needle = search:lower()
  if ImGui.BeginChild(ctx, "##grid", 420, 300, ImGui.ChildFlags_Borders) then
    local avail = ImGui.GetContentRegionAvail(ctx)
    local per_row = math.max(1, math.floor(avail / (GRID_CELL + 8)))
    local shown = 0
    for _, name in ipairs(list) do
      if needle == "" or name:lower():find(needle, 1, true) then
        if shown % per_row ~= 0 then ImGui.SameLine(ctx) end
        shown = shown + 1
        if name == current then
          ImGui.PushStyleColor(ctx, ImGui.Col_Button, 0x0080B8FF)
        end
        if M.thumbnail(ImGui, ctx, "##icon_" .. name, name, GRID_CELL) then chosen = name end
        if name == current then ImGui.PopStyleColor(ctx) end
        if ImGui.IsItemHovered(ctx) then ImGui.SetTooltip(ctx, name) end
      end
    end
    if shown == 0 then
      ImGui.TextDisabled(ctx, #list == 0 and ("No icons in " .. M.folder()) or "No icons match.")
    end
    ImGui.EndChild(ctx)
  end
  return chosen
end

return M
