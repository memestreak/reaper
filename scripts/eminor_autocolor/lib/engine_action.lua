-- lib/engine_action.lua
--
-- The engine's action, so the editor can start the engine and Settings ›
-- Startup can name it, without anyone loading the engine script by hand.
-- The engine action is found, in order:
--   1. by the command ID the engine saved when it last ran,
--   2. in reaper-kb.ini (the Action List), if it was loaded by hand,
--   3. otherwise by adding eminor_autocolor_engine.lua to the Action List.

local settings = require("lib.settings")
local startup = require("lib.startup")

local M = {}

local MAIN_SECTION = 0

-- The engine script, which sits one folder up from this file.
function M.script_path()
  local here = debug.getinfo(1, "S").source:match("^@?(.*[/\\])") or ""
  local folder = here:gsub("lib[/\\]$", "")
  return folder .. "eminor_autocolor_engine.lua"
end

local function lookup(named)
  if not named or named == "" then return nil end
  local id = reaper.NamedCommandLookup("_" .. named)
  if id == 0 then return nil end
  return id
end

-- The engine action's numeric command ID, adding it to the Action List if
-- it isn't there yet. Returns nil if REAPER wouldn't add it.
function M.command_id()
  local id = settings.toggle_command(settings.ENGINE) or lookup(startup.find_engine_command())
  if id then return id end
  id = reaper.AddRemoveReaScript(true, MAIN_SECTION, M.script_path(), true)
  if not id or id == 0 then return nil end
  settings.remember_toggle_command(settings.ENGINE, id)
  return id
end

-- The engine action's named ID ("RS..."), as __startup.lua needs it.
function M.named_command()
  local id = M.command_id()
  if not id then return nil end
  local named = reaper.ReverseNamedCommandLookup(id)
  return named and (named:gsub("^_", "")) or nil
end

function M.is_running()
  return reaper.GetExtState(settings.SECTION, "engine_running") == "1"
end

-- Starts the engine unless it is running. Returns true, or false and a message.
function M.start()
  if M.is_running() then return true end
  local id = M.command_id()
  if not id then
    return false, "Couldn't add the engine (" .. M.script_path() .. ") to the Action List."
  end
  reaper.Main_OnCommand(id, 0)
  return true
end

return M
