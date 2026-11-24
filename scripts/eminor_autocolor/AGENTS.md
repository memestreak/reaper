# Notes for agents working on Eminor Auto Color

Background that the user-facing README leaves out. Read this before
changing the engine, the editor or the tests.

## Hand changes and ownership

Each track, marker and region remembers what the engine last set on it
(tracks in their P_EXT, markers and regions in the project). The engine
only changes what is still as it left it, and undoes its own changes
when a rule stops matching. The editor's Force button overwrites
everything.

Two cases are taken over on first sight, so moving from SWS is smooth:

- a track whose colour is exactly one a fixed rule gives;
- a marker or region that a rule matches (SWS recoloured those on every
  pass, so any colour on them came from SWS).

Tracks SWS coloured with a gradient or random colour can't be told apart
from hand colours; Force takes them over. Unlike SWS, a colour set by
hand on a marker or region stays.

## Performance limits (hard rule: never affect audio, transport or UI smoothness)

- The engine runs on REAPER's UI thread (a defer loop), never the audio
  thread.
- Most ticks only compare a change counter and return. Tracks are
  scanned only when the project changes, or every 0.5 s as a fallback.
- Nothing is applied while recording, and the engine waits 300 ms after
  Play, Record or Stop.
- Settings has a timing log for measuring the cost on real projects.
  Keep new work inside these limits.

## Tests

The REAPER-free logic is tested with plain Lua 5.4:

```sh
lua scripts/eminor_autocolor/tests/run.lua
```

- `tests/fake_reaper.lua` stands in for the REAPER API (including a fake
  SWS command registry and a script registry for AddRemoveReaScript).
- `tests/fake_imgui.lua` stands in for ReaImGui and knows the real
  argument counts of every ReaImGui 0.10 function and constant the editor
  uses, so a wrong name or call fails the tests. Add any new ReaImGui call
  or constant there, checked against the 0.10 API.
- The fakes can't show how the window looks. Anything that touches REAPER
  for real still needs checking in REAPER.

Also syntax-check changed files with `luac -p` (see the root CLAUDE.md).
