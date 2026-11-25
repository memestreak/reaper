# /// script
# requires-python = ">=3.10"
# dependencies = ["mcp>=2,<3"]
# ///
"""MCP server for the eminor MCP Bridge.

Lets any MCP client run Lua inside REAPER.
Start it with:  uv run server.py

It talks to REAPER through files in the bridge folder, where the
eminor_mcp_bridge.lua action is polling:

    request-<time>-<id>.lua  written here, read and deleted by REAPER
    response-<id>.json       written by REAPER, read and deleted here
    running.json             exists while the bridge action is running

Every request gets its own file, and REAPER answers them oldest first, so
several clients (or several calls from one client) can share the bridge.

Set EMINOR_MCP_BRIDGE_FOLDER to use a folder other than the default
<REAPER resource folder>/Data/eminor_mcp_bridge.
"""

import json
import os
import sys
import time
import uuid
from pathlib import Path

from mcp.server.mcpserver import MCPServer

# Waiting in the queue, behind other clients' scripts (5 seconds at most
# each), before REAPER takes the request.
PICKUP_TIMEOUT_SECONDS = 15
# After pickup. The bridge stops a script after 5.
RESPONSE_TIMEOUT_SECONDS = 10
POLL_SECONDS = 0.02
BRIDGE_VERSION = 2   # lib/loop.lua's M.VERSION this server speaks to

mcp = MCPServer("reaper")


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


def check_running(folder: Path) -> None:
    """Raises BridgeError unless a bridge this server can talk to is up.

    Args:
        folder: The bridge folder.

    Raises:
        BridgeError: If the bridge is not running, or is an older version.
    """
    try:
        running = json.loads((folder / "running.json").read_text())
    except FileNotFoundError:
        raise BridgeError(
            "The eminor MCP Bridge is not running. In REAPER, run the action "
            "'Script: eminor_mcp_bridge.lua' and try again."
        ) from None
    except json.JSONDecodeError:
        running = {}   # caught mid-write; the version check below decides
    if running and running.get("version", 1) < BRIDGE_VERSION:
        raise BridgeError(
            "The eminor MCP Bridge running in REAPER is an older version. "
            "Run the action 'Script: eminor_mcp_bridge.lua' twice (off, then "
            "on) to load the new one, and try again."
        )


def wait_for_response(request_path: Path, response_path: Path) -> str:
    """Waits for REAPER to take the request and answer it.

    Args:
        request_path: The request file, which REAPER deletes on pickup.
        response_path: The response file REAPER writes.

    Returns:
        The response file's text.

    Raises:
        BridgeError: If REAPER does not pick up or answer in time.
    """
    picked_up = False
    deadline = time.monotonic() + PICKUP_TIMEOUT_SECONDS
    while not response_path.exists():
        if not picked_up and not request_path.exists():
            picked_up = True
            deadline = time.monotonic() + RESPONSE_TIMEOUT_SECONDS
        if time.monotonic() > deadline:
            if picked_up:
                raise BridgeError(
                    "REAPER took the request but did not answer in time. "
                    "It may be showing a dialog, or the script is slow."
                )
            try:
                request_path.unlink()
            except FileNotFoundError:
                # Taken just now: give it the full time to answer.
                picked_up = True
                deadline = time.monotonic() + RESPONSE_TIMEOUT_SECONDS
                continue
            raise BridgeError(
                "REAPER did not pick up the request. Check that REAPER is "
                "open and the eminor_mcp_bridge.lua action is still running."
            )
        time.sleep(POLL_SECONDS)
    text = response_path.read_text(encoding="utf-8", errors="replace")
    response_path.unlink(missing_ok=True)
    return text


def send_request(code: str, undo_label: str | None = None) -> dict:
    """Runs `code` in REAPER and returns the bridge's response.

    Args:
        code: Lua source to run.
        undo_label: Undo point name, for scripts that change the project.

    Returns:
        The bridge's response: id, ok, and result or error, plus output.

    Raises:
        BridgeError: If the bridge is not available or does not answer.
    """
    folder = bridge_folder()
    check_running(folder)

    request_id = uuid.uuid4().hex[:12]
    header = f"--@id {request_id}\n"
    if undo_label:
        header += f"--@undo {' '.join(undo_label.split())}\n"

    # The zero-padded time first, so REAPER sorting the names takes
    # requests in the order they were sent.
    stem = f"request-{time.time_ns():020d}-{request_id}"
    request_path = folder / f"{stem}.lua"
    temporary_path = folder / f"{stem}.tmp"

    # Write under another name first, so REAPER never reads half a file.
    temporary_path.write_text(header + code, encoding="utf-8")
    os.replace(temporary_path, request_path)
    text = wait_for_response(
        request_path, folder / f"response-{request_id}.json"
    )
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
