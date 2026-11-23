-- lib/plan.lua
--
-- Works out which rule colours each track, marker or region, and with what
-- colour. Shared by apply_tracks.lua and apply_markers.lua. Pure Lua.
--
-- Within a target the first enabled rule that matches and sets a colour
-- claims the item. Rules whose colour mode is "ignore" are skipped, so a
-- lower rule can still colour the item.

local colour = require("lib.colour")

local M = {}


-- Gives each item claimed by a family rule a slot. Items keep the slot they
-- had (unless forcing), so adding a match never reshuffles the others.
-- New matches take the lowest free slot, in order.
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

-- Plans colours for a list of items, in display order.
--   entries  list of { guid = ..., state = <state.parse result>, ... }
--   rules    clean rules for this target only
--   matches  function(rule, entry) -> true when the rule's filter matches
--   force    true to respread families
-- Sets on each claimed entry:
--   entry.rule  the claiming rule
--   entry.want  { rgb = 0xRRGGBB }, { clear = true } or { parent = true }
--   entry.slot  the family slot, for family rules
function M.plan_colours(entries, rules, matches, force)
  local by_rule, order = {}, {}
  for _, entry in ipairs(entries) do
    for _, rule in ipairs(rules) do
      if rule.enabled and rule.colour.mode ~= "ignore" and matches(rule, entry) then
        entry.rule = rule
        if not by_rule[rule] then
          by_rule[rule] = {}
          order[#order + 1] = rule
        end
        local list = by_rule[rule]
        list[#list + 1] = entry
        break
      end
    end
  end
  for _, rule in ipairs(order) do
    local entries_for_rule = by_rule[rule]
    local spec = rule.colour
    if spec.mode == "family" then
      assign_family_slots(entries_for_rule, rule, force)
    end
    for index, entry in ipairs(entries_for_rule) do
      if spec.mode == "fixed" then
        entry.want = { rgb = spec.rgb }
      elseif spec.mode == "gradient" then
        entry.want = { rgb = colour.gradient(spec.from, spec.to, index, #entries_for_rule) }
      elseif spec.mode == "family" then
        entry.want = { rgb = colour.family_colour(spec, entry.slot) }
      elseif spec.mode == "random" then
        entry.want = { rgb = colour.random_for(entry.guid) }
      elseif spec.mode == "none" then
        entry.want = { clear = true }
      elseif spec.mode == "parent" then
        entry.want = { parent = true }
      end
    end
  end
end

-- The first enabled rule that matches and has a non-empty `field`, or nil.
-- Used for icons and layouts, which are settled separately from colour.
function M.first_with(rules, field, matches, entry)
  for _, rule in ipairs(rules) do
    if rule.enabled and rule[field] ~= "" and matches(rule, entry) then
      return rule
    end
  end
  return nil
end

-- The set of rgb colours fixed rules in `rules` can give, as rgb -> true.
-- A colour found on an item this script has never seen counts as one it
-- set (for example under SWS) when it is in this set.
function M.fixed_colours(rules)
  local set = {}
  for _, rule in ipairs(rules) do
    if rule.enabled and rule.colour.mode == "fixed" then
      set[rule.colour.rgb] = true
    end
  end
  return set
end

-- Rules for one target, in order.
function M.rules_for(rules, target)
  local list = {}
  for _, rule in ipairs(rules) do
    if rule.target == target then list[#list + 1] = rule end
  end
  return list
end

return M
