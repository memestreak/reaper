# /// script
# requires-python = ">=3.10"
# dependencies = [
#     "mcp>=2,<3",
#     "pyobjc-framework-Quartz; sys_platform == 'darwin'",
# ]
# ///
"""End-to-end test of server.py against the fake bridge. Needs `lua`.

From the repository root:  uv run scripts/eminor_mcp_bridge/mcp/test_server.py
"""

import os
import subprocess
import sys
import tempfile
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

HERE = Path(__file__).resolve().parent
FAKE_BRIDGE = HERE.parent / "tests" / "fake_bridge.lua"


def check_to_lua(server):
    assert server.to_lua(None) == "nil"
    assert server.to_lua({"a": [1, 2.5, True], "b": None}) == '{["a"] = {1, 2.5, true}}'
    assert server.to_lua('say "hi"\\\n') == '"say \\"hi\\"\\\\\\010"'


def check_screenshot_choice():
    import screenshot
    from screenshot import ScreenshotError, Window

    windows = [
        Window(1, "FX: Track 2 \"Piano\" - Pianoteq 8", 900, 600),
        Window(2, "song.rpp [~/Music] - REAPER v7.27 - Registered to Jeremy", 1800, 1100),
        Window(3, "MIDI take: Chords", 1200, 700),
    ]
    choose = screenshot.choose_windows
    assert [w.id for w in choose(windows, "main")] == [2]
    assert [w.id for w in choose(windows, "front")] == [1]
    assert [w.id for w in choose(windows, "all")] == [1, 2, 3]
    assert [w.id for w in choose(windows, "midi take")] == [3]
    untitled = [Window(1, "", 300, 200), Window(2, "", 1800, 1100)]
    assert [w.id for w in choose(untitled, "main")] == [2], "largest"
    for wanted, pattern, among in [
        ("Mixer", "Windows: \"FX: Track 2", windows),
        ("Mixer", "Screen Recording", untitled),
        ("main", "No REAPER windows", []),
    ]:
        try:
            choose(among, wanted)
        except ScreenshotError as problem:
            assert pattern in str(problem), problem
        else:
            raise AssertionError(f"{wanted} should fail")


def main():
    folder = Path(tempfile.mkdtemp(prefix="eminor_mcp_bridge_"))
    os.environ["EMINOR_MCP_BRIDGE_FOLDER"] = str(folder)
    import server
    check_to_lua(server)
    check_screenshot_choice()
    if sys.platform != "darwin":
        result = server.reaper_screenshot()
        assert result == ["ERROR: reaper_screenshot works on macOS only, for now."], result
    server.PICKUP_TIMEOUT_SECONDS = 1
    server.RESPONSE_TIMEOUT_SECONDS = 3

    def requests_left() -> list[str]:
        return [p.name for p in folder.glob("request-*")]

    # No running.json yet: a clear message, and no request left behind.
    result = server.reaper_project_summary()
    assert "not running" in result, result
    assert not requests_left()

    # An older bridge (one shared request file) is refused.
    (folder / "running.json").write_text('{"version": 2}')
    result = server.reaper_run_lua("return 1")
    assert "older version" in result, result
    assert not requests_left()

    # running.json but nobody polling: times out and cleans up.
    (folder / "running.json").write_text('{"version": 3}')
    result = server.reaper_run_lua("return 1")
    assert "did not pick up" in result, result
    assert not requests_left()

    bridge = subprocess.Popen(["lua", str(FAKE_BRIDGE), str(folder)])
    try:
        summary = server.reaper_project_summary()
        assert '"name": "Piano"' in summary, summary

        result = server.reaper_run_lua(
            """
            bridge.set_time_signature(5, 4)
            print("placing chords")
            return bridge.insert_midi("Piano", {
              bar = 2, bars = 1,
              notes = { {pitch = 61, start = 0, length = 5} },
            })
            """,
            undo_label="Add chord\nprogression",
        )
        assert '"start_seconds": 2.5' in result, result
        assert "placing chords" in result, result

        notes = server.reaper_run_lua('return bridge.read_midi("Piano")')
        assert '"pitch": 61' in notes, notes

        result = server.reaper_run_lua(
            'bridge.find_track("Bass")', undo_label="x"
        )
        assert result.startswith("ERROR:") and "Drums, Piano" in result, result

        # Many calls at once, as from several clients: each gets its own
        # answer.
        with ThreadPoolExecutor(max_workers=8) as pool:
            answers = list(pool.map(
                lambda n: server.reaper_run_lua(f"return {n} * 10"),
                range(16),
            ))
        assert answers == [str(n * 10) for n in range(16)], answers

        # The MIDI tools: write, then read back what was written.
        result = server.reaper_write_midi(
            mode="new", undo_label="Add bass", track="Drums", bar=2, bars=1,
            name='Odd "name"\nwith a newline \\ and ünïcode',
            notes=[{"pitch": "C#2", "start": 0, "length": 1, "velocity": 90}],
            events=[{"cc": 64, "value": 127, "start": 0},
                    {"type": "pitch_bend", "value": -100, "start": 2}],
        )
        assert '"note_count": 1' in result and '"event_count": 2' in result, result
        result = server.reaper_write_midi(
            mode="replace", undo_label="Redo bass", track="Drums", bar=2, bars=1,
            notes=[{"pitch": 38, "start": 1, "length": 0.5}],
        )
        assert '"removed_notes": 1' in result, result
        notes = server.reaper_read_midi(track="Drums", from_bar=2)
        assert '"name": "D2"' in notes and '"at": "2.2"' in notes, notes
        assert 'ünïcode' in notes and '"value": -100' in notes, notes
        result = server.reaper_write_midi(
            mode="new", undo_label="x", track="Drums",
            notes=[{"pitch": "H2", "start": 0, "length": 1}],
        )
        assert result.startswith("ERROR:") and "pitch must be" in result, result

        leftovers = sorted(p.name for p in folder.iterdir())
        assert leftovers == ["running.json"], leftovers
    finally:
        (folder / "stop").write_text("")
        bridge.wait(timeout=5)
    print("server test passed")


if __name__ == "__main__":
    main()
