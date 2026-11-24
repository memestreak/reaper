# Eminor Auto Color

A replacement for SWS Auto Color/Icon/Layout, written as Lua ReaScripts.
It colours tracks, markers and regions, and sets track icons and layouts,
by rules you set. It leaves changes you make by hand alone.

![The rule editor](docs/editor.png)

## Quick start

1. Install ReaImGui from ReaPack (Extensions › ReaPack › Browse packages).
2. Load `eminor_autocolor_editor.lua` in the Action List (New action ›
   Load ReaScript) and run it. It adds the engine to the Action List
   itself; press **Start engine** at the bottom of the editor.
3. Add rules with **+**. From then on the engine starts with REAPER
   (untick Settings › Startup to stop that). Moving from SWS?
   Settings › SWS imports its rules and switches it off.

## Actions

Only the editor needs loading (Action List › New action › Load
ReaScript): it adds the engine action the first time it opens.

| Script | What it does |
| --- | --- |
| `eminor_autocolor_engine.lua` | The background engine that applies the rules; run again to stop it. Shows on/off on toolbars. Started by the editor's **Start engine** button or by Settings › Startup. |
| `eminor_autocolor_editor.lua` | Opens the rule editor; run again to close it. Needs ReaImGui 0.10+ (ReaPack). |

The editor has everything else: the five on/off switches (the pills
along the top), Force, Settings and Undo.

## The editor

Rules are grouped into Tracks, Regions and Markers, each in its own
priority order (top wins), and edited in place:

- **Drag** a row's `::` grip to reorder it, or select a row and press
  Alt+Up / Alt+Down. Right-click the grip to duplicate, move or delete.
- **Tick** a rule to turn it on or off without deleting it.
- **Click the swatch** for colours: saved palettes and colours in use
  first, "Custom colour…" for the full picker. Family colours have a
  Range / Palette toggle with hue and lightness sliders and a preview.
- **Type the filter**, or pick a special filter from the arrow menu.
- **Click the icon** for a browser over `Data/track_icons` (subfolders
  included). TCP and MCP menus list the current theme's layouts.
- The number on the right is how many items the filter matches now.

Every change is saved at once and the engine applies it straight away.
Cmd+Z and Cmd+Shift+Z (or the Undo and Redo buttons) undo rule edits.
The pills along the top are the five on/off switches. Settings holds the
engine's fallback check interval, the icon thumbnail size, and "Start
the engine with REAPER", which adds or removes one line in
`Scripts/__startup.lua`.

Settings › SWS has SWS's own five Auto Color switches (leave them off:
SWS and this script would undo each other's colours) and **Import rules
from SWS…**, which adds SWS's rules after yours (leaving out ones with a
type and filter you already have) or replaces yours. The import changes
your rules at once, and Undo in the editor takes it back. The footer
warns while SWS is switched on for something this script also does.

## Rules

Rules live in `<resource folder>/Data/eminor_autocolor/rules.lua`, outside
this repository. The first time the editor or engine runs it creates the file,
copying your SWS rules from `sws-autocoloricon.ini` if there are any.
The editor writes it; hand edits also work and are picked up within two
seconds. The format is described at the top of `lib/rules.lua`.

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
