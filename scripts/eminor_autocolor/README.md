# eminor Auto Color

A replacement for SWS Auto Color/Icon/Layout, written as Lua ReaScripts.
It colours tracks (and later markers, regions, icons and layouts) by
rules you set, and leaves colours you set by hand alone.

Status: **phase 1**, the engine core. Track colour works with every
colour mode. Markers, regions, icons, layouts and the editor window come
in later phases; see the plan doc.

## Actions

Load each with Action List › New action › Load ReaScript.

| Script | What it does |
| --- | --- |
| `eminor_autocolor_engine.lua` | Starts the background engine; run again to stop it. Shows on/off on toolbars. |
| `eminor_autocolor_force.lua` | Applies every rule now, overwriting hand-set colours, as one undo point. |
| `eminor_autocolor_toggle_track_colour.lua` | Turns automatic track colouring on or off. |

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
- Within a target, the first matching rule wins.

Colour modes: `fixed`, `gradient`, `family` (similar shades from a range
or a palette), `random` (stable per track), `parent`, `none` and
`ignore`.

## Performance

The engine runs on REAPER's UI thread, never the audio thread. Most ticks
only compare a change counter and return. It looks at the tracks only
when the project changes (or every half second as a fallback), never
applies while recording, and waits 300 ms after Play, Record or Stop.

## Tests

The logic that doesn't need REAPER is tested with plain Lua 5.4:

```sh
lua scripts/eminor_autocolor/tests/run.lua
```

`tests/fake_reaper.lua` stands in for the REAPER API in those tests.
Anything that touches REAPER for real still needs checking in REAPER.
