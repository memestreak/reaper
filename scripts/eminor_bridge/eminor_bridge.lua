-- eminor_bridge.lua
--
-- Action: start or stop the eminor Bridge. While it runs, an outside
-- program (the MCP server in mcp/server.py) can ask REAPER to run a piece
-- of Lua by dropping a file into
-- <REAPER resource folder>/Data/eminor_bridge/.
--
-- Running the action again stops it. Its toggle state shows on toolbars.

local here = debug.getinfo(1, "S").source:match("^@?(.*[/\\])")
package.path = here .. "?.lua;" .. package.path

require("lib.loop").run()
