# /// script
# requires-python = ">=3.10"
# dependencies = ["mcp>=2,<3"]
# ///
"""End-to-end test of server.py against the fake bridge. Needs `lua`.

From the repository root:  uv run scripts/eminor_mcp_bridge/mcp/test_server.py
"""

import os
import subprocess
import tempfile
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

HERE = Path(__file__).resolve().parent
FAKE_BRIDGE = HERE.parent / "tests" / "fake_bridge.lua"


def main():
    folder = Path(tempfile.mkdtemp(prefix="eminor_mcp_bridge_"))
    os.environ["EMINOR_MCP_BRIDGE_FOLDER"] = str(folder)
    import server
    server.PICKUP_TIMEOUT_SECONDS = 1
    server.RESPONSE_TIMEOUT_SECONDS = 3

    def requests_left() -> list[str]:
        return [p.name for p in folder.glob("request-*")]

    # No running.json yet: a clear message, and no request left behind.
    result = server.reaper_project_summary()
    assert "not running" in result, result
    assert not requests_left()

    # An older bridge (one shared request file) is refused.
    (folder / "running.json").write_text('{"version": 1}')
    result = server.reaper_run_lua("return 1")
    assert "older version" in result, result
    assert not requests_left()

    # running.json but nobody polling: times out and cleans up.
    (folder / "running.json").write_text('{"version": 2}')
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

        leftovers = sorted(p.name for p in folder.iterdir())
        assert leftovers == ["running.json"], leftovers
    finally:
        (folder / "stop").write_text("")
        bridge.wait(timeout=5)
    print("server test passed")


if __name__ == "__main__":
    main()
