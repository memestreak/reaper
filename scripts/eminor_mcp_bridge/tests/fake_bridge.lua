-- tests/fake_bridge.lua
--
-- Runs the bridge's polling against the fake REAPER, for testing the MCP
-- server without REAPER (see mcp/test_server.py):
--   lua scripts/eminor_mcp_bridge/tests/fake_bridge.lua <folder>
-- Polls <folder> until a file named "stop" appears there.

local here = debug.getinfo(1, "S").source:match("^@?(.*[/\\])") or "./"
package.path = here .. "../?.lua;" .. here .. "?.lua;" .. package.path

local loop = require("lib.loop")
local fake_reaper = require("fake_reaper")

local folder = assert(arg[1], "give the bridge folder") .. "/"
local r = fake_reaper.new({ "Drums", "Piano" })
r.time_precise = os.clock

local function exists(path)
  local file = io.open(path, "rb")
  if file then file:close() end
  return file ~= nil
end

while not exists(folder .. "stop") do
  loop.poll_once(folder, r)
end
