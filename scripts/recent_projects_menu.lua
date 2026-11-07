-- recent_projects_menu.lua
--
-- Pop up REAPER's recent-projects list, centered on the REAPER window, as
-- a short, scrollable table, and open the clicked project in a new tab.
--
-- The list is read from the [Recent] section of reaper.ini, whose entries
-- look like "recent07=/path/to/song.rpp". Each row shows the project file
-- name, its parent folder and when the file was last modified. Projects
-- whose files no longer exist are left out.
--
-- Requirements:
--   * The ReaImGui extension (install it with ReaPack).
--   * macOS: modification times come from the BSD `stat` command.
--
-- Keys: Escape, or clicking anywhere else, closes the list.

local RECENT_SECTION_HEADER = "[Recent]"

-- Rows visible before the list starts scrolling.
local MAX_VISIBLE_ROWS = 12

local DATE_FORMAT = "%Y-%m-%d %H:%M"

local MESSAGE_BOX_OK = 0

-- Native action command IDs (see Reaper's Action List).
local COMMAND_NEW_PROJECT_TAB = 40859  -- File: New project tab

local EXEC_MODE_NORMAL = 0

if not reaper.ImGui_GetBuiltinPath then
  reaper.ShowMessageBox(
      "This script requires the ReaImGui extension. Install it with ReaPack.",
      "ReaImGui not found",
      MESSAGE_BOX_OK)
  return
end

package.path = reaper.ImGui_GetBuiltinPath() .. "/?.lua"
local ImGui = require "imgui" "0.9"

local WINDOW_FLAGS = ImGui.WindowFlags_NoDecoration
                   | ImGui.WindowFlags_AlwaysAutoResize
                   | ImGui.WindowFlags_NoSavedSettings
                   | ImGui.WindowFlags_NoDocking

local TABLE_FLAGS = ImGui.TableFlags_ScrollY
                  | ImGui.TableFlags_RowBg
                  | ImGui.TableFlags_BordersInnerV
                  | ImGui.TableFlags_SizingFixedFit

-- Read the [Recent] section of reaper.ini.
-- returns: array of { n = integer, path = string }, duplicates removed,
-- in file order.
function ReadRecentProjects()
  local recent = {}
  local seen = {}
  local in_recent_section = false

  for line in io.lines(reaper.get_ini_file()) do
    line = line:gsub("\r$", "")  -- Tolerate Windows line endings.

    if line:match("^%[") then
      in_recent_section = (line == RECENT_SECTION_HEADER)
    elseif in_recent_section then
      local n, path = line:match("^recent(%d+)=(.+)$")
      if n and not seen[path] then
        seen[path] = true
        recent[#recent + 1] = { n = tonumber(n), path = path }
      end
    end
  end

  return recent
end

-- Wrap a string in single quotes for the shell.
function ShellQuote(text)
  return "'" .. text:gsub("'", "'\\''") .. "'"
end

-- Look up modification times with a single `stat` call.
-- returns: table mapping path -> Unix time. Files that no longer exist
-- are absent.
function ModificationTimes(paths)
  local quoted = {}
  for i, path in ipairs(paths) do
    quoted[i] = ShellQuote(path)
  end

  -- %m is the modification time in seconds, %N the file name.
  local command = "stat -f '%m %N' -- " .. table.concat(quoted, " ")
                  .. " 2>/dev/null"

  local times = {}
  local pipe = io.popen(command)
  for line in pipe:lines() do
    local seconds, path = line:match("^(%d+) (.+)$")
    if seconds then
      times[path] = tonumber(seconds)
    end
  end
  pipe:close()

  return times
end

-- Split a path into its file name and parent folder name.
-- returns: string file, string folder
function FileAndFolder(path)
  local dir, file = path:match("^(.*)[/\\]([^/\\]+)$")
  local folder = dir and dir:match("([^/\\]+)$") or ""
  return file or path, folder
end

-- Build the table rows, most recent first, skipping missing files.
-- returns: array of { path, file, folder, modified }
function BuildRows(recent)
  -- The highest-numbered entry is the most recent; list it first.
  table.sort(recent, function(a, b) return a.n > b.n end)

  local paths = {}
  for i, project in ipairs(recent) do
    paths[i] = project.path
  end
  local times = ModificationTimes(paths)

  local rows = {}
  for _, path in ipairs(paths) do
    local seconds = times[path]
    if seconds then  -- nil when the file no longer exists.
      local file, folder = FileAndFolder(path)
      rows[#rows + 1] = {
        path = path,
        file = file,
        folder = folder,
        modified = os.date(DATE_FORMAT, seconds),
      }
    end
  end

  return rows
end

-- Width of the widest of the given strings, in pixels.
function MaxTextWidth(ctx, strings)
  local widest = 0
  for _, text in ipairs(strings) do
    widest = math.max(widest, (ImGui.CalcTextSize(ctx, text)))
  end
  return widest
end

-- Draw the projects table.
-- returns: the path of the clicked project, or nil.
function DrawTable(ctx, rows)
  local files, folders, dates = { "Project" }, { "Folder" }, { "Modified" }
  for i, row in ipairs(rows) do
    files[i + 1] = row.file
    folders[i + 1] = row.folder
    dates[i + 1] = row.modified
  end
  local column_widths = {
    MaxTextWidth(ctx, files),
    MaxTextWidth(ctx, folders),
    MaxTextWidth(ctx, dates),
  }

  -- Size the table to fit the columns and MAX_VISIBLE_ROWS rows, plus the
  -- header row.
  local pad_x, pad_y = ImGui.GetStyleVar(ctx, ImGui.StyleVar_CellPadding)
  local scrollbar = ImGui.GetStyleVar(ctx, ImGui.StyleVar_ScrollbarSize)
  local width = scrollbar
  for _, column_width in ipairs(column_widths) do
    width = width + column_width + 2 * pad_x + 1  -- 1 == border
  end
  local row_height = ImGui.GetTextLineHeight(ctx) + 2 * pad_y
  local visible_rows = math.min(#rows, MAX_VISIBLE_ROWS) + 1
  local height = visible_rows * row_height

  local clicked_path = nil

  if ImGui.BeginTable(ctx, "projects", 3, TABLE_FLAGS, width, height) then
    ImGui.TableSetupScrollFreeze(ctx, 0, 1)  -- Keep the header visible.
    ImGui.TableSetupColumn(ctx, "Project", ImGui.TableColumnFlags_WidthFixed,
                           column_widths[1])
    ImGui.TableSetupColumn(ctx, "Folder", ImGui.TableColumnFlags_WidthFixed,
                           column_widths[2])
    ImGui.TableSetupColumn(ctx, "Modified", ImGui.TableColumnFlags_WidthFixed,
                           column_widths[3])
    ImGui.TableHeadersRow(ctx)

    for i, row in ipairs(rows) do
      ImGui.TableNextRow(ctx)

      ImGui.TableNextColumn(ctx)
      -- "##<i>" gives each row a unique ID without changing its label.
      if ImGui.Selectable(ctx, row.file .. "##" .. i, false,
                          ImGui.SelectableFlags_SpanAllColumns) then
        clicked_path = row.path
      end
      ImGui.TableNextColumn(ctx)
      ImGui.Text(ctx, row.folder)
      ImGui.TableNextColumn(ctx)
      ImGui.Text(ctx, row.modified)
    end

    ImGui.EndTable(ctx)
  end

  return clicked_path
end

local recent = ReadRecentProjects()
if #recent == 0 then
  return
end

local rows = BuildRows(recent)
if #rows == 0 then
  return
end

local ctx = ImGui.CreateContext("Recent Projects")

-- SetNextWindowPos pivot: (0.5, 0.5) places the window's center, rather
-- than its top-left corner, at the given position.
local PIVOT_CENTER = 0.5

local is_first_frame = true
local has_had_focus = false

-- Open the project in a new tab, then let the script end.
function OpenProjectInNewTab(path)
  reaper.Main_OnCommand(COMMAND_NEW_PROJECT_TAB, EXEC_MODE_NORMAL)
  reaper.Main_openProject(path)
end

-- Close the dialog first, then open the project.
--
-- ReaImGui removes a context's windows at the end of the first defer cycle
-- in which the context isn't used. Opening the project in the same cycle
-- that drew the click leaves the dialog on screen while the project loads,
-- so wait out one cycle without touching the context, then open it.
function CloseDialogThenOpen(path)
  reaper.defer(function()     -- Cycle where the context goes unused.
    reaper.defer(function()   -- The dialog is gone by now.
      OpenProjectInNewTab(path)
    end)
  end)
end

function Loop()
  -- In ReaImGui the main viewport is REAPER's main window. Re-center every
  -- frame, since the window's size isn't known until it has been drawn.
  local center_x, center_y =
      ImGui.Viewport_GetCenter(ImGui.GetMainViewport(ctx))
  ImGui.SetNextWindowPos(ctx, center_x, center_y, ImGui.Cond_Always,
                         PIVOT_CENTER, PIVOT_CENTER)

  if is_first_frame then
    ImGui.SetNextWindowFocus(ctx)
    is_first_frame = false
  end

  local keep_open = true
  local clicked_path = nil

  local visible = ImGui.Begin(ctx, "Recent Projects", nil, WINDOW_FLAGS)
  if visible then
    clicked_path = DrawTable(ctx, rows)

    -- Behave like a menu: close on Escape or when focus moves elsewhere.
    local is_focused = ImGui.IsWindowFocused(
        ctx, ImGui.FocusedFlags_RootAndChildWindows)
    if is_focused then
      has_had_focus = true
    end
    if ImGui.IsKeyPressed(ctx, ImGui.Key_Escape)
        or (has_had_focus and not is_focused) then
      keep_open = false
    end

    ImGui.End(ctx)
  end

  if clicked_path then
    CloseDialogThenOpen(clicked_path)
  elseif keep_open then
    reaper.defer(Loop)
  end
end

reaper.defer(Loop)
