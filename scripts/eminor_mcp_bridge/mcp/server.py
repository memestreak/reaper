# /// script
# requires-python = ">=3.10"
# dependencies = ["mcp>=2,<3"]
# ///
"""MCP server for the eminor MCP Bridge.

Lets any MCP client run Lua inside REAPER.
Start it with:  uv run server.py

It talks to REAPER through files in the bridge folder, where the
eminor_mcp_bridge.lua action is polling:

    request.lua            written here, read and deleted by REAPER
    response-<id>.json     written by REAPER, read and deleted here
    running.json           exists while the bridge action is running

Set EMINOR_MCP_BRIDGE_FOLDER to use a folder other than the default
<REAPER resource folder>/Data/eminor_mcp_bridge.
"""

import json
import os
import sys
import threading
import time
import uuid
from pathlib import Path

from mcp.server.mcpserver import MCPServer

RESPONSE_TIMEOUT_SECONDS = 10   # the bridge stops a script after 5
POLL_SECONDS = 0.02

mcp = MCPServer("reaper")

# REAPER answers one request at a time, so only one may be waiting.
_one_at_a_time = threading.Lock()


class BridgeError(Exception):
    """A problem worth showing to the model as the tool's result."""


def bridge_folder() -> Path:
    override = os.environ.get("EMINOR_MCP_BRIDGE_FOLDER")
    if override:
        return Path(override).expanduser()
    home = Path.home()
    if sys.platform == "darwin":
        resources = home / "Library" / "Application Support" / "REAPER"
    elif sys.platform == "win32":
        resources = Path(os.environ.get("APPDATA", home)) / "REAPER"
    else:
        resources = home / ".config" / "REAPER"
    return resources / "Data" / "eminor_mcp_bridge"


def send_request(code: str, undo_label: str | None = None) -> dict:
    """Runs `code` in REAPER and returns the bridge's response."""
    folder = bridge_folder()
    if not (folder / "running.json").exists():
        raise BridgeError(
            "The eminor MCP Bridge is not running. In REAPER, run the action "
            "'Script: eminor_mcp_bridge.lua' and try again."
        )

    request_id = uuid.uuid4().hex[:12]
    header = f"--@id {request_id}\n"
    if undo_label:
        header += f"--@undo {' '.join(undo_label.split())}\n"

    request_path = folder / "request.lua"
    response_path = folder / f"response-{request_id}.json"
    temporary_path = folder / f"request-{request_id}.tmp"

    with _one_at_a_time:
        # Write under another name first, so REAPER never reads half a file.
        temporary_path.write_text(header + code, encoding="utf-8")
        os.replace(temporary_path, request_path)

        deadline = time.monotonic() + RESPONSE_TIMEOUT_SECONDS
        while not response_path.exists():
            if time.monotonic() > deadline:
                picked_up = not request_path.exists()
                request_path.unlink(missing_ok=True)
                if picked_up:
                    raise BridgeError(
                        "REAPER took the request but did not answer in time. "
                        "It may be showing a dialog, or the script is slow."
                    )
                raise BridgeError(
                    "REAPER did not pick up the request. Check that REAPER is "
                    "open and the eminor_mcp_bridge.lua action is still running."
                )
            time.sleep(POLL_SECONDS)

        text = response_path.read_text(encoding="utf-8", errors="replace")
        response_path.unlink(missing_ok=True)
    return json.loads(text)


def as_tool_result(response: dict) -> str:
    """The response as text for the model: the result, or the error."""
    parts = []
    if response.get("ok"):
        parts.append(json.dumps(response.get("result"), indent=2))
    else:
        parts.append("ERROR: " + str(response.get("error")))
    if response.get("output"):
        parts.append("print output:\n" + response["output"])
    return "\n\n".join(parts)


def run(code: str, undo_label: str | None = None) -> str:
    try:
        return as_tool_result(send_request(code, undo_label))
    except BridgeError as problem:
        return "ERROR: " + str(problem)


@mcp.tool()
def reaper_project_summary() -> str:
    """Describes the open REAPER project: tempo, time signature, cursor,
    tracks (number, name, FX, whether it has an instrument, item count),
    markers and regions. Read-only. Call this before changing anything."""
    return run("return bridge.project_summary()")


@mcp.tool()
def reaper_run_lua(code: str, undo_label: str | None = None) -> str:
    """Runs Lua inside REAPER (Lua 5.4, on REAPER's main thread) and
    returns the value the script returns, as JSON, plus anything it printed.

    The full ReaScript API is available as `reaper.*`. Return one value; use
    a table of plain values (not REAPER pointers) to return several.

    undo_label: REQUIRED whenever the script changes the project. The whole
    run becomes one undo point with this label, e.g. "Add chord progression".
    Leave it out only for scripts that just read.

    Limits: a script is stopped after 5 seconds, and nothing runs while
    REAPER is recording. Never start or stop playback or recording, and
    never open dialogs, unless the user asked for exactly that.

    Helpers in the `bridge` table (bars and tracks count from 1; note times
    and lengths are in quarter notes):

    bridge.project_summary()
        The table reaper_project_summary returns.

    bridge.find_track(ref) -> MediaTrack
        ref is a track number or a name (exact match, else a unique partial
        match). Errors list the track names.

    bridge.set_time_signature(numerator, denominator, {bar=1, bpm=nil})
        Sets the time signature from that bar on. Tempo is kept unless bpm
        is given.

    bridge.insert_midi(track_ref, {
        bar = 1,          -- bar the new item starts on
        bars = 4,         -- item length in bars (default: fits the notes)
        name = "Chords",  -- optional item name
        notes = {
          {pitch=61, start=0, length=5, velocity=90, channel=1},
        },
    })
        Creates a new MIDI item and fills it. `start` is quarter notes from
        the item's start. Pitch 60 is middle C (C4 in REAPER's default
        naming). velocity defaults to 96, channel to 1. Returns where the
        item was placed.

    bridge.read_midi(track_ref)
        Every MIDI item on the track, with notes in the same shape.

    Example, one bar of C# major in 5/4:

        bridge.set_time_signature(5, 4)
        return bridge.insert_midi("Piano", {
          bar = 1, bars = 1, name = "C#",
          notes = {
            {pitch = 49, start = 0, length = 5},
            {pitch = 61, start = 0, length = 5},
            {pitch = 65, start = 0, length = 5},
            {pitch = 68, start = 0, length = 5},
          },
        })
    """
    return run(code, undo_label)


if __name__ == "__main__":
    mcp.run()
