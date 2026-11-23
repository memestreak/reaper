# eminor Auto Color

A replacement for SWS Auto Color/Icon/Layout, written as Lua ReaScripts.
It colours tracks, markers and regions, and sets track icons and layouts,
by rules you set. It leaves changes you make by hand alone.

Status: **phase 2**. Everything SWS Auto Color/Icon/Layout does works
from the rules file. The editor window comes in phase 3; see the plan doc.

## Actions

Load each with Action List › New action › Load ReaScript.

| Script | What it does |
| --- | --- |
| `eminor_autocolor_engine.lua` | Starts the background engine; run again to stop it. Shows on/off on toolbars. |
| `eminor_autocolor_force.lua` | Applies every rule now, overwriting hand-set colours, as one undo point. |
| `eminor_autocolor_toggle_track_colour.lua` | Turns automatic track colouring on or off. |
| `eminor_autocolor_toggle_track_icon.lua` | Turns automatic track icons on or off. |
| `eminor_autocolor_toggle_track_layout.lua` | Turns automatic TCP/MCP layouts on or off (off at first, as in SWS). |
| `eminor_autocolor_toggle_marker_colour.lua` | Turns automatic marker colouring on or off. |
| `eminor_autocolor_toggle_region_colour.lua` | Turns automatic region colouring on or off. |
| `eminor_autocolor_toggle_timing_log.lua` | Prints how much UI time the engine uses to the console every 10 s. Off again after a restart. |

All toggles show on/off on toolbars.

To start the engine with REAPER, add this line to
`<resource folder>/Scripts/__startup.lua`, using the command ID the
Action List shows for the engine script (right-click › Copy selected
action command ID):

```lua
reaper.Main_OnCommand(reaper.NamedCommandLookup("_RS..."), 0)
```

## Rules

Rules live in `<resource folder>/Data/eminor_autocolor/rules.lua`, outside
this repository. The first time the engine runs it creates the file,
copying your SWS rules from `sws-autocoloricon.ini` if there are any.
Until the editor exists, edit the file by hand; the engine picks up
changes within two seconds. The format is described at the top of
`lib/rules.lua`.

Matching follows SWS:

- A name filter matches when the name **contains** it, ignoring case
  (`gtr` matches `Bass Gtr DI`). There are no wildcards.
- Special filters in brackets match track properties: `(any)`,
  `(unnamed)`, `(folder)`, `(children)`, `(receive)`, `(master)`,
  `(record armed)`, `(vca master)`, `(instrument)`, `(audio input)`,
  `(audio output)`, `(MIDI input)`, `(MIDI output)`.
- Marker and region rules understand `(any)` and `(unnamed)`.
- Within a target, the first matching rule wins. Colour, icon, TCP layout
  and MCP layout are settled separately: a rule that only names an icon
  leaves the colour to the rules below it.
- A layout of `(hide)` hides the track in that panel instead.
- Icons are named relative to `<resource folder>/Data/track_icons`.

Colour modes: `fixed`, `gradient`, `family` (similar shades from a range
or a palette), `random` (stable per track), `parent`, `none` and
`ignore`.

## Changes you make by hand

Each track, marker and region remembers what the engine last set on it
(tracks in the track, markers and regions in the project). The engine
only changes what is still as it left it, and undoes its own changes
when a rule stops matching. Force overwrites everything.

Two cases are taken over on first sight, so moving from SWS is smooth:

- a track whose colour is exactly one a fixed rule gives;
- a marker or region that a rule matches (SWS recoloured those on every
  pass, so any colour on them came from SWS).

Tracks SWS coloured with a gradient or random colour can't be told
apart from hand colours. Run Force once to take them over.

Unlike SWS, a colour you set by hand on a marker or region now stays.

## Performance

The engine runs on REAPER's UI thread, never the audio thread. Most ticks
only compare a change counter and return. It looks at the tracks only
when the project changes (or every half second as a fallback), never
applies while recording, and waits 300 ms after Play, Record or Stop.
To check the cost on your own projects, turn on the timing log.

## Tests

The logic that doesn't need REAPER is tested with plain Lua 5.4:

```sh
lua scripts/eminor_autocolor/tests/run.lua
```

`tests/fake_reaper.lua` stands in for the REAPER API in those tests.
Anything that touches REAPER for real still needs checking in REAPER.
