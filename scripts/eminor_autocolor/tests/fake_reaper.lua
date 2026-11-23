-- tests/fake_reaper.lua
--
-- A stand-in for the parts of REAPER's API that lib/apply.lua and
-- lib/match.lua use, so their logic can be tested with plain Lua.
-- Tracks are plain tables; "native" colours are 0xRRGGBB, as on macOS.

local M = {}

-- Makes a fresh fake project and installs it as the global `reaper`.
-- `specs` lists tracks in order, each a table of track fields such as
-- { name = "Gtr", folder = 1, depth = 0, parent = 1 }.
function M.install(specs)
  local master = { name = "", guid = "{MASTER}", colour = 0, ext = {}, is_master = true }
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
      ext = {},
    }
  end

  local fake = { tracks = tracks, master = master, writes = 0, undo_blocks = 0 }

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
  }
  function fake.GetMediaTrackInfo_Value(t, key)
    return (t[values[key]] or 0) + 0.0  -- REAPER returns floats
  end
  function fake.SetMediaTrackInfo_Value(t, key, value)
    assert(key == "I_CUSTOMCOLOR", "unexpected write to " .. key)
    t.colour = math.tointeger(value)
    fake.writes = fake.writes + 1
    return true
  end
  function fake.GetSetMediaTrackInfo_String(t, key, value, set)
    if key == "P_NAME" then
      if set then t.name = value end
      return true, t.name
    end
    local ext = key:match("^P_EXT:(.+)$")
    assert(ext, "unexpected string key " .. key)
    if set then t.ext[ext] = value end
    return true, t.ext[ext] or ""
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
