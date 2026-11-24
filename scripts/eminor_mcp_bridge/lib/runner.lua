-- lib/runner.lua
--
-- Runs one request and builds the response. No file access here: loop.lua
-- reads the request file and writes the response file.
--
-- A request is Lua source. Two optional comment lines at the top carry
-- its details:
--   --@id 3f9c2a          names the response file
--   --@undo Add chords    wraps the run in one undo point with this label
-- A request without --@undo must only read the project.

local M = {}

local RECORDING_BIT = 4          -- reaper.GetPlayState() bit: recording
local TIME_LIMIT_SECONDS = 5     -- a runaway script is stopped after this
local HOOK_INSTRUCTION_COUNT = 100000

function M.parse(text)
  return {
    id = text:match("%-%-@id ([%w_%-]+)") or "unknown",
    undo = text:match("%-%-@undo ([^\r\n]+)"),
    code = text,   -- the --@ lines are comments, so line numbers stay true
  }
end

-- Runs `request` (from M.parse). `r` is the reaper API table and `helpers`
-- is the table scripts see as `bridge`. Returns the response table.
function M.run(request, r, helpers)
  local response = { id = request.id, ok = false }

  if r.GetPlayState() & RECORDING_BIT ~= 0 then
    response.error = "REAPER is recording, so the bridge is not running requests."
    return response
  end

  -- The script gets its own globals, so one request cannot leave
  -- variables behind for the next.
  local printed = {}
  local env = setmetatable({
    reaper = r,
    bridge = helpers,
    print = function(...)
      local parts = table.pack(...)
      for i = 1, parts.n do parts[i] = tostring(parts[i]) end
      printed[#printed + 1] = table.concat(parts, "\t")
    end,
  }, { __index = _G })

  local chunk, syntax_error = load(request.code, "=request", "t", env)
  if not chunk then
    response.error = "Syntax error: " .. tostring(syntax_error)
    return response
  end

  local started = r.time_precise()
  local function stop_if_too_slow()
    if r.time_precise() - started > TIME_LIMIT_SECONDS then
      error(string.format("stopped after %d seconds", TIME_LIMIT_SECONDS), 0)
    end
  end

  if request.undo then r.Undo_BeginBlock2(0) end
  r.PreventUIRefresh(1)
  debug.sethook(stop_if_too_slow, "", HOOK_INSTRUCTION_COUNT)
  local ok, result = xpcall(chunk, debug.traceback)
  debug.sethook()
  r.PreventUIRefresh(-1)
  if request.undo then
    -- Also on failure, so whatever the script changed can be undone.
    r.Undo_EndBlock2(0, request.undo, -1)
  end
  r.UpdateArrange()

  response.ok = ok
  if ok then
    response.result = result
  else
    response.error = tostring(result)
  end
  response.output = table.concat(printed, "\n")
  response.elapsed_ms = math.floor((r.time_precise() - started) * 1000 + 0.5)
  return response
end

return M
