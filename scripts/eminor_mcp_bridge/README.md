# eminor MCP Bridge

Lets an AI assistant work inside REAPER: read the project, write MIDI, change the
time signature, and anything else a ReaScript can do.

It has two halves:

- `eminor_mcp_bridge.lua` is a REAPER action. While it runs, it watches a
  folder for a Lua request, runs it, and writes back the result.
- `mcp/server.py` is an MCP server. It gives any MCP client two tools, and
  passes their requests to that folder.

```
MCP client  <-- MCP -->  server.py  <-- files -->  eminor_mcp_bridge.lua  -->  REAPER
```

## Setup

1. In REAPER: Actions > Show action list > New action > Load ReaScript,
   and pick `eminor_mcp_bridge.lua`. Run it. Its toggle state shows that it
   is on. To have it start with REAPER, call it from `__startup.lua` or
   use SWS's startup action.
2. Register the server with your MCP client. It is a standard stdio
   server and needs [uv](https://docs.astral.sh/uv/). The command to
   run is:

   ```
   uv run /path/to/scripts/eminor_mcp_bridge/mcp/server.py
   ```

   Most clients take that as a JSON entry:

   ```json
   {
     "mcpServers": {
       "reaper": {
         "command": "uv",
         "args": ["run", "/path/to/scripts/eminor_mcp_bridge/mcp/server.py"]
       }
     }
   }
   ```

   Some have a command for it, for example Claude Code:

   ```
   claude mcp add --scope user reaper -- uv run /path/to/scripts/eminor_mcp_bridge/mcp/server.py
   ```

Then ask for something, for example: "Set the time signature to 5/4 and
write a four-bar chord progression in C# minor on the Piano track."

## The tools

- `reaper_project_summary` describes the project: tempo, time signature,
  tracks and their FX, markers and regions.
- `reaper_run_lua` runs a Lua script in REAPER and returns what it
  returns. Scripts can use all of `reaper.*`, plus a small `bridge`
  library (`lib/helpers.lua`) for the fiddly jobs: `find_track`,
  `set_time_signature`, `insert_midi`, `read_midi`.

## Toolbar icons

`toolbar_icons/` has three icons for the bridge's toolbar button, each
with normal, hover and on frames:
`eminor_toolbar_mcp_bridge_arch.png`,
`eminor_toolbar_mcp_bridge_spark.png` and
`eminor_toolbar_mcp_bridge_label.png`.
Copy the folder's contents, including `150/` and `200/` for high-DPI
screens, into `<REAPER resource folder>/Data/toolbar_icons/`, then choose
one for the button. The icon turns blue while the bridge is on.

## Staying out of REAPER's way

- Each change is one undo point, named for what it did. Edit > Undo
  takes it back.
- Nothing runs while REAPER is recording.
- A script that runs longer than 5 seconds is stopped.
- When idle, the action costs one folder listing every 100 ms.
- Several MCP clients can use the bridge at once, for example Claude
  Code and the Claude desktop app. Each request gets its own file, and
  REAPER runs them one at a time, oldest first.

## Security

Anything that can write to the bridge folder
(`<REAPER resource folder>/Data/eminor_mcp_bridge/`) can run Lua in REAPER
while the action is on. That is the same access as any program running
as you already has, but turn the action off when you are not using it
if that matters to you.

## Tests

```
lua scripts/eminor_mcp_bridge/tests/run.lua           # the Lua side, with a fake REAPER
uv run scripts/eminor_mcp_bridge/mcp/test_server.py   # server and bridge together (needs lua)
```
