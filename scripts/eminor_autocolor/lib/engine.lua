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
local timing = require("lib.timing")
local prefs = require("lib.prefs")

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
local function refresh_toggle_states(switches, timing_on)
  local MAIN_SECTION = 0
  local function show(key, on)
    local command_id = settings.toggle_command(key)
    if command_id then
      reaper.SetToggleCommandState(MAIN_SECTION, command_id, on and 1 or 0)
      reaper.RefreshToolbar2(MAIN_SECTION, command_id)
    end
  end
  for _, switch in ipairs(settings.SWITCHES) do
    show(switch.key, switches[switch.key])
  end
  show(settings.TIMING_LOG, timing_on)
end

-- Creates the rules file on first run. If SWS rules exist they are copied
-- in (skipping SWS's unused "(name)" placeholder); otherwise the file
-- starts empty. SWS's on/off switches are not copied: switching SWS off
-- is part of moving over, so they are usually off by now.
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
    local problems
    clean, problems = sws_import.convert(sws_text, from_native)
    report_problems(problems)
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
  -- Remember this action's ID, for the editor's "start with REAPER" setting.
  local _, _, _, command_id = reaper.get_action_context()
  settings.remember_toggle_command(settings.ENGINE, command_id)
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

  local timing_on = settings.timing_log_on()
  local backstop_seconds = prefs.read("engine").backstop_ms / 1000
  local stats = timing.new(reaper.time_precise())

  refresh_toggle_states(switches, timing_on)

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
      local was_timing = timing_on
      timing_on = settings.timing_log_on()
      backstop_seconds = prefs.read("engine").backstop_ms / 1000
      if timing_on and not was_timing then
        stats = timing.new(now)
        log("timing log on; a summary follows every " .. timing.REPORT_SECONDS .. " s")
      end
      refresh_toggle_states(switches, timing_on)
      pending = true
    end

    -- Project: has anything changed that a rule could depend on?
    local current_project = reaper.EnumProjects(-1)
    local count = reaper.GetProjectStateChangeCount(current_project)
    if current_project ~= project or count ~= change_count or now >= next_backstop then
      project, change_count = current_project, count
      next_backstop = now + backstop_seconds
      local new_signature = watch.project_signature()
      if new_signature ~= signature then
        signature = new_signature
        pending = true
        watch.note_change(gate, now)
      end
    end

    watch.note_play_state(gate, now, math.tointeger(reaper.GetPlayState()) or 0)

    if pending and watch.may_run(gate, now) then
      pending = false
      local pass_start = reaper.time_precise()
      local changes = apply.run_pass(rules, switches, false)
      -- Take our own edits as the new baseline so they don't trigger a pass.
      signature = watch.project_signature()
      change_count = reaper.GetProjectStateChangeCount(current_project)
      if timing_on then
        timing.note_pass(stats, reaper.time_precise() - pass_start, changes)
      end
    end

    if timing_on then
      local done = reaper.time_precise()
      timing.note_tick(stats, done - now)
      if timing.due(stats, done) then
        log(timing.report(stats, done))
        stats = timing.new(done)
      end
    end

    reaper.defer(tick)
  end

  tick()
end

return M
