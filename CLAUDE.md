# Reaper scripts

A personal collection of Lua action scripts for the Reaper DAW.

## Git

- Committing directly to `main` is fine in this repo. It overrides the
  global "always use a separate branch" rule -- these are small personal
  scripts with no code review step. Use a branch only when asked, or when
  a change is large enough to want one.
- The remote is named `github`, not `origin`. Use `git push github main`.

## Lua scripts

- Scripts live in `scripts/` and are loaded by Reaper's Action List.
- Syntax-check before reporting a change as done: `luac -p <file>`.
  Reaper's API (the `reaper.*` table) is unavailable outside Reaper, so
  scripts cannot be executed here -- `luac -p` catches syntax errors
  only, and behavior needs testing in Reaper itself.
- Refer to native actions by a named constant holding the command ID,
  with the Action List description in a trailing comment, rather than
  passing bare integers to `reaper.Main_OnCommand`.
