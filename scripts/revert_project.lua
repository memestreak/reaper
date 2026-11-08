-- Revert: reload the current project from its last saved file,
-- discarding unsaved changes without prompting.

local _, path = reaper.EnumProjects(-1)
if path == "" then return end -- never saved; nothing to revert to

reaper.Main_openProject("noprompt:" .. path)
