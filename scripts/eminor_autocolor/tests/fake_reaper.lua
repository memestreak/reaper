-- tests/fake_reaper.lua
--
-- A stand-in for the parts of REAPER's API that the apply and match
-- modules use, so their logic can be tested with plain Lua.
-- Tracks are plain tables; "native" colours are 0xRRGGBB, as on macOS.

local M = {}

M.RESOURCE = "/res"
M.ICONS = "/res/Data/track_icons/"
M.THEME_MARKER = 0x00AA00   -- the fake theme's default marker colour
M.THEME_REGION = 0x0000AA

-- Makes a fresh fake project and installs it as the global `reaper`.
-- `specs` lists tracks in order, each a table of track fields such as
-- { name = "Gtr", folder = 1, depth = 0, parent = 1 }.
-- `marker_specs` lists markers and regions in order, each like
-- { name = "Verse", region = true, colour = 0, guid = "{M1}" }.
-- `options.colour_zero_keeps` makes setting a marker colour to 0 leave it
-- unchanged, as some REAPER versions do.
function M.install(specs, marker_specs, options)
  options = options or {}
  local master = { name = "", guid = "{MASTER}", colour = 0, ext = {}, is_master = true,
                   icon = "", tcp_layout = "", mcp_layout = "", show_tcp = 1, show_mcp = 1 }
  local tracks = {}
  for i, spec in ipairs(specs or {}) do
    tracks[i] = {
      name = spec.name or "",
      guid = spec.guid or string.format("{TRACK-%d}", i),
      colour = spec.colour or 0,
      folder = spec.folder or 0,
      depth = spec.depth or 0,
      parent_index = spec.parent,
      receives = spec.receives or 0,
      rec_arm = spec.rec_arm or 0,
      rec_input = spec.rec_input or -1,
      hw_outputs = spec.hw_outputs or 0,
      midi_hw_out = spec.midi_hw_out or -1,
      instrument = spec.instrument or -1,
      vca = spec.vca or 0,
      icon = spec.icon or "",
      tcp_layout = spec.tcp_layout or "",
      mcp_layout = spec.mcp_layout or "",
      show_tcp = spec.show_tcp or 1,
      show_mcp = spec.show_mcp or 1,
      ext = {},
    }
  end

  local markers = {}
  for i, spec in ipairs(marker_specs or {}) do
    markers[i] = {
      name = spec.name or "",
      is_region = spec.region or false,
      pos = spec.pos or i,
      region_end = spec.region and (spec.pos or i) + 0.5 or 0,
      number = spec.number or i,
      colour = spec.colour or 0,
      guid = spec.guid or string.format("{MARKER-%d}", i),
    }
  end

  local fake = { tracks = tracks, master = master, markers = markers, proj_ext = {},
                 writes = 0, marker_writes = 0, undo_blocks = 0 }

  function fake.GetMasterTrack() return master end
  function fake.CountTracks() return #tracks end
  function fake.GetTrack(_, i) return tracks[i + 1] end
  function fake.GetTrackGUID(t) return t.guid end
  function fake.GetTrackDepth(t) return t.depth end
  function fake.GetParentTrack(t) return t.parent_index and tracks[t.parent_index] or nil end
  function fake.GetTrackNumSends(t, category)
    if category == -1 then return t.receives end
    if category == 1 then return t.hw_outputs end
    return 0
  end
  function fake.TrackFX_GetInstrument(t) return t.instrument end
  function fake.GetSetTrackGroupMembership(t) return t.vca end
  function fake.GetSetTrackGroupMembershipHigh() return 0 end

  local values = {
    I_FOLDERDEPTH = "folder", I_RECARM = "rec_arm", I_RECINPUT = "rec_input",
    I_MIDIHWOUT = "midi_hw_out", I_CUSTOMCOLOR = "colour",
    B_SHOWINTCP = "show_tcp", B_SHOWINMIXER = "show_mcp",
  }
  local writable = { I_CUSTOMCOLOR = true, B_SHOWINTCP = true, B_SHOWINMIXER = true }
  function fake.GetMediaTrackInfo_Value(t, key)
    assert(values[key], "unexpected read of " .. key)
    return (t[values[key]] or 0) + 0.0  -- REAPER returns floats
  end
  function fake.SetMediaTrackInfo_Value(t, key, value)
    assert(writable[key], "unexpected write to " .. key)
    t[values[key]] = math.tointeger(value)
    fake.writes = fake.writes + 1
    return true
  end
  local strings = { P_NAME = "name", P_ICON = "icon", P_TCP_LAYOUT = "tcp_layout",
                    P_MCP_LAYOUT = "mcp_layout" }
  function fake.GetSetMediaTrackInfo_String(t, key, value, set)
    if strings[key] then
      if set then
        t[strings[key]] = value
        if key ~= "P_NAME" then fake.writes = fake.writes + 1 end
      end
      return true, t[strings[key]]
    end
    local ext = key:match("^P_EXT:(.+)$")
    assert(ext, "unexpected string key " .. key)
    if set then t.ext[ext] = value end
    return true, t.ext[ext] or ""
  end

  function fake.GetResourcePath() return M.RESOURCE end

  function fake.EnumProjectMarkers3(_, index)
    local m = markers[index + 1]
    if not m then return 0 end
    return index + 1, m.is_region, m.pos + 0.0, m.region_end + 0.0, m.name, m.number, m.colour
  end
  function fake.SetProjectMarkerByIndex2(_, index, is_region, pos, region_end, number, name, colour, flags)
    local m = assert(markers[index + 1], "no marker " .. index)
    assert(m.is_region == is_region and m.pos == pos and m.number == number and m.name == name,
           "marker fields changed")
    if not (colour == 0 and options.colour_zero_keeps) then
      m.colour = colour
    end
    fake.marker_writes = fake.marker_writes + 1
    return true
  end
  function fake.GetSetProjectInfo_String(_, key, value, set)
    local index = tonumber(key:match("^MARKER_GUID:(%d+)$"))
    assert(index and not set, "unexpected project string " .. key)
    local m = markers[index + 1]
    return m ~= nil, m and m.guid or ""
  end
  function fake.GetThemeColor(name)
    if name == "marker" then return M.THEME_MARKER end
    if name == "region" then return M.THEME_REGION end
    return -1
  end
  function fake.GetProjExtState(_, section, key)
    local value = (fake.proj_ext[section] or {})[key]
    return value and 1 or 0, value or ""
  end
  function fake.SetProjExtState(_, section, key, value)
    fake.proj_ext[section] = fake.proj_ext[section] or {}
    fake.proj_ext[section][key] = value ~= "" and value or nil
    return 1
  end
  function fake.EnumProjExtState(_, section, index)
    local keys = {}
    for key in pairs(fake.proj_ext[section] or {}) do keys[#keys + 1] = key end
    table.sort(keys)
    local key = keys[index + 1]
    if not key then return false, "", "" end
    return true, key, fake.proj_ext[section][key]
  end
  function fake.UpdateTimeline() end

  -- SWS's actions: fake.sws holds named command -> toggle state (0/1) when
  -- a test installs SWS; otherwise SWS is missing.
  fake.sws = nil
  fake.commands_run = {}
  local id_of, name_of, next_id = {}, {}, 50000
  -- Scripts added to the Action List: path -> named ID ("RS1", ...).
  fake.scripts = {}
  local script_ids, script_names, next_script_id = {}, {}, 90000
  function fake.AddRemoveReaScript(add, section, path, commit)
    assert(add and section == 0, "unexpected AddRemoveReaScript")
    if not fake.scripts[path] then
      next_script_id = next_script_id + 1
      local named = "_RS" .. next_script_id
      fake.scripts[path] = named
      script_ids[named], script_names[next_script_id] = next_script_id, named
    end
    return script_ids[fake.scripts[path]]
  end
  function fake.ReverseNamedCommandLookup(id)
    local named = script_names[id] or name_of[id]
    return named and named:sub(2) or nil
  end
  function fake.NamedCommandLookup(name)
    if script_ids[name] then return script_ids[name] end
    if not (fake.sws and fake.sws[name]) then return 0 end
    if not id_of[name] then
      id_of[name], name_of[next_id] = next_id, name
      next_id = next_id + 1
    end
    return id_of[name]
  end
  function fake.GetToggleCommandState(id)
    local name = name_of[id]
    return name and fake.sws[name] or -1
  end
  function fake.Main_OnCommand(id, flag)
    if script_names[id] then
      fake.commands_run[#fake.commands_run + 1] = script_names[id]
      return
    end
    local name = assert(name_of[id], "unknown command " .. tostring(id))
    fake.commands_run[#fake.commands_run + 1] = name
    fake.sws[name] = 1 - fake.sws[name]
  end

  function fake.ColorToNative(r, g, b) return (r << 16) | (g << 8) | b end
  function fake.PreventUIRefresh() end
  function fake.TrackList_AdjustWindows() end
  function fake.UpdateArrange() end
  function fake.Undo_BeginBlock2() fake.undo_blocks = fake.undo_blocks + 1 end
  function fake.Undo_EndBlock2() end

  _G.reaper = fake
  return fake
end

-- The flagged native colour REAPER would store for 0xRRGGBB.
function M.flagged(rgb)
  return rgb | 0x1000000
end

return M
