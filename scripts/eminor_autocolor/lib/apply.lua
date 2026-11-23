-- lib/apply.lua
--
-- Applies the rules to the current project. Phase 1 handles track colour;
-- icons, layouts, markers and regions follow in phase 2.
--
-- How a pass works (the same behaviour as SWS Auto Color):
--   * For each track, the first enabled track rule that matches and sets a
--     colour claims it. Rules whose colour mode is "ignore" are skipped.
--   * Each track remembers the colour this script last set on it, in the
--     track's P_EXT:eminor_autocolor value, which saves with the project.
--   * The script only changes a track's colour if it is still the one it
--     set last time (or the track had none). A colour you set by hand is
--     left alone, unless this is a Force pass.
--   * When no rule claims a track any more, its colour is cleared, but only
--     if it is still the one this script set.

local colour = require("lib.colour")
local match = require("lib.match")

local M = {}

M.STATE_KEY = "P_EXT:eminor_autocolor"

local ACTIVE_PROJECT = 0
local COLOUR_SET_FLAG = 0x1000000   -- set on I_CUSTOMCOLOR when a colour is in use
local NO_COLOUR = 0


-- -----------------------------------------------------------------------------
-- Remembered state, stored per track as text such as "c=16777215;r=r3;s=2":
--   c  the native colour value this script last set (0 = it cleared it)
--   r  id of the rule that set it
--   s  family slot, for "family" rules
-- -----------------------------------------------------------------------------

function M.parse_state(text)
  local state = {}
  for key, value in (text or ""):gmatch("(%a)=([^;]*)") do
    if key == "c" or key == "s" then
      state[key] = math.tointeger(tonumber(value))
    elseif key == "r" then
      state.r = value
    end
  end
  return state
end

function M.format_state(state)
  if state.c == nil then return "" end
  local parts = { "c=" .. state.c }
  if state.r then parts[#parts + 1] = "r=" .. state.r end
  if state.s then parts[#parts + 1] = "s=" .. state.s end
  return table.concat(parts, ";")
end

local function read_state(track)
  local _, text = reaper.GetSetMediaTrackInfo_String(track, M.STATE_KEY, "", false)
  return M.parse_state(text)
end

local function write_state(track, state)
  reaper.GetSetMediaTrackInfo_String(track, M.STATE_KEY, M.format_state(state), true)
end


-- -----------------------------------------------------------------------------
-- Colours
-- -----------------------------------------------------------------------------

-- The track's current colour as a native value with the "set" flag, or 0.
local function current_colour(track)
  local value = math.tointeger(reaper.GetMediaTrackInfo_Value(track, "I_CUSTOMCOLOR")) or 0
  if value & COLOUR_SET_FLAG == 0 then
    return NO_COLOUR
  end
  return value
end

-- 0xRRGGBB to REAPER's native track colour, with the "set" flag.
local function to_native(rgb)
  local r, g, b = colour.unpack(rgb)
  return reaper.ColorToNative(r, g, b) | COLOUR_SET_FLAG
end


-- -----------------------------------------------------------------------------
-- The pass
-- -----------------------------------------------------------------------------

-- Every track in project order, master first, with what the pass needs.
local function collect_tracks()
  local tracks = {}
  local master = reaper.GetMasterTrack(ACTIVE_PROJECT)
  tracks[1] = { track = master, info = match.track_info(master, true) }
  for i = 0, reaper.CountTracks(ACTIVE_PROJECT) - 1 do
    local track = reaper.GetTrack(ACTIVE_PROJECT, i)
    tracks[#tracks + 1] = { track = track, info = match.track_info(track, false) }
  end
  for _, entry in ipairs(tracks) do
    entry.guid = reaper.GetTrackGUID(entry.track)
    entry.state = read_state(entry.track)
  end
  return tracks
end

-- The first enabled track rule that matches and sets a colour, or nil.
local function claiming_rule(rules, info)
  for _, rule in ipairs(rules) do
    if rule.enabled and rule.target == "track" and rule.colour.mode ~= "ignore"
        and match.track_matches(rule.filter, info) then
      return rule
    end
  end
  return nil
end

-- Gives each track claimed by a family rule a slot. Tracks keep the slot
-- they had (unless forcing), so adding a match never reshuffles the others.
-- New matches take the lowest free slot, in track order.
local function assign_family_slots(entries, rule, force)
  local taken = {}
  for _, entry in ipairs(entries) do
    local old = entry.state
    if not force and old.r == rule.id and old.s and not taken[old.s] then
      entry.slot = old.s
      taken[old.s] = true
    end
  end
  local next_free = 0
  for _, entry in ipairs(entries) do
    if not entry.slot then
      while taken[next_free] do next_free = next_free + 1 end
      entry.slot = next_free
      taken[next_free] = true
    end
  end
end

-- Works out the wanted native colour for every claimed track.
-- Parent mode is resolved later, during writing, because it depends on the
-- parent's final colour.
local function plan_colours(tracks, rules, force)
  local by_rule = {}
  for _, entry in ipairs(tracks) do
    entry.rule = claiming_rule(rules, entry.info)
    if entry.rule then
      local list = by_rule[entry.rule] or {}
      list[#list + 1] = entry
      by_rule[entry.rule] = list
    end
  end
  for rule, entries in pairs(by_rule) do
    local spec = rule.colour
    if spec.mode == "family" then
      assign_family_slots(entries, rule, force)
    end
    for index, entry in ipairs(entries) do
      if spec.mode == "fixed" then
        entry.wanted = to_native(spec.rgb)
      elseif spec.mode == "gradient" then
        entry.wanted = to_native(colour.gradient(spec.from, spec.to, index, #entries))
      elseif spec.mode == "family" then
        entry.wanted = to_native(colour.family_colour(spec, entry.slot))
      elseif spec.mode == "random" then
        entry.wanted = to_native(colour.random_for(entry.guid))
      elseif spec.mode == "none" then
        entry.wanted = NO_COLOUR
      end
      -- "parent": entry.wanted stays nil and is resolved while writing.
    end
  end
end

-- Runs one pass over all tracks.
--   rules   clean rule list (rules.parse)
--   force   true to overwrite hand-made changes and respread families
-- Returns the number of tracks whose colour changed.
function M.apply_track_colours(rules, force)
  local tracks = collect_tracks()
  plan_colours(tracks, rules, force)

  local final_colour = {}  -- track -> colour after this pass, for "parent"
  local changed = 0

  for _, entry in ipairs(tracks) do
    local track, state = entry.track, entry.state
    local current = current_colour(track)
    local last_set = (not force and state.c) or NO_COLOUR
    local new_state

    if entry.rule then
      local wanted = entry.wanted
      if entry.rule.colour.mode == "parent" then
        local parent = reaper.GetParentTrack(track)
        local parent_colour = parent and (final_colour[parent] or current_colour(parent)) or NO_COLOUR
        -- A parent without a colour gives nothing to copy: leave this track
        -- and its remembered state as they are.
        wanted = parent_colour ~= NO_COLOUR and parent_colour or nil
      end
      if wanted == nil then
        new_state = state
      else
        local untouched_by_hand = force or current == last_set
        if untouched_by_hand and wanted ~= current then
          reaper.SetMediaTrackInfo_Value(track, "I_CUSTOMCOLOR", wanted)
          current = wanted
          changed = changed + 1
        end
        new_state = { c = wanted, r = entry.rule.id, s = entry.slot }
      end
    else
      -- No rule claims this track: undo our colour if it is still ours.
      if state.c and state.c ~= NO_COLOUR and current == state.c then
        reaper.SetMediaTrackInfo_Value(track, "I_CUSTOMCOLOR", NO_COLOUR)
        current = NO_COLOUR
        changed = changed + 1
      end
      new_state = {}
    end

    final_colour[track] = current
    if M.format_state(new_state) ~= M.format_state(state) then
      write_state(track, new_state)
    end
  end
  return changed
end


-- -----------------------------------------------------------------------------
-- Entry points
-- -----------------------------------------------------------------------------

-- One pass, as the engine runs it: no undo point.
--   switches  settings.read_switches() result
function M.run_pass(rules, switches, force)
  if not (switches.track_colour or force) then
    return 0
  end
  reaper.PreventUIRefresh(1)
  local changed = M.apply_track_colours(rules, force)
  reaper.PreventUIRefresh(-1)
  if changed > 0 then
    reaper.TrackList_AdjustWindows(false)
    reaper.UpdateArrange()
  end
  return changed
end

-- Force: reapplies every rule, overwriting hand-made changes, with one
-- undo point. Runs whatever the on/off switches say, as in SWS.
function M.force(rules)
  local UNDO_STATE_TRACKCFG = 1
  reaper.Undo_BeginBlock2(ACTIVE_PROJECT)
  local changed = M.run_pass(rules, { track_colour = true }, true)
  reaper.Undo_EndBlock2(ACTIVE_PROJECT, "Apply auto color/icon/layout", UNDO_STATE_TRACKCFG)
  return changed
end

return M
