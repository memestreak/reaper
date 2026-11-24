-- lib/loop.lua
--
-- The bridge's background loop. A few times a second it looks for
-- request.lua in the bridge folder, runs it, and writes the answer to
-- response-<id>.json.
--
-- Cost when idle: one failed file open per poll. Nothing runs while
-- REAPER is recording (see runner.lua).

local runner = require("lib.runner")
local helpers = require("lib.helpers")
local json = require("lib.json")

local M = {}

M.VERSION = 1

local POLL_SECONDS = 0.1

-- set_action_options flags (REAPER 7.03+)
local OPTION_TERMINATE_ON_RELAUNCH = 1
local OPTION_TOGGLE_ON = 4
local OPTION_TOGGLE_OFF = 8

local function write_file(path, text)
  local file = assert(io.open(path, "wb"))
  file:write(text)
  file:close()
end

-- Writes to a temporary name first, so a reader never sees half a file.
local function write_file_whole(path, text)
  write_file(path .. ".tmp", text)
  os.remove(path)  -- Windows will not rename over an existing file
  assert(os.rename(path .. ".tmp", path))
end

-- Looks for a request in `folder` and answers it. Returns true if one
-- was found. `r` is the reaper API table.
function M.poll_once(folder, r)
  local request_path = folder .. "request.lua"
  local file = io.open(request_path, "rb")
  if not file then return false end
  local text = file:read("a")
  file:close()
  os.remove(request_path)

  local request = runner.parse(text)
  local response = runner.run(request, r, helpers.new(r))
  local ok, encoded = pcall(json.encode, response)
  if not ok then
    encoded = json.encode({
      id = request.id, ok = false,
      error = "The script's result could not be sent back: " .. tostring(encoded),
    })
  end
  write_file_whole(folder .. "response-" .. request.id .. ".json", encoded)
  return true
end

function M.folder()
  local sep = package.config:sub(1, 1)
  return reaper.GetResourcePath() .. sep .. "Data" .. sep .. "eminor_bridge" .. sep
end

function M.run()
  if not reaper.set_action_options then
    reaper.MB("eminor Bridge needs REAPER 7.03 or newer.", "eminor Bridge", 0)
    return
  end
  reaper.set_action_options(OPTION_TERMINATE_ON_RELAUNCH | OPTION_TOGGLE_ON)

  local folder = M.folder()
  reaper.RecursiveCreateDirectory(folder, 0)

  -- running.json tells the MCP server that the bridge is up.
  local running_path = folder .. "running.json"
  write_file_whole(running_path, json.encode({
    version = M.VERSION,
    reaper_version = reaper.GetAppVersion(),
  }))
  reaper.atexit(function()
    os.remove(running_path)
    reaper.set_action_options(OPTION_TOGGLE_OFF)
  end)

  local next_poll = 0
  local function tick()
    local now = reaper.time_precise()
    if now >= next_poll then
      next_poll = now + POLL_SECONDS
      local ok, problem = pcall(M.poll_once, folder, reaper)
      if not ok then
        reaper.ShowConsoleMsg("eminor Bridge: " .. tostring(problem) .. "\n")
      end
    end
    reaper.defer(tick)
  end
  tick()
end

return M
