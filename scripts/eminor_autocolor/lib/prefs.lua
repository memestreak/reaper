-- lib/prefs.lua
--
-- The editor's Settings, following Jeremy's settings rules: each section is
-- saved under one key, every field has a default, and a parser checks each
-- field so a bad stored value can never break anything.
--
-- Saved in REAPER ExtState, section "eminor_autocolor", keys
-- "settings.<section>", as text such as "backstop_ms=500;settle_ms=150".
--
-- Sections:
--   engine      backstop_ms  fallback check interval while idle (100-5000)
--   appearance  thumb_size   icon thumbnail size in the editor, px (16-48)
-- Startup (start the engine with REAPER) is saved in __startup.lua itself;
-- see startup.lua.
--
-- The parsing is pure and tested outside REAPER.

local M = {}

M.SECTION = "eminor_autocolor"

M.FIELDS = {
  engine = {
    { key = "backstop_ms", label = "Fallback check every", unit = "ms",
      default = 500, min = 100, max = 5000,
      help = "How often the engine looks for changes REAPER doesn't report, such as rec-arm. Longer is cheaper; shorter notices sooner." },
  },
  appearance = {
    { key = "thumb_size", label = "Icon thumbnail size", unit = "px",
      default = 20, min = 16, max = 48,
      help = "Size of track icons in the rule list." },
  },
}

local function field(section, key)
  for _, f in ipairs(M.FIELDS[section]) do
    if f.key == key then return f end
  end
end

-- Parses a stored section. Missing or invalid fields take their defaults.
function M.parse(section, text)
  local values = {}
  for _, f in ipairs(M.FIELDS[section]) do values[f.key] = f.default end
  for key, raw in (text or ""):gmatch("([%w_]+)=([^;]*)") do
    local f = field(section, key)
    local number = tonumber(raw)
    if f and number and number >= f.min and number <= f.max then
      values[key] = math.floor(number + 0.5)
    end
  end
  return values
end

function M.format(section, values)
  local parts = {}
  for _, f in ipairs(M.FIELDS[section]) do
    parts[#parts + 1] = f.key .. "=" .. tostring(values[f.key])
  end
  return table.concat(parts, ";")
end

function M.defaults(section)
  return M.parse(section, "")
end

-- Needs REAPER from here on.
function M.read(section)
  return M.parse(section, reaper.GetExtState(M.SECTION, "settings." .. section))
end

function M.write(section, values)
  reaper.SetExtState(M.SECTION, "settings." .. section, M.format(section, values), true)
end

return M
