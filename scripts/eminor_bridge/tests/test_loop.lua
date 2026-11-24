local loop = require("lib.loop")
local fake_reaper = require("fake_reaper")

local T = {}

-- Makes a fresh folder under $TMPDIR (os.tmpname() only knows /tmp, which
-- a sandbox may not allow).
local folder_count = 0
local function temp_folder()
  folder_count = folder_count + 1
  local base = (os.getenv("TMPDIR") or "/tmp"):gsub("/$", "")
  local name = string.format("%s/eminor_bridge_test_%d_%d", base, os.time(), folder_count)
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
  write(folder .. "request.lua", "--@id r1\nreturn bridge.project_summary().time_signature")
  assert(loop.poll_once(folder, fake_reaper.new()) == true)
  assert(read(folder .. "request.lua") == nil)
  local response = read(folder .. "response-r1.json")
  assert(response:find('"ok":true', 1, true) and response:find('"result":"4/4"', 1, true))
  assert(read(folder .. "response-r1.json.tmp") == nil)
end

function T.a_result_that_cannot_be_encoded_still_gets_an_answer()
  local folder = temp_folder()
  write(folder .. "request.lua", "--@id r2\nlocal t = {} t.me = t return t")
  loop.poll_once(folder, fake_reaper.new())
  local response = read(folder .. "response-r2.json")
  assert(response:find('"ok":false', 1, true) and response:find("could not be sent back", 1, true))
end

return T
