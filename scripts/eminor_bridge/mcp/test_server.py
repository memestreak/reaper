# /// script
# requires-python = ">=3.10"
# dependencies = ["mcp>=2,<3"]
# ///
"""End-to-end test of server.py against the fake bridge. Needs `lua`.

From the repository root:  uv run scripts/eminor_bridge/mcp/test_server.py
"""

import os
import subprocess
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
FAKE_BRIDGE = HERE.parent / "tests" / "fake_bridge.lua"


def main():
    folder = Path(tempfile.mkdtemp(prefix="eminor_bridge_"))
    os.environ["EMINOR_BRIDGE_FOLDER"] = str(folder)
    import server
    server.RESPONSE_TIMEOUT_SECONDS = 3

    # No running.json yet: a clear message, and no request left behind.
    result = server.reaper_project_summary()
    assert "not running" in result, result
    assert not (folder / "request.lua").exists()

    # running.json but nobody polling: times out and cleans up.
    (folder / "running.json").write_text("{}")
    result = server.reaper_run_lua("return 1")
    assert "did not pick up" in result, result
    assert not (folder / "request.lua").exists()

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

        result = server.reaper_run_lua('bridge.find_track("Bass")', undo_label="x")
        assert result.startswith("ERROR:") and "Drums, Piano" in result, result

        leftovers = sorted(p.name for p in folder.iterdir())
        assert leftovers == ["running.json"], leftovers
    finally:
        (folder / "stop").write_text("")
        bridge.wait(timeout=5)
    print("server test passed")


if __name__ == "__main__":
    main()
