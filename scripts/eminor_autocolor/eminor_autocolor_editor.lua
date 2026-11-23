-- eminor_autocolor_editor.lua
--
-- Action: open the eminor Auto Color rule editor (run again to close it).
-- Needs the ReaImGui extension (0.10 or newer), from ReaPack. The engine
-- doesn't need it: colouring keeps working without the editor.

local here = debug.getinfo(1, "S").source:match("^@?(.*[/\\])")
package.path = here .. "?.lua;" .. package.path

local TITLE = "eminor Auto Color"
local REAIMGUI_VERSION = "0.10"
local MB_YESNO, MB_RESULT_YES = 4, 6

-- set_action_options flags (REAPER 7.03+)
local OPTION_TERMINATE_ON_RELAUNCH = 1
local OPTION_TOGGLE_ON = 4
local OPTION_TOGGLE_OFF = 8

local function offer_reaimgui(problem)
  local answer = reaper.MB(problem .. "\n\nOpen ReaPack to install or update ReaImGui?", TITLE, MB_YESNO)
  if answer ~= MB_RESULT_YES then return end
  if reaper.ReaPack_BrowsePackages then
    reaper.ReaPack_BrowsePackages("ReaImGui")
  else
    reaper.MB("ReaPack isn't installed either. Get it from https://reapack.com, "
        .. "then install ReaImGui from Extensions › ReaPack › Browse packages.", TITLE, 0)
  end
end

if not reaper.ImGui_GetBuiltinPath then
  offer_reaimgui("The eminor Auto Color editor needs the ReaImGui extension.")
  return
end

package.path = reaper.ImGui_GetBuiltinPath() .. "/?.lua;" .. package.path
local ok, ImGui = pcall(function() return require("imgui")(REAIMGUI_VERSION) end)
if not ok then
  offer_reaimgui("The eminor Auto Color editor needs ReaImGui " .. REAIMGUI_VERSION
      .. " or newer.\n(" .. tostring(ImGui) .. ")")
  return
end

if reaper.set_action_options then
  reaper.set_action_options(OPTION_TERMINATE_ON_RELAUNCH | OPTION_TOGGLE_ON)
  reaper.atexit(function() reaper.set_action_options(OPTION_TOGGLE_OFF) end)
end

require("ui.editor").run(ImGui)
