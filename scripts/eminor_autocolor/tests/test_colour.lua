local colour = require("lib.colour")

local T = {}

function T.hex_round_trip()
  assert(colour.parse_hex("#BF0004") == 0xBF0004)
  assert(colour.parse_hex("#bf0004") == 0xBF0004)
  assert(colour.parse_hex("BF0004") == nil)
  assert(colour.parse_hex("#BF00") == nil)
  assert(colour.to_hex(0x0F80FF) == "#0F80FF")
end

function T.hsl_round_trip_keeps_colours()
  for _, rgb in ipairs({ 0x8AC627, 0xEA8D20, 0x800040, 0x6666FF, 0x000000, 0xFFFFFF, 0x808080 }) do
    local h, s, l = colour.rgb_to_hsl(rgb)
    local back = colour.hsl_to_rgb(h, s, l)
    local r1, g1, b1 = colour.unpack(rgb)
    local r2, g2, b2 = colour.unpack(back)
    assert(math.abs(r1 - r2) <= 1 and math.abs(g1 - g2) <= 1 and math.abs(b1 - b2) <= 1,
           string.format("%06X came back as %06X", rgb, back))
  end
end

function T.gradient_ends_and_single_item()
  assert(colour.gradient(0x000000, 0xFFFFFF, 1, 3) == 0x000000)
  assert(colour.gradient(0x000000, 0xFFFFFF, 3, 3) == 0xFFFFFF)
  assert(colour.gradient(0x000000, 0xFFFFFF, 2, 3) == 0x808080)
  assert(colour.gradient(0x123456, 0xFFFFFF, 1, 1) == 0x123456)
end

function T.family_offsets_spread_and_never_repeat()
  local expected = { 0, 1, -1, 0.5, -0.5, 0.75, -0.75, 0.25, -0.25 }
  for slot, want in ipairs(expected) do
    assert(colour.family_offset(slot - 1) == want,
           string.format("slot %d gave %s", slot - 1, colour.family_offset(slot - 1)))
  end
  local seen = {}
  for slot = 0, 63 do
    local t = colour.family_offset(slot)
    assert(not seen[t], "offset repeated at slot " .. slot)
    assert(t >= -1 and t <= 1)
    seen[t] = true
  end
end

function T.family_first_slot_is_the_base_colour()
  local family = { base = 0x8AC627, hue = 8, light = 0.12 }
  assert(colour.family_colour(family, 0) == 0x8AC627)
end

function T.family_shades_are_similar_but_different()
  local family = { base = 0x8AC627, hue = 8, light = 0.12 }
  local seen = {}
  local base_h = colour.rgb_to_hsl(family.base)
  for slot = 0, 5 do
    local rgb = colour.family_colour(family, slot)
    assert(not seen[rgb], "slot " .. slot .. " repeats a colour")
    seen[rgb] = true
    local h = colour.rgb_to_hsl(rgb)
    assert(math.abs(h - base_h) <= 8.5, "hue drifted too far at slot " .. slot)
  end
end

function T.family_palette_cycles()
  local family = { palette = { 0x111111, 0x222222, 0x333333 } }
  assert(colour.family_colour(family, 0) == 0x111111)
  assert(colour.family_colour(family, 2) == 0x333333)
  assert(colour.family_colour(family, 3) == 0x111111)
end

function T.random_is_stable_per_key()
  assert(colour.random_for("{A}") == colour.random_for("{A}"))
  assert(colour.random_for("{A}") ~= colour.random_for("{B}"))
end

return T
