-- lib/engine.lua
--
-- The background engine: a reaper.defer loop that watches the project and
-- runs a pass when something a rule depends on has changed.
--
-- Each tick costs a handful of API calls unless something changed; see
-- watch.lua for the timing rules that keep it out of REAPER's way.

local rules_module = require("lib.rules")
local settings = require("lib.settings")
local apply = require("lib.apply")
local watch = require("lib.watch")
local sws_import = require("lib.sws_import")

local M = {}

local RULES_FILE_CHECK_SECONDS = 2  -- for hand edits; the editor signals at once

-- set_action_options flags (REAPER 7.03+)
local OPTION_TERMINATE_ON_RELAUNCH = 1
local OPTION_TOGGLE_ON = 4
local OPTION_TOGGLE_OFF = 8


local function log(message)
  reaper.ShowConsoleMsg("eminor Auto Color: " .. message .. "\n")
end

local function report_problems(problems)
  for _, problem in ipairs(problems) do log(problem) end
end

-- Shows each switch's state on toolbar buttons of its toggle action.
local function refresh_toggle_states(switches)
  local MAIN_SECTION = 0
  for _, switch in ipairs(settings.SWITCHES) do
    local command_id = settings.toggle_command(switch.key)
    if command_id then
      reaper.SetToggleCommandState(MAIN_SECTION, command_id, switches[switch.key] and 1 or 0)
      reaper.RefreshToolbar2(MAIN_SECTION, command_id)
    end
  end
end

-- Creates the rules file on first run. If SWS rules exist they are copied
-- in (skipping SWS's unused "(name)" placeholder), along with SWS's on/off
-- switches; otherwise the file starts empty.
local function create_rules_file(path)
  local sep = package.config:sub(1, 1)
  local folder = path:match("^(.*)" .. sep)
  reaper.RecursiveCreateDirectory(folder, 0)

  local sws_path = reaper.GetResourcePath() .. sep .. "sws-autocoloricon.ini"
  local sws_text = rules_module.read_file(sws_path)
  local clean = {}
  if sws_text then
    local from_native = function(native)
      local r, g, b = reaper.ColorFromNative(native)
      return (r << 16) | (g << 8) | b
    end
    local raw_rules, switches, skipped = sws_import.parse(sws_text, from_native)
    report_problems(skipped)
    for i, raw in ipairs(raw_rules) do
      local rule, err = rules_module.check_rule(raw)
      if not rule then
        log("SWS rule " .. i .. " not imported: " .. err)
      elseif not sws_import.is_unused_placeholder(rule) then
        clean[#clean + 1] = rule
      end
    end
    for key, on in pairs(switches) do settings.set_switch(key, on) end
    log(string.format("copied %d rules from SWS into %s", #clean, path))
  end
  rules_module.assign_ids(clean)
  rules_module.write_file(path, rules_module.serialize(clean))
end


function M.run()
  if not reaper.set_action_options then
    reaper.MB("eminor Auto Color needs REAPER 7.03 or newer.", "eminor Auto Color", 0)
    return
  end
  reaper.set_action_options(OPTION_TERMINATE_ON_RELAUNCH | OPTION_TOGGLE_ON)
  settings.set_engine_running(true)
  reaper.atexit(function()
    reaper.set_action_options(OPTION_TOGGLE_OFF)
    settings.set_engine_running(false)
  end)

  local path = rules_module.file_path()
  if not rules_module.read_file(path) then
    create_rules_file(path)
  end

  local rules, rules_text = {}, nil
  local switches = settings.read_switches()
  local switches_version = settings.switches_version()
  local rules_version = nil
  local next_rules_check = 0

  local project, change_count, signature = nil, nil, nil
  local next_backstop = 0
  local gate = watch.new_gate()
  local pending = true  -- run once at start

  refresh_toggle_states(switches)

  local function reload_rules_if_changed()
    local text = rules_module.read_file(path) or ""
    if text ~= rules_text then
      rules_text = text
      local problems
      rules, problems = rules_module.parse(text)
      report_problems(problems)
      pending = true
    end
  end

  local function tick()
    local now = reaper.time_precise()

    -- Rules: re-read when the editor says so, or now and then for hand edits.
    local version = settings.rules_version()
    if version ~= rules_version or now >= next_rules_check then
      rules_version = version
      next_rules_check = now + RULES_FILE_CHECK_SECONDS
      reload_rules_if_changed()
    end

    -- Switches: a toggle action bumps the version.
    local new_switches_version = settings.switches_version()
    if new_switches_version ~= switches_version then
      switches_version = new_switches_version
      switches = settings.read_switches()
      refresh_toggle_states(switches)
      pending = true
    end

    -- Project: has anything changed that a rule could depend on?
    local current_project = reaper.EnumProjects(-1)
    local count = reaper.GetProjectStateChangeCount(current_project)
    if current_project ~= project or count ~= change_count or now >= next_backstop then
      project, change_count = current_project, count
      next_backstop = now + watch.BACKSTOP_SECONDS
      local new_signature = watch.track_signature()
      if new_signature ~= signature then
        signature = new_signature
        pending = true
        watch.note_change(gate, now)
      end
    end

    watch.note_play_state(gate, now, math.tointeger(reaper.GetPlayState()) or 0)

    if pending and watch.may_run(gate, now) then
      pending = false
      apply.run_pass(rules, switches, false)
      -- Take our own edits as the new baseline so they don't trigger a pass.
      signature = watch.track_signature()
      change_count = reaper.GetProjectStateChangeCount(current_project)
    end

    reaper.defer(tick)
  end

  tick()
end

return M
