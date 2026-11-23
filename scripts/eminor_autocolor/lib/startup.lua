-- lib/startup.lua
--
-- Starting the engine with REAPER, through <resource>/Scripts/__startup.lua.
-- The editor's Settings › Startup section adds or removes one marked line;
-- the rest of the file is never touched. The file itself is the saved
-- value: the checkbox shows whether the line is there.
--
-- The text functions are pure and tested outside REAPER.

local M = {}

M.MARKER = "-- eminor Auto Color: start the engine (added by its editor)"

local function line_for(named_command)
  return string.format('reaper.Main_OnCommand(reaper.NamedCommandLookup("_%s"), 0)', named_command)
end

-- True when the text has our marked block.
function M.has_line(text)
  return (text or ""):find(M.MARKER, 1, true) ~= nil
end

-- Removes our marked block (the marker comment and the line after it).
function M.remove_line(text)
  local out, skip_next = {}, false
  for line in ((text or "") .. "\n"):gmatch("([^\n]*)\n") do
    if skip_next then
      skip_next = false
    elseif line == M.MARKER then
      skip_next = true
    else
      out[#out + 1] = line
    end
  end
  -- gmatch on text plus "\n" adds one empty line at the end
  if out[#out] == "" then out[#out] = nil end
  if #out == 0 then return "" end
  return table.concat(out, "\n") .. "\n"
end

-- Adds our block at the end (replacing an old one, so the command ID is current).
function M.add_line(text, named_command)
  local rest = M.remove_line(text)
  if rest ~= "" and rest:sub(-1) ~= "\n" then rest = rest .. "\n" end
  return rest .. M.MARKER .. "\n" .. line_for(named_command) .. "\n"
end


-- -----------------------------------------------------------------------------
-- The file. Needs REAPER.
-- -----------------------------------------------------------------------------

function M.file_path()
  local sep = package.config:sub(1, 1)
  return reaper.GetResourcePath() .. sep .. "Scripts" .. sep .. "__startup.lua"
end

local function read(path)
  local file = io.open(path, "r")
  if not file then return "" end
  local text = file:read("a")
  file:close()
  return text
end

function M.is_enabled()
  return M.has_line(read(M.file_path()))
end

-- The engine action's named command ID ("RS..."), found in the text of
-- reaper-kb.ini, where REAPER lists every loaded script:
--   SCR 4 0 RS1a2b... "Custom: eminor_autocolor_engine.lua" "/path/eminor_autocolor_engine.lua"
function M.engine_command_in_keymap(text)
  for line in (text or ""):gmatch("[^\r\n]+") do
    if line:find("^SCR ") and line:find("eminor_autocolor_engine.lua", 1, true) then
      local id = line:match("^SCR %S+ %S+ (%S+)")
      if id then return (id:gsub("^_", "")) end
    end
  end
  return nil
end

-- Finds the engine's command ID even if the engine has never run.
function M.find_engine_command()
  local sep = package.config:sub(1, 1)
  return M.engine_command_in_keymap(read(reaper.GetResourcePath() .. sep .. "reaper-kb.ini"))
end

-- Adds or removes the line. Returns true, or false and a message.
function M.set_enabled(on, named_command)
  local path = M.file_path()
  local text = read(path)
  local new_text
  if on then
    if not named_command then
      return false, "Couldn't find the engine action in the Action List. Load "
          .. "eminor_autocolor_engine.lua there (New action › Load ReaScript), then try again."
    end
    new_text = M.add_line(text, named_command)
  else
    new_text = M.remove_line(text)
  end
  if new_text == text then return true end
  local file, err = io.open(path, "w")
  if not file then return false, err end
  file:write(new_text)
  file:close()
  return true
end

return M
