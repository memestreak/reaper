-- lib/colour.lua
--
-- Colour maths for eminor Auto Color. Pure Lua: nothing here calls REAPER,
-- so it can be tested outside REAPER.
--
-- Colours are plain integers in 0xRRGGBB form ("rgb" below). Converting to
-- REAPER's native, flagged track colour happens in apply.lua.

local M = {}


-- -----------------------------------------------------------------------------
-- Packing and parsing
-- -----------------------------------------------------------------------------

-- Splits 0xRRGGBB into three 0-255 components.
function M.unpack(rgb)
  return (rgb >> 16) & 0xFF, (rgb >> 8) & 0xFF, rgb & 0xFF
end

-- Joins three 0-255 components (rounded and clamped) into 0xRRGGBB.
function M.pack(r, g, b)
  local function byte(v)
    v = math.floor(v + 0.5)
    if v < 0 then return 0 end
    if v > 255 then return 255 end
    return v
  end
  return (byte(r) << 16) | (byte(g) << 8) | byte(b)
end

-- Parses "#RRGGBB" (the form used in the rules file) into 0xRRGGBB.
-- Returns nil for anything else.
function M.parse_hex(text)
  if type(text) ~= "string" then return nil end
  local hex = text:match("^#(%x%x%x%x%x%x)$")
  if not hex then return nil end
  return tonumber(hex, 16)
end

-- Formats 0xRRGGBB as "#RRGGBB".
function M.to_hex(rgb)
  return string.format("#%06X", rgb)
end


-- -----------------------------------------------------------------------------
-- HSL conversion (h in degrees 0-360, s and l in 0-1)
-- -----------------------------------------------------------------------------

function M.rgb_to_hsl(rgb)
  local r, g, b = M.unpack(rgb)
  r, g, b = r / 255, g / 255, b / 255
  local max, min = math.max(r, g, b), math.min(r, g, b)
  local l = (max + min) / 2
  if max == min then
    return 0, 0, l  -- a grey: hue and saturation are meaningless
  end
  local d = max - min
  local s = l > 0.5 and d / (2 - max - min) or d / (max + min)
  local h
  if max == r then
    h = (g - b) / d + (g < b and 6 or 0)
  elseif max == g then
    h = (b - r) / d + 2
  else
    h = (r - g) / d + 4
  end
  return h * 60, s, l
end

function M.hsl_to_rgb(h, s, l)
  h = (h % 360) / 360
  if s == 0 then
    return M.pack(l * 255, l * 255, l * 255)
  end
  local function hue_to_channel(p, q, t)
    if t < 0 then t = t + 1 end
    if t > 1 then t = t - 1 end
    if t < 1 / 6 then return p + (q - p) * 6 * t end
    if t < 1 / 2 then return q end
    if t < 2 / 3 then return p + (q - p) * (2 / 3 - t) * 6 end
    return p
  end
  local q = l < 0.5 and l * (1 + s) or l + s - l * s
  local p = 2 * l - q
  return M.pack(hue_to_channel(p, q, h + 1 / 3) * 255,
                hue_to_channel(p, q, h) * 255,
                hue_to_channel(p, q, h - 1 / 3) * 255)
end


-- -----------------------------------------------------------------------------
-- Gradient: the colour a fraction t (0-1) of the way from one colour to another
-- -----------------------------------------------------------------------------

function M.lerp(from_rgb, to_rgb, t)
  local r1, g1, b1 = M.unpack(from_rgb)
  local r2, g2, b2 = M.unpack(to_rgb)
  return M.pack(r1 + (r2 - r1) * t, g1 + (g2 - g1) * t, b1 + (b2 - b1) * t)
end

-- Colour of item `index` (1-based) out of `count` items spread over a
-- gradient. A single item takes the start colour, as in SWS.
function M.gradient(from_rgb, to_rgb, index, count)
  if count <= 1 then return from_rgb end
  return M.lerp(from_rgb, to_rgb, (index - 1) / (count - 1))
end


-- -----------------------------------------------------------------------------
-- Family colours: similar but different shades for repeated matches
-- -----------------------------------------------------------------------------

-- Van der Corput sequence in base 2: 0, 0.5, 0.25, 0.75, 0.125, ...
local function van_der_corput(n)
  local result, denominator = 0, 1
  while n > 0 do
    denominator = denominator * 2
    result = result + (n % 2) / denominator
    n = n // 2
  end
  return result
end

-- How far slot `slot` (0-based) sits from the base colour, from -1 to 1.
-- The sequence is 0, +1, -1, +0.5, -0.5, +0.75, -0.75, +0.25, -0.25, ...
-- so the first few slots are spread widely, every slot is different, and
-- adding a slot never moves the earlier ones.
function M.family_offset(slot)
  if slot == 0 then return 0 end
  local pair = (slot + 1) // 2  -- 1, 1, 2, 2, 3, 3, ...
  local magnitude = 1 - van_der_corput(pair - 1)
  if slot % 2 == 1 then
    return magnitude
  end
  return -magnitude
end

-- Colour for family slot `slot` (0-based).
--   family.base      0xRRGGBB centre colour
--   family.hue       how far hue may drift, in degrees either way
--   family.light     how far lightness may drift, 0-1 either way
--   family.palette   optional list of 0xRRGGBB; when present, slots cycle
--                    through it and base/hue/light are ignored
function M.family_colour(family, slot)
  if family.palette and #family.palette > 0 then
    return family.palette[(slot % #family.palette) + 1]
  end
  local t = M.family_offset(slot)
  local h, s, l = M.rgb_to_hsl(family.base)
  l = l + t * family.light
  if l < 0.05 then l = 0.05 end
  if l > 0.95 then l = 0.95 end
  return M.hsl_to_rgb(h + t * family.hue, s, l)
end


-- -----------------------------------------------------------------------------
-- "Random": a colour picked from an item's GUID, so it is chosen once and
-- stays the same every time without storing anything.
-- -----------------------------------------------------------------------------

-- FNV-1a string hash, kept to 32 bits.
local function hash(text)
  local h = 2166136261
  for i = 1, #text do
    h = ((h ~ text:byte(i)) * 16777619) & 0xFFFFFFFF
  end
  return h
end

function M.random_for(key)
  local h = hash(key)
  local hue = h % 360
  local saturation = 0.45 + ((h >> 9) % 30) / 100   -- 0.45-0.74
  local lightness = 0.42 + ((h >> 17) % 16) / 100   -- 0.42-0.57
  return M.hsl_to_rgb(hue, saturation, lightness)
end

return M
