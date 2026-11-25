local loop = require("lib.loop")
local fake_reaper = require("fake_reaper")

local T = {}

-- Makes a fresh folder under $TMPDIR (os.tmpname() only knows /tmp, which
-- a sandbox may not allow).
local folder_count = 0
local function temp_folder()
  folder_count = folder_count + 1
  local base = (os.getenv("TMPDIR") or "/tmp"):gsub("/$", "")
  local name = string.format("%s/eminor_mcp_bridge_test_%d_%d", base, os.time(), folder_count)
  os.execute('rm -rf "' .. name .. '" && mkdir -p "' .. name .. '"')
  return name .. "/"
end

local function read(path)
  local file = io.open(path, "rb")
  if not file then return nil end
  local text = file:read("a")
  file:close()
  return text
end

local function write(path, text)
  local file = assert(io.open(path, "wb"))
  file:write(text)
  file:close()
end

function T.no_request_means_nothing_happens()
  assert(loop.poll_once(temp_folder(), fake_reaper.new()) == false)
end

function T.a_request_is_answered_and_removed()
  local folder = temp_folder()
  local name = "request-00000000000000000001-r1.lua"
  write(folder .. name, "--@id r1\nreturn bridge.project_summary().time_signature")
  assert(loop.poll_once(folder, fake_reaper.new()) == true)
  assert(read(folder .. name) == nil)
  local response = read(folder .. "response-r1.json")
  assert(response:find('"ok":true', 1, true) and response:find('"result":"4/4"', 1, true))
  assert(read(folder .. "response-r1.json.tmp") == nil)
end

function T.queued_requests_are_answered_oldest_first_one_per_poll()
  local folder = temp_folder()
  write(folder .. "request-00000000000000000002-b.lua", "--@id b\nreturn 2")
  write(folder .. "request-00000000000000000001-a.lua", "--@id a\nreturn 1")
  local r = fake_reaper.new()
  assert(loop.poll_once(folder, r) == true)
  assert(read(folder .. "response-a.json") and not read(folder .. "response-b.json"))
  assert(loop.poll_once(folder, r) == true)
  assert(read(folder .. "response-b.json"):find('"result":2', 1, true))
  assert(loop.poll_once(folder, r) == false)
end

function T.half_written_requests_and_other_files_are_left_alone()
  local folder = temp_folder()
  write(folder .. "request-00000000000000000001-a.tmp", "--@id a\nreturn 1")
  write(folder .. "running.json", "{}")
  write(folder .. "response-x.json", "{}")
  assert(loop.poll_once(folder, fake_reaper.new()) == false)
  assert(read(folder .. "request-00000000000000000001-a.tmp"))
end

function T.a_result_that_cannot_be_encoded_still_gets_an_answer()
  local folder = temp_folder()
  write(folder .. "request-00000000000000000001-r2.lua", "--@id r2\nlocal t = {} t.me = t return t")
  loop.poll_once(folder, fake_reaper.new())
  local response = read(folder .. "response-r2.json")
  assert(response:find('"ok":false', 1, true) and response:find("could not be sent back", 1, true))
end

return T
