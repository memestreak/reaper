-- lib/rules.lua
--
-- The rule list: reading, checking and writing the rules file.
--
-- The file is a Lua table kept in REAPER's Data folder (never in the repo):
--   <resource>/Data/eminor_autocolor/rules.lua
--
-- Example:
--   return {
--     version = 1,
--     rules = {
--       { id = "r1", target = "track", filter = "guitar",
--         colour = { mode = "fixed", rgb = "#BF0004" } },
--       { id = "r2", target = "region", filter = "verse",
--         colour = { mode = "family", base = "#8AC627", hue = 8, light = 0.12 } },
--     },
--     palettes = {
--       { name = "Song sections", colours = { "#EA8D20", "#8AC627" } },
--     },
--   }
--
-- Palettes are saved colour lists the editor offers in its colour popover.
-- A family rule copies a palette's colours into its own "palette" field,
-- so later edits to the saved palette don't change existing rules.
--
-- Rule fields:
--   id          unique text; generated when missing
--   enabled     true (default) or false
--   target      "track", "marker" or "region"
--   filter      name text (case-insensitive "contains"), or a special filter
--               such as "(folder)"; see match.lua
--   colour      see COLOUR MODES below; missing means "ignore"
--   icon        file name under Data/track_icons, or "" (tracks only)
--   tcp_layout  theme layout name, "(hide)" or "" (tracks only)
--   mcp_layout  theme layout name, "(hide)" or "" (tracks only)
--
-- COLOUR MODES
--   { mode = "fixed",    rgb = "#RRGGBB" }
--   { mode = "gradient", from = "#RRGGBB", to = "#RRGGBB" }
--   { mode = "family",   base = "#RRGGBB", hue = <degrees>, light = <0-1> }
--   { mode = "family",   palette = { "#RRGGBB", ... } }
--   { mode = "random" }   a stable colour picked from each item's GUID
--   { mode = "parent" }   the parent folder's colour (tracks only)
--   { mode = "none" }     clears the colour
--   { mode = "ignore" }   this rule leaves colour alone
--
-- Pure Lua apart from file_path(), so it can be tested outside REAPER.

local colour = require("lib.colour")

local M = {}

M.FORMAT_VERSION = 1
M.TARGETS = { track = true, marker = true, region = true }

local DEFAULT_FAMILY_HUE = 8      -- degrees either way
local DEFAULT_FAMILY_LIGHT = 0.12 -- lightness either way
local DEFAULT_GRADIENT_FROM = 0x3A6EA5
local DEFAULT_GRADIENT_TO = 0x8FC1E8


-- Where the rules file lives. Needs REAPER.
function M.file_path()
  local sep = package.config:sub(1, 1)
  return reaper.GetResourcePath() .. sep .. "Data" .. sep .. "eminor_autocolor"
      .. sep .. "rules.lua"
end


-- -----------------------------------------------------------------------------
-- Checking. Each check returns a clean value or nil plus a problem message.
-- Problems never stop the whole file loading: the bad rule is skipped and
-- the message reported.
-- -----------------------------------------------------------------------------

local function check_hex(value, what)
  local rgb = colour.parse_hex(value)
  if not rgb then
    return nil, string.format("%s must look like \"#RRGGBB\" (got %s)",
                              what, tostring(value))
  end
  return rgb
end

local function check_colour(spec)
  if spec == nil then
    return { mode = "ignore" }
  end
  if type(spec) ~= "table" then
    return nil, "colour must be a table such as { mode = \"fixed\", rgb = \"#BF0004\" }"
  end
  local mode = spec.mode
  if mode == "fixed" then
    local rgb, err = check_hex(spec.rgb, "colour.rgb")
    if not rgb then return nil, err end
    return { mode = mode, rgb = rgb }
  elseif mode == "gradient" then
    local from = spec.from == nil and DEFAULT_GRADIENT_FROM or check_hex(spec.from, "colour.from")
    local to = spec.to == nil and DEFAULT_GRADIENT_TO or check_hex(spec.to, "colour.to")
    if not from or not to then
      return nil, "colour.from and colour.to must look like \"#RRGGBB\""
    end
    return { mode = mode, from = from, to = to }
  elseif mode == "family" then
    if spec.palette ~= nil then
      if type(spec.palette) ~= "table" or #spec.palette == 0 then
        return nil, "colour.palette must be a list of \"#RRGGBB\" colours"
      end
      local palette = {}
      for i, value in ipairs(spec.palette) do
        local rgb, err = check_hex(value, "colour.palette[" .. i .. "]")
        if not rgb then return nil, err end
        palette[i] = rgb
      end
      return { mode = mode, palette = palette }
    end
    local base, err = check_hex(spec.base, "colour.base")
    if not base then return nil, err end
    local hue = tonumber(spec.hue) or DEFAULT_FAMILY_HUE
    local light = tonumber(spec.light) or DEFAULT_FAMILY_LIGHT
    return { mode = mode, base = base,
             hue = math.max(0, math.min(180, hue)),
             light = math.max(0, math.min(0.5, light)) }
  elseif mode == "random" or mode == "parent" or mode == "none"
      or mode == "ignore" then
    return { mode = mode }
  end
  return nil, "unknown colour mode " .. tostring(mode)
end

local function check_text(value, default)
  if value == nil then return default end
  if type(value) ~= "string" then return nil end
  return value
end

-- Returns a clean rule, or nil and a problem message.
function M.check_rule(raw)
  if type(raw) ~= "table" then
    return nil, "a rule must be a table"
  end
  local target = raw.target or "track"
  if not M.TARGETS[target] then
    return nil, "target must be \"track\", \"marker\" or \"region\" (got "
        .. tostring(target) .. ")"
  end
  if type(raw.filter) ~= "string" or raw.filter == "" then
    return nil, "filter must be non-empty text"
  end
  local spec, err = check_colour(raw.colour)
  if not spec then return nil, err end
  if spec.mode == "parent" and target ~= "track" then
    return nil, "colour mode \"parent\" only applies to tracks"
  end
  local icon = check_text(raw.icon, "")
  local tcp = check_text(raw.tcp_layout, "")
  local mcp = check_text(raw.mcp_layout, "")
  if not icon or not tcp or not mcp then
    return nil, "icon, tcp_layout and mcp_layout must be text"
  end
  return {
    id = type(raw.id) == "string" and raw.id ~= "" and raw.id or nil,
    enabled = raw.enabled ~= false,
    target = target,
    filter = raw.filter,
    colour = spec,
    icon = icon,
    tcp_layout = tcp,
    mcp_layout = mcp,
  }
end

-- Gives every rule a unique id, keeping the ones it already has.
function M.assign_ids(rules)
  local used = {}
  for _, rule in ipairs(rules) do
    if rule.id and not used[rule.id] then
      used[rule.id] = true
    else
      rule.id = nil
    end
  end
  local next_number = 1
  for _, rule in ipairs(rules) do
    if not rule.id then
      while used["r" .. next_number] do next_number = next_number + 1 end
      rule.id = "r" .. next_number
      used[rule.id] = true
    end
  end
end


-- -----------------------------------------------------------------------------
-- Parsing and writing
-- -----------------------------------------------------------------------------

-- Checks the optional palettes list. Returns clean palettes
-- ({ name = text, colours = { 0xRRGGBB, ... } }) and adds any problems.
local function check_palettes(raw, problems)
  local palettes = {}
  if raw == nil then return palettes end
  if type(raw) ~= "table" then
    problems[#problems + 1] = "palettes must be a list"
    return palettes
  end
  for i, item in ipairs(raw) do
    local ok = type(item) == "table" and type(item.name) == "string"
        and item.name ~= "" and type(item.colours) == "table"
    local colours = {}
    if ok then
      for j, value in ipairs(item.colours) do
        local rgb = colour.parse_hex(value)
        if not rgb then ok = false break end
        colours[j] = rgb
      end
    end
    if ok then
      palettes[#palettes + 1] = { name = item.name, colours = colours }
    else
      problems[#problems + 1] = string.format(
          "palette %d skipped: needs a name and a list of \"#RRGGBB\" colours", i)
    end
  end
  return palettes
end

-- Parses the text of a rules file.
-- Returns the list of clean rules, a list of problem messages, and the
-- list of saved palettes.
-- The file runs with no access to any functions, so it can hold data only.
function M.parse(text)
  local chunk, syntax_error = load(text, "rules.lua", "t", {})
  if not chunk then
    return {}, { "rules file has a syntax error: " .. syntax_error }
  end
  local ok, data = pcall(chunk)
  if not ok then
    return {}, { "rules file failed to load: " .. tostring(data) }
  end
  if type(data) ~= "table" or type(data.rules) ~= "table" then
    return {}, { "rules file must return a table with a \"rules\" list" }
  end
  local rules, problems = {}, {}
  local palettes = check_palettes(data.palettes, problems)
  for i, raw in ipairs(data.rules) do
    local rule, err = M.check_rule(raw)
    if rule then
      rules[#rules + 1] = rule
    else
      problems[#problems + 1] = string.format("rule %d skipped: %s", i, err)
    end
  end
  M.assign_ids(rules)
  return rules, problems, palettes
end

local function quote(text)
  return string.format("%q", text)
end

local function format_colour(spec)
  local hex = colour.to_hex
  if spec.mode == "fixed" then
    return string.format("{ mode = \"fixed\", rgb = \"%s\" }", hex(spec.rgb))
  elseif spec.mode == "gradient" then
    return string.format("{ mode = \"gradient\", from = \"%s\", to = \"%s\" }",
                         hex(spec.from), hex(spec.to))
  elseif spec.mode == "family" and spec.palette then
    local items = {}
    for i, rgb in ipairs(spec.palette) do items[i] = quote(hex(rgb)) end
    return "{ mode = \"family\", palette = { " .. table.concat(items, ", ") .. " } }"
  elseif spec.mode == "family" then
    return string.format("{ mode = \"family\", base = \"%s\", hue = %g, light = %g }",
                         hex(spec.base), spec.hue, spec.light)
  end
  return string.format("{ mode = %s }", quote(spec.mode))
end

-- Turns clean rules (and saved palettes, if any) back into file text.
-- Fields come out in a fixed order so the file diffs well.
function M.serialize(rules, palettes)
  local lines = {
    "-- Eminor Auto Color rules. Rules are checked top to bottom within each",
    "-- target (track, marker, region); the first match wins.",
    "return {",
    "  version = " .. M.FORMAT_VERSION .. ",",
    "  rules = {",
  }
  for _, rule in ipairs(rules) do
    local parts = {
      "id = " .. quote(rule.id),
      "target = " .. quote(rule.target),
      "filter = " .. quote(rule.filter),
      "colour = " .. format_colour(rule.colour),
    }
    if not rule.enabled then table.insert(parts, 2, "enabled = false") end
    if rule.icon ~= "" then parts[#parts + 1] = "icon = " .. quote(rule.icon) end
    if rule.tcp_layout ~= "" then parts[#parts + 1] = "tcp_layout = " .. quote(rule.tcp_layout) end
    if rule.mcp_layout ~= "" then parts[#parts + 1] = "mcp_layout = " .. quote(rule.mcp_layout) end
    lines[#lines + 1] = "    { " .. table.concat(parts, ", ") .. " },"
  end
  lines[#lines + 1] = "  },"
  if palettes and #palettes > 0 then
    lines[#lines + 1] = "  palettes = {"
    for _, palette in ipairs(palettes) do
      local items = {}
      for i, rgb in ipairs(palette.colours) do items[i] = quote(colour.to_hex(rgb)) end
      lines[#lines + 1] = string.format("    { name = %s, colours = { %s } },",
          quote(palette.name), table.concat(items, ", "))
    end
    lines[#lines + 1] = "  },"
  end
  lines[#lines + 1] = "}"
  return table.concat(lines, "\n") .. "\n"
end


-- -----------------------------------------------------------------------------
-- File access
-- -----------------------------------------------------------------------------

function M.read_file(path)
  local file = io.open(path, "r")
  if not file then return nil end
  local text = file:read("a")
  file:close()
  return text
end

-- Writes through a temporary file, then renames it, so a reader never sees
-- a half-written file.
function M.write_file(path, text)
  local temp = path .. ".tmp"
  local file, err = io.open(temp, "w")
  if not file then return false, err end
  file:write(text)
  file:close()
  os.remove(path)
  local ok, rename_err = os.rename(temp, path)
  if not ok then return false, rename_err end
  return true
end

return M
