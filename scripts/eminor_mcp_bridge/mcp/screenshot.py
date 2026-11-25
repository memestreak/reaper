"""Screenshots of REAPER's windows, for the reaper_screenshot tool.

macOS only. The capture happens outside REAPER: the window server lists
REAPER's windows and `screencapture` copies one window's pixels, so
nothing runs on REAPER's main thread and audio and the UI are untouched.
It also captures windows that other windows cover, and plugin GUIs.

macOS asks once for Screen Recording permission for the app that runs
this server (the MCP client, or the terminal it was started from).
"""

import subprocess
import sys
import tempfile
import time
from dataclasses import dataclass
from pathlib import Path

MAX_WINDOWS = 6          # "all" returns at most this many images
KEEP_CAPTURES = 20       # older full-size captures are deleted
MIN_SIDE = 40            # smaller windows are tooltips and the like
TOP_LAYER = 20           # higher window layers are menus and overlays


class ScreenshotError(Exception):
    """A problem worth showing to the model as the tool's result."""


@dataclass
class Window:
    id: int
    title: str
    width: int
    height: int

    def describe(self) -> str:
        return f'"{self.title or "(no title)"}" ({self.width}x{self.height})'


PERMISSION_HELP = (
    "macOS has not allowed screen capture. In System Settings > Privacy & "
    "Security > Screen & System Audio Recording (called Screen Recording "
    "before macOS 15), turn on the app that runs this MCP server (your MCP "
    "client, or the terminal it runs in), then restart that app."
)


def reaper_windows() -> list[Window]:
    """REAPER's on-screen windows, frontmost first.

    Returns:
        The windows, possibly empty.

    Raises:
        ScreenshotError: If this is not macOS.
    """
    if sys.platform != "darwin":
        raise ScreenshotError("reaper_screenshot works on macOS only, for now.")
    import Quartz  # pyobjc-framework-Quartz, installed on macOS only

    infos = Quartz.CGWindowListCopyWindowInfo(
        Quartz.kCGWindowListOptionOnScreenOnly
        | Quartz.kCGWindowListExcludeDesktopElements,
        Quartz.kCGNullWindowID,
    )
    windows = []
    for info in infos or []:
        owner = str(info.get("kCGWindowOwnerName") or "")
        if not owner.upper().startswith("REAPER"):
            continue
        if int(info.get("kCGWindowLayer", 0)) >= TOP_LAYER:
            continue
        bounds = info.get("kCGWindowBounds") or {}
        width, height = int(bounds.get("Width", 0)), int(bounds.get("Height", 0))
        if width < MIN_SIDE or height < MIN_SIDE:
            continue
        windows.append(Window(
            id=int(info["kCGWindowNumber"]),
            title=str(info.get("kCGWindowName") or ""),
            width=width,
            height=height,
        ))
    return windows


def choose_windows(windows: list[Window], target: str) -> list[Window]:
    """Picks the windows `target` names.

    Args:
        windows: REAPER's windows, frontmost first.
        target: "main", "front", "all", or part of a window title
            (ignoring case), such as "MIDI editor" or "Pianoteq".

    Returns:
        The windows to capture, at least one.

    Raises:
        ScreenshotError: If none fit, listing the windows there are.
    """
    if not windows:
        raise ScreenshotError(
            "No REAPER windows are on screen. Is REAPER open, and not minimized?"
        )
    wanted = target.strip().lower()
    if wanted == "all":
        return windows[:MAX_WINDOWS]
    if wanted == "front":
        return windows[:1]
    if wanted == "main":
        # The main window's title ends in "- REAPER v7.xx ...".
        main = [w for w in windows if "reaper v" in w.title.lower()]
        if main:
            return main[:1]
        return [max(windows, key=lambda w: w.width * w.height)]
    matches = [w for w in windows if wanted in w.title.lower()]
    if matches:
        return matches[:1]
    titles = ", ".join(w.describe() for w in windows)
    problem = f'No REAPER window has "{target}" in its title. Windows: {titles}.'
    if not any(w.title for w in windows):
        problem += " Every title is empty, which usually means this: " + PERMISSION_HELP
    raise ScreenshotError(problem)


def capture_folder() -> Path:
    folder = Path(tempfile.gettempdir()) / "eminor_mcp_bridge_screenshots"
    folder.mkdir(parents=True, exist_ok=True)
    return folder


def forget_old_captures(folder: Path) -> None:
    captures = sorted(folder.glob("*.png"), key=lambda p: p.stat().st_mtime)
    for old in captures[:-KEEP_CAPTURES]:
        old.unlink(missing_ok=True)
        old.with_suffix(".jpg").unlink(missing_ok=True)


def capture(window: Window, max_size: int) -> tuple[Path, Path]:
    """Captures one window.

    Args:
        window: The window.
        max_size: Longest side, in pixels, of the copy for the model.

    Returns:
        The full-size PNG, and a smaller JPEG for the model.

    Raises:
        ScreenshotError: If macOS would not capture it.
    """
    folder = capture_folder()
    # Milliseconds too, so two captures of one window in a second both keep.
    now = time.time()
    stem = time.strftime("%Y%m%d-%H%M%S", time.localtime(now)) \
        + f"-{int(now * 1000) % 1000:03d}-{window.id}"
    full = folder / f"{stem}.png"
    small = folder / f"{stem}.jpg"
    # -x: no camera sound. -o: no window shadow. -l: just this window.
    done = subprocess.run(
        ["screencapture", "-x", "-o", f"-l{window.id}", str(full)],
        capture_output=True, text=True, timeout=10,
    )
    if done.returncode != 0 or not full.exists() or full.stat().st_size == 0:
        detail = (done.stderr or done.stdout).strip()
        raise ScreenshotError(
            f"Could not capture {window.describe()}"
            + (f": {detail}" if detail else "") + ". " + PERMISSION_HELP
        )
    subprocess.run(
        ["sips", "-Z", str(max_size), "-s", "format", "jpeg",
         "-s", "formatOptions", "80", str(full), "--out", str(small)],
        capture_output=True, timeout=10, check=True,
    )
    forget_old_captures(folder)
    return full, small
