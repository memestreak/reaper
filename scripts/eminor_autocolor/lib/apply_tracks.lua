-- lib/apply_tracks.lua
--
-- Applies track rules: colour, icon, and TCP/MCP layout. Each of the three
-- is settled separately, as in SWS: the first matching rule that sets a
-- colour gives the colour, the first that names an icon gives the icon,
-- and so on.
--
-- How it treats your own changes (the same as SWS):
--   * Each track remembers what this script last set on it, in the track's
--     P_EXT:eminor_autocolor value (see state.lua), which saves with the
--     project.
--   * The script only changes something if it is still what it set last
--     time (or was never set). Changes you make by hand are left alone,
--     unless this is a Force pass.
--   * When no rule claims a track any more, what this script set is
--     undone, but only if it is still there.
--
-- One addition: a track this script has never seen, whose colour is
-- exactly one a fixed rule gives, is treated as coloured by this script.
-- That takes over colours SWS set before the switch.

local colour = require("lib.colour")
local match = require("lib.match")
local plan = require("lib.plan")
local state_text = require("lib.state")

local M = {}

M.STATE_KEY = "P_EXT:eminor_autocolor"
M.HIDE = "(hide)"

local ACTIVE_PROJECT = 0
local COLOUR_SET_FLAG = 0x1000000   -- set on I_CUSTOMCOLOR when a colour is in use
local NO_COLOUR = 0

local PANELS = {
  { field = "tcp_layout", layout_key = "P_TCP_LAYOUT", show_key = "B_SHOWINTCP",
    state_key = "t", hidden_bit = state_text.HIDDEN_TCP },
  { field = "mcp_layout", layout_key = "P_MCP_LAYOUT", show_key = "B_SHOWINMIXER",
    state_key = "m", hidden_bit = state_text.HIDDEN_MCP },
}


-- -----------------------------------------------------------------------------
-- Helpers
-- -----------------------------------------------------------------------------

local function same_text(a, b)
  return (a or ""):lower() == (b or ""):lower()
end

local function get_string(track, key)
  local _, value = reaper.GetSetMediaTrackInfo_String(track, key, "", false)
  return value or ""
end

local function set_string(track, key, value)
  reaper.GetSetMediaTrackInfo_String(track, key, value, true)
end

-- The track's current colour as a native value with the "set" flag, or 0.
local function current_colour(track)
  local value = math.tointeger(reaper.GetMediaTrackInfo_Value(track, "I_CUSTOMCOLOR")) or 0
  if value & COLOUR_SET_FLAG == 0 then
    return NO_COLOUR
  end
  return value
end

-- 0xRRGGBB to REAPER's native colour, with the "set" flag.
function M.to_native(rgb)
  local r, g, b = colour.unpack(rgb)
  return reaper.ColorToNative(r, g, b) | COLOUR_SET_FLAG
end

local function copy(t)
  local c = {}
  for k, v in pairs(t) do c[k] = v end
  return c
end


-- -----------------------------------------------------------------------------
-- Icons. Rules name an icon relative to <resource>/Data/track_icons, as
-- SWS does; REAPER is given the full path.
-- -----------------------------------------------------------------------------

local function icon_folder()
  local sep = package.config:sub(1, 1)
  return reaper.GetResourcePath() .. sep .. "Data" .. sep .. "track_icons" .. sep
end

local function is_absolute(path)
  return path:sub(1, 1) == "/" or path:sub(1, 1) == "\\" or path:match("^%a:") ~= nil
end

-- A full icon path as a name relative to the icon folder, when it is inside it.
local function short_icon(path, folder)
  if path:sub(1, #folder):lower() == folder:lower() then
    return path:sub(#folder + 1)
  end
  return path
end

local function full_icon(name, folder)
  if is_absolute(name) then return name end
  return folder .. name
end


-- -----------------------------------------------------------------------------
-- Gathering tracks
-- -----------------------------------------------------------------------------

-- Every track in project order, master first, with what the pass needs.
local function collect_tracks()
  local tracks = {}
  local master = reaper.GetMasterTrack(ACTIVE_PROJECT)
  tracks[1] = { track = master, is_master = true, info = match.track_info(master, true) }
  for i = 0, reaper.CountTracks(ACTIVE_PROJECT) - 1 do
    local track = reaper.GetTrack(ACTIVE_PROJECT, i)
    tracks[#tracks + 1] = { track = track, is_master = false, info = match.track_info(track, false) }
  end
  for _, entry in ipairs(tracks) do
    entry.guid = reaper.GetTrackGUID(entry.track)
    entry.state = state_text.parse(get_string(entry.track, M.STATE_KEY))
    entry.next = copy(entry.state)  -- what will be remembered after this pass
  end
  return tracks
end

local function track_matches(rule, entry)
  return match.track_matches(rule.filter, entry.info)
end


-- -----------------------------------------------------------------------------
-- Colour
-- -----------------------------------------------------------------------------

local function apply_colours(tracks, rules, force)
  plan.plan_colours(tracks, rules, track_matches, force)

  local adoptable = {}
  for rgb in pairs(plan.fixed_colours(rules)) do adoptable[M.to_native(rgb)] = true end

  local final_colour = {}  -- track -> colour after this pass, for "parent"
  local changed = 0

  for _, entry in ipairs(tracks) do
    local track, state, next_state = entry.track, entry.state, entry.next
    local current = current_colour(track)

    if entry.rule then
      local wanted
      if entry.want.parent then
        local parent = reaper.GetParentTrack(track)
        local parent_colour = parent and (final_colour[parent] or current_colour(parent)) or NO_COLOUR
        -- A parent without a colour gives nothing to copy: leave this track
        -- and its remembered colour as they are.
        wanted = parent_colour ~= NO_COLOUR and parent_colour or nil
      elseif entry.want.clear then
        wanted = NO_COLOUR
      else
        wanted = M.to_native(entry.want.rgb)
      end

      if wanted ~= nil then
        local first_sight = state.c == nil
        local ours = current == (state.c or NO_COLOUR)
            or (first_sight and adoptable[current])
        if (force or ours) and wanted ~= current then
          reaper.SetMediaTrackInfo_Value(track, "I_CUSTOMCOLOR", wanted)
          current = wanted
          changed = changed + 1
        end
        next_state.c, next_state.r, next_state.s = wanted, entry.rule.id, entry.slot
      end
    else
      -- No rule claims this track: undo our colour if it is still ours.
      if state.c and state.c ~= NO_COLOUR and current == state.c then
        reaper.SetMediaTrackInfo_Value(track, "I_CUSTOMCOLOR", NO_COLOUR)
        current = NO_COLOUR
        changed = changed + 1
      end
      next_state.c, next_state.r, next_state.s = nil, nil, nil
    end

    final_colour[track] = current
  end
  return changed
end


-- -----------------------------------------------------------------------------
-- Icon
-- -----------------------------------------------------------------------------

local function apply_icons(tracks, rules, force)
  local folder = icon_folder()
  local changed = 0
  for _, entry in ipairs(tracks) do
    local track, state = entry.track, entry.state
    local current = short_icon(get_string(track, "P_ICON"), folder)
    local rule = plan.first_with(rules, "icon", track_matches, entry)
    if rule then
      local ours = same_text(current, state.i)
      if (force or ours) and not same_text(current, rule.icon) then
        set_string(track, "P_ICON", full_icon(rule.icon, folder))
        changed = changed + 1
      end
      entry.next.i = rule.icon
    else
      if state.i and state.i ~= "" and same_text(current, state.i) then
        set_string(track, "P_ICON", "")
        changed = changed + 1
      end
      entry.next.i = nil
    end
  end
  return changed
end


-- -----------------------------------------------------------------------------
-- Layouts. A layout of "(hide)" hides the track in that panel instead.
-- -----------------------------------------------------------------------------

local function apply_layout_name(entry, panel, wanted, force)
  local track, state = entry.track, entry.state
  local current = get_string(track, panel.layout_key)
  local last_set = state[panel.state_key]
  if wanted then
    local ours = same_text(current, last_set)
    entry.next[panel.state_key] = wanted
    if (force or ours) and not same_text(current, wanted) then
      set_string(track, panel.layout_key, wanted)
      return 1
    end
  else
    entry.next[panel.state_key] = nil
    if last_set and last_set ~= "" and same_text(current, last_set) then
      set_string(track, panel.layout_key, "")
      return 1
    end
  end
  return 0
end

local function apply_hide(entry, panel, hide, force)
  if entry.is_master then return 0 end  -- the master has its own visibility setting
  local track = entry.track
  local visible = reaper.GetMediaTrackInfo_Value(track, panel.show_key) ~= 0
  local hidden_bits = entry.next.h or 0
  local we_hid = (entry.state.h or 0) & panel.hidden_bit ~= 0
  local changed = 0
  if hide then
    -- Ours when it is as we left it: hidden if we hid it, else visible.
    local ours = visible ~= we_hid
    if force or ours then
      if visible then
        reaper.SetMediaTrackInfo_Value(track, panel.show_key, 0)
        changed = 1
      end
      hidden_bits = hidden_bits | panel.hidden_bit
    end
  else
    if we_hid and not visible then
      reaper.SetMediaTrackInfo_Value(track, panel.show_key, 1)
      changed = 1
    end
    hidden_bits = hidden_bits & ~panel.hidden_bit
  end
  entry.next.h = hidden_bits ~= 0 and hidden_bits or nil
  return changed
end

local function apply_layouts(tracks, rules, force)
  local changed = 0
  for _, entry in ipairs(tracks) do
    for _, panel in ipairs(PANELS) do
      local rule = plan.first_with(rules, panel.field, track_matches, entry)
      local value = rule and rule[panel.field]
      local hide = value == M.HIDE
      changed = changed + apply_layout_name(entry, panel, (not hide) and value or nil, force)
      changed = changed + apply_hide(entry, panel, hide, force)
    end
  end
  return changed
end


-- -----------------------------------------------------------------------------
-- Entry point
-- -----------------------------------------------------------------------------

-- Runs one pass over all tracks.
--   all_rules  clean rule list (rules.parse); other targets are ignored
--   switches   which parts to apply: track_colour, track_icon, track_layout
--   force      true to overwrite hand-made changes and respread families
-- Returns the number of changes made.
function M.run(all_rules, switches, force)
  local rules = plan.rules_for(all_rules, "track")
  local tracks = collect_tracks()
  local changed = 0
  if switches.track_colour then changed = changed + apply_colours(tracks, rules, force) end
  if switches.track_icon then changed = changed + apply_icons(tracks, rules, force) end
  if switches.track_layout then changed = changed + apply_layouts(tracks, rules, force) end
  for _, entry in ipairs(tracks) do
    local text = state_text.format(entry.next)
    if text ~= state_text.format(entry.state) then
      set_string(entry.track, M.STATE_KEY, text)
    end
  end
  return changed
end

return M
