# /// script
# requires-python = ">=3.10"
# dependencies = [
#     "mcp>=2,<3",
#     "pyobjc-framework-Quartz; sys_platform == 'darwin'",
# ]
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
from typing import Annotated, Literal, NotRequired, TypedDict

from pydantic import Field

from mcp.server.mcpserver import Image, MCPServer

import screenshot

# Waiting in the queue, behind other clients' scripts (5 seconds at most
# each), before REAPER takes the request.
PICKUP_TIMEOUT_SECONDS = 15
# After pickup. The bridge stops a script after 5.
RESPONSE_TIMEOUT_SECONDS = 10
POLL_SECONDS = 0.02
BRIDGE_VERSION = 3   # lib/loop.lua's M.VERSION this server speaks to

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
        parts.append(json.dumps(response.get("result"), indent=2, ensure_ascii=False))
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


def to_lua(value) -> str:
    """`value` (from JSON-like Python) as a Lua literal."""
    if value is None:
        return "nil"
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, (int, float)):
        return repr(value)
    if isinstance(value, str):
        return _lua_string(value)
    if isinstance(value, dict):
        fields = ", ".join(
            f"[{_lua_string(str(k))}] = {to_lua(v)}"
            for k, v in value.items() if v is not None
        )
        return "{" + fields + "}"
    if isinstance(value, (list, tuple)):
        return "{" + ", ".join(to_lua(v) for v in value) + "}"
    raise TypeError(f"cannot pass {type(value).__name__} to Lua")


def _lua_string(text: str) -> str:
    """`text` as a quoted Lua string. UTF-8 passes through as is."""
    escaped = []
    for char in text:
        if char in ('"', "\\"):
            escaped.append("\\" + char)
        elif ord(char) < 32 or ord(char) == 127:
            escaped.append(f"\\{ord(char):03d}")
        else:
            escaped.append(char)
    return '"' + "".join(escaped) + '"'


@mcp.tool()
def reaper_project_summary() -> str:
    """Describes the open REAPER project: tempo, time signature, cursor,
    tracks (number, name, FX, whether it has an instrument, item count),
    markers and regions, and `selected`: the selected tracks and items
    and the item open in the MIDI editor. Read-only. Call this before
    changing anything."""
    return run("return bridge.project_summary()")


def described(text: str):
    """A field description, which the client shows the model."""
    return Field(description=text)


START = described("Quarter notes from the start of `bar`.")
CHANNEL = described("1-16, default 1.")
PITCH_TYPE = int | str


class Note(TypedDict):
    pitch: Annotated[PITCH_TYPE, described(
        'MIDI number (60 is middle C) or a name: "C4", "C#4", "Db4".')]
    start: Annotated[float, START]
    length: Annotated[float, described("In quarter notes.")]
    velocity: NotRequired[Annotated[int, described("1-127, default 96.")]]
    channel: NotRequired[Annotated[int, CHANNEL]]


EventType = Literal[
    "cc", "pitch_bend", "program", "channel_pressure", "poly_aftertouch"
]


class MidiEvent(TypedDict):
    type: NotRequired[Annotated[EventType, described('Default "cc".')]]
    start: Annotated[float, START]
    value: Annotated[int, described(
        "0-127; for pitch_bend -8192 to 8191, with 0 the centre.")]
    cc: NotRequired[Annotated[int, described(
        'The controller, for type "cc": 1 mod wheel, 7 volume, '
        "11 expression, 64 sustain.")]]
    pitch: NotRequired[Annotated[PITCH_TYPE, described(
        'The note, for type "poly_aftertouch".')]]
    channel: NotRequired[Annotated[int, CHANNEL]]


@mcp.tool()
def reaper_read_midi(
    track: int | str | None = None,
    item: Literal["selected", "editor"] | None = None,
    from_bar: int | None = None,
    to_bar: int | None = None,
    include_events: bool = True,
) -> str:
    """Reads MIDI notes and events (CCs, pitch bend, program changes,
    pressure) from REAPER. Read-only.

    Say where: `track` (number, or name: exact, else a unique partial
    match), or `item` = "selected" (the selected MIDI items) or "editor"
    (the take open in the MIDI editor). `from_bar`/`to_bar` (inclusive)
    limit it to those bars; use them on long tracks.

    Returns a list of items. In each, every note's and event's `start` is
    in quarter notes from the start of the item's `bar` (from_bar if given,
    else the bar the item starts in): the same convention
    reaper_write_midi uses, so what you read can be edited and written back
    with mode "replace". Notes also have `name` ("C#4") and `at`, the
    bar.beat position ("5.2.5" is halfway through beat 2 of bar 5).
    """
    spec = {
        "track": track, "item": item, "from_bar": from_bar,
        "to_bar": to_bar, "events": include_events,
    }
    return run(f"return bridge.read_midi({to_lua(spec)})")


@mcp.tool()
def reaper_write_midi(
    mode: Literal["new", "add", "replace"],
    undo_label: str,
    track: int | str | None = None,
    item: Literal["selected", "editor"] | None = None,
    bar: int = 1,
    bars: int | None = None,
    notes: list[Note] | None = None,
    events: list[MidiEvent] | None = None,
    name: str | None = None,
) -> str:
    """Writes MIDI notes and events into REAPER, as one undo point
    named `undo_label` (e.g. "Add bass line").

    mode:
      "new": a new item on `track` starting at `bar`, `bars` long (default:
        just fits what is written). `name` names it.
      "add": into the existing item at `bar`, keeping what is there.
      "replace": clears bars `bar` to `bar + bars - 1` and writes there.
        Notes ringing into the range from before are shortened to its
        start. Events are cleared only on the lanes `events` writes (a CC
        number, or pitch bend), so rewriting notes keeps the sustain pedal.
        With no item there yet, one is made.
    Items grow to fit what is written.

    Say where: `track` (number or name), or `item` = "selected" (exactly one
    selected MIDI item) or "editor" (the take open in the MIDI editor),
    for "add" and "replace".

    Times: every `start` is in quarter notes from the start of `bar`, and
    lengths are in quarter notes, whatever the time signature (a 5/4 bar
    is 5, a 6/8 bar is 3). Pitches are numbers or names (60 = "C4",
    middle C).

    Nothing is written if any note or event is invalid. Nothing runs
    while REAPER is recording.
    """
    spec = {
        "mode": mode, "track": track, "item": item, "bar": bar, "bars": bars,
        "notes": notes or [], "events": events or [], "name": name,
    }
    return run(f"return bridge.write_midi({to_lua(spec)})", undo_label)


@mcp.tool()
def reaper_screenshot(
    window: str = "main", max_size: int = 1600
) -> list[Image | str]:
    """Takes a screenshot of a REAPER window and shows it to you, for
    debugging layouts, themes, scripts and plugin windows. macOS only.
    Read-only: it does not bring windows forward or touch REAPER.

    window: "main" (the main window, default), "front" (the frontmost
    REAPER window), "all" (every REAPER window, up to 6 images), or part
    of a window's title, ignoring case, e.g. "MIDI editor", "Mixer",
    "Pianoteq". An unknown title lists the windows there are.

    max_size: the longest side, in pixels, of the image you get. The
    full-size PNG is saved, and its path is in the reply.
    """
    try:
        chosen = screenshot.choose_windows(screenshot.reaper_windows(), window)
        results: list[Image | str] = []
        for each in chosen:
            full, small = screenshot.capture(each, max(200, min(max_size, 4000)))
            results.append(f"{each.describe()}, full size at {full}")
            results.append(Image(path=small))
        return results
    except screenshot.ScreenshotError as problem:
        return ["ERROR: " + str(problem)]


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

    bridge.read_midi(spec), bridge.write_midi(spec)
        What reaper_read_midi and reaper_write_midi do, with the same
        arguments as a table, e.g. bridge.write_midi({mode = "new",
        track = "Piano", bar = 1, notes = {...}}). Prefer those tools for
        MIDI; use these when a script needs MIDI along with other changes.

    Example, one bar of C# major in 5/4:

        bridge.set_time_signature(5, 4)
        return bridge.write_midi({
          mode = "new", track = "Piano", bar = 1, bars = 1, name = "C#",
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
