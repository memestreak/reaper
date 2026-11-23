-- lib/apply_markers.lua
--
-- Applies marker and region rules (colour only; they have no icon or
-- layout). Markers and regions are separate targets: a "marker" rule never
-- colours a region.
--
-- SWS recoloured every matching marker on every pass, so a colour you set
-- by hand on one never lasted. This script keeps them, as it does for
-- tracks:
--   * What it last set on each marker or region is stored in the project,
--     in project ExtState section "eminor_autocolor", under the key
--     "m:<marker GUID>" (see state.lua for the value).
--   * It only changes a colour that is still the one it set.
--   * A marker or region it has never seen is taken over when a rule
--     matches it, because under SWS any colour on it came from SWS.
--
-- Clearing a colour: REAPER's API treats colour 0 as "leave unchanged" in
-- some versions, so after asking for 0 the script reads the colour back
-- and, if it is still set, uses the theme's default marker or region
-- colour instead, as SWS did. Both count as "no colour".

local match = require("lib.match")
local plan = require("lib.plan")
local state_text = require("lib.state")
local tracks = require("lib.apply_tracks")

local M = {}

M.SECTION = "eminor_autocolor"
M.KEY_PREFIX = "m:"

local ACTIVE_PROJECT = 0
local COLOUR_SET_FLAG = 0x1000000
local NO_COLOUR = 0


-- -----------------------------------------------------------------------------
-- Reading and writing markers
-- -----------------------------------------------------------------------------

local function read_marker(index)
  local retval, is_region, pos, region_end, name, number, colour =
      reaper.EnumProjectMarkers3(ACTIVE_PROJECT, index)
  if retval == 0 then return nil end
  return {
    index = index, is_region = is_region, pos = pos, region_end = region_end,
    name = name or "", number = number,
    colour = math.tointeger(colour) or 0,
  }
end

local function marker_guid(marker)
  local ok, guid = reaper.GetSetProjectInfo_String(ACTIVE_PROJECT,
      "MARKER_GUID:" .. marker.index, "", false)
  if ok and guid and guid ~= "" then return guid end
  -- Without a GUID, fall back to the number shown in the ruler.
  return (marker.is_region and "R" or "M") .. tostring(marker.number)
end

local function read_state(guid)
  local _, text = reaper.GetProjExtState(ACTIVE_PROJECT, M.SECTION, M.KEY_PREFIX .. guid)
  return state_text.parse(text)
end

local function collect_markers()
  local entries = {}
  local index = 0
  while true do
    local marker = read_marker(index)
    if not marker then break end
    marker.guid = marker_guid(marker)
    marker.info = { name = marker.name }
    marker.state = read_state(marker.guid)
    marker.next = {}
    for k, v in pairs(marker.state) do marker.next[k] = v end
    entries[#entries + 1] = marker
    index = index + 1
  end
  return entries
end

local function set_colour(marker, value)
  reaper.SetProjectMarkerByIndex2(ACTIVE_PROJECT, marker.index, marker.is_region,
      marker.pos, marker.region_end, marker.number, marker.name, value, 0)
end

-- The theme's default colours, as flagged native values.
local function theme_defaults()
  local function flagged(name)
    local value = reaper.GetThemeColor(name, 0)
    if not value or value < 0 then return nil end
    return value | COLOUR_SET_FLAG
  end
  return { marker = flagged("marker"), region = flagged("region") }
end

local function is_cleared(value, marker, defaults)
  if value == NO_COLOUR then return true end
  local default = marker.is_region and defaults.region or defaults.marker
  return default ~= nil and value == default
end

local function same_colour(a, b, marker, defaults)
  if a == b then return true end
  return is_cleared(a, marker, defaults) and is_cleared(b, marker, defaults)
end

-- Clears a marker's colour. Returns the colour it has afterwards.
local function clear_colour(marker, defaults)
  set_colour(marker, NO_COLOUR)
  local after = read_marker(marker.index)
  local now = after and after.colour or NO_COLOUR
  if now ~= NO_COLOUR then
    local default = marker.is_region and defaults.region or defaults.marker
    if default then
      set_colour(marker, default)
      now = default
    end
  end
  return now
end


-- -----------------------------------------------------------------------------
-- The pass
-- -----------------------------------------------------------------------------

local function marker_matches(rule, entry)
  return match.marker_matches(rule.filter, entry.info)
end

local function apply_colours(entries, rules, force, defaults)
  plan.plan_colours(entries, rules, marker_matches, force)
  local changed = 0
  for _, entry in ipairs(entries) do
    local state, current = entry.state, entry.colour
    if entry.rule then
      local wanted = entry.want.clear and NO_COLOUR or tracks.to_native(entry.want.rgb)
      local first_sight = state.c == nil
      local ours = first_sight or same_colour(current, state.c, entry, defaults)
      if (force or ours) and not same_colour(current, wanted, entry, defaults) then
        if wanted == NO_COLOUR then
          clear_colour(entry, defaults)
        else
          set_colour(entry, wanted)
        end
        changed = changed + 1
      end
      entry.next.c, entry.next.r, entry.next.s = wanted, entry.rule.id, entry.slot
    else
      if state.c and not is_cleared(state.c, entry, defaults) and current == state.c then
        clear_colour(entry, defaults)
        changed = changed + 1
      end
      entry.next.c, entry.next.r, entry.next.s = nil, nil, nil
    end
  end
  return changed
end

-- Deletes remembered state for markers and regions that no longer exist.
local function prune_state(entries)
  local present = {}
  for _, entry in ipairs(entries) do present[M.KEY_PREFIX .. entry.guid] = true end
  local stale = {}
  local index = 0
  while true do
    local ok, key = reaper.EnumProjExtState(ACTIVE_PROJECT, M.SECTION, index)
    if not ok then break end
    if key:sub(1, #M.KEY_PREFIX) == M.KEY_PREFIX and not present[key] then
      stale[#stale + 1] = key
    end
    index = index + 1
  end
  for _, key in ipairs(stale) do
    reaper.SetProjExtState(ACTIVE_PROJECT, M.SECTION, key, "")
  end
end

-- Runs one pass over all markers and regions.
--   all_rules  clean rule list; only marker and region rules are used
--   switches   marker_colour, region_colour
--   force      true to overwrite hand-made changes and respread families
-- Returns the number of colours changed.
function M.run(all_rules, switches, force)
  if not (switches.marker_colour or switches.region_colour) then return 0 end
  local all = collect_markers()
  local markers, regions = {}, {}
  for _, entry in ipairs(all) do
    local list = entry.is_region and regions or markers
    list[#list + 1] = entry
  end

  local defaults = theme_defaults()
  local changed = 0
  if switches.marker_colour then
    changed = changed + apply_colours(markers, plan.rules_for(all_rules, "marker"), force, defaults)
  end
  if switches.region_colour then
    changed = changed + apply_colours(regions, plan.rules_for(all_rules, "region"), force, defaults)
  end

  for _, entry in ipairs(all) do
    local text = state_text.format(entry.next)
    if text ~= state_text.format(entry.state) then
      reaper.SetProjExtState(ACTIVE_PROJECT, M.SECTION, M.KEY_PREFIX .. entry.guid, text)
    end
  end
  prune_state(all)
  return changed
end

return M
