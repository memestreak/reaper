-- lib/editor_model.lua
--
-- The editor's document: the rule list and saved palettes, the edits the
-- editor makes to them, and undo/redo. Pure Lua: tested outside REAPER.
--
-- Every edit goes through model:edit(), which keeps a snapshot for undo.
-- The editor saves the file after each edit, so rule changes apply at once.

local rules_module = require("lib.rules")
local match = require("lib.match")

local M = {}

M.UNDO_LIMIT = 100
M.TARGETS = { "track", "region", "marker" }   -- display order of the groups
M.DEFAULT_COLOUR = 0x4080C2

local Model = {}
Model.__index = Model

local function deep_copy(value)
  if type(value) ~= "table" then return value end
  local copy = {}
  for k, v in pairs(value) do copy[k] = deep_copy(v) end
  return copy
end

function M.new(rules, palettes)
  return setmetatable({
    doc = { rules = rules or {}, palettes = palettes or {} },
    undo_stack = {}, redo_stack = {},
  }, Model)
end

function Model:text()
  return rules_module.serialize(self.doc.rules, self.doc.palettes)
end

-- Applies `change(doc)` as one undoable step. `label` names it for the
-- Undo menu item ("Undo Delete rule").
function Model:edit(label, change)
  local before = deep_copy(self.doc)
  change(self.doc)
  rules_module.assign_ids(self.doc.rules)
  self.undo_stack[#self.undo_stack + 1] = { label = label, doc = before }
  if #self.undo_stack > M.UNDO_LIMIT then table.remove(self.undo_stack, 1) end
  self.redo_stack = {}
end

function Model:can_undo() return #self.undo_stack > 0 end
function Model:can_redo() return #self.redo_stack > 0 end

function Model:undo_label()
  local top = self.undo_stack[#self.undo_stack]
  return top and top.label
end

function Model:redo_label()
  local top = self.redo_stack[#self.redo_stack]
  return top and top.label
end

function Model:undo()
  local step = table.remove(self.undo_stack)
  if not step then return false end
  self.redo_stack[#self.redo_stack + 1] = { label = step.label, doc = self.doc }
  self.doc = step.doc
  return true
end

function Model:redo()
  local step = table.remove(self.redo_stack)
  if not step then return false end
  self.undo_stack[#self.undo_stack + 1] = { label = step.label, doc = self.doc }
  self.doc = step.doc
  return true
end

-- Replaces the document, for example after the file was edited by hand.
-- Undo history is kept, so a reload can itself be undone.
function Model:replace(rules, palettes)
  self:edit("Reload rules file", function(doc)
    doc.rules, doc.palettes = rules, palettes
  end)
end


-- -----------------------------------------------------------------------------
-- Queries and edits on a document
-- -----------------------------------------------------------------------------

-- The rules for one target, in priority order.
function M.group(doc, target)
  local list = {}
  for _, rule in ipairs(doc.rules) do
    if rule.target == target then list[#list + 1] = rule end
  end
  return list
end

function M.find(doc, id)
  for i, rule in ipairs(doc.rules) do
    if rule.id == id then return rule, i end
  end
  return nil
end

-- Moves the rule at position `from` of a target's group to position `to`
-- (both counted within the group, from 1). Rules of other targets keep
-- their places in the file.
function M.move_within(doc, target, from, to)
  local group = M.group(doc, target)
  if from == to or not group[from] or to < 1 or to > #group then return false end
  local moving = table.remove(group, from)
  table.insert(group, to, moving)
  local next_index = 1
  for i, rule in ipairs(doc.rules) do
    if rule.target == target then
      doc.rules[i] = group[next_index]
      next_index = next_index + 1
    end
  end
  return true
end

-- A new rule for `target`, added at the end of its group. Returns it.
function M.add_rule(doc, target)
  local rule = {
    enabled = true, target = target, filter = "new rule",
    colour = { mode = "fixed", rgb = M.DEFAULT_COLOUR },
    icon = "", tcp_layout = "", mcp_layout = "",
  }
  doc.rules[#doc.rules + 1] = rule
  rules_module.assign_ids(doc.rules)
  return rule
end

-- A copy of a rule, placed just below it. Returns the copy.
function M.duplicate_rule(doc, id)
  local rule, index = M.find(doc, id)
  if not rule then return nil end
  local copy = deep_copy(rule)
  copy.id = nil
  table.insert(doc.rules, index + 1, copy)
  rules_module.assign_ids(doc.rules)
  return copy
end

function M.delete_rule(doc, id)
  local _, index = M.find(doc, id)
  if not index then return false end
  table.remove(doc.rules, index)
  return true
end

-- Every distinct fixed and family colour the rules use, in rule order:
-- the "In use" row of the colour popover.
function M.colours_in_use(doc)
  local seen, list = {}, {}
  local function add(rgb)
    if rgb and not seen[rgb] then
      seen[rgb] = true
      list[#list + 1] = rgb
    end
  end
  for _, rule in ipairs(doc.rules) do
    local spec = rule.colour
    if spec.mode == "fixed" then add(spec.rgb)
    elseif spec.mode == "family" and spec.base then add(spec.base)
    elseif spec.mode == "gradient" then add(spec.from); add(spec.to)
    end
  end
  return list
end

-- Adds `rgb` to the front of a recent-colours list, without repeats.
function M.push_recent(recent, rgb, limit)
  for i = #recent, 1, -1 do
    if recent[i] == rgb then table.remove(recent, i) end
  end
  table.insert(recent, 1, rgb)
  while #recent > (limit or 8) do table.remove(recent) end
  return recent
end


-- -----------------------------------------------------------------------------
-- Match counts for the "Matches" column and the status line.
-- `project` holds info tables: { tracks = {...}, markers = {...}, regions = {...} }
-- (tracks as match.track_info builds them; markers and regions need only a name).
-- -----------------------------------------------------------------------------

local ITEMS = { track = "tracks", marker = "markers", region = "regions" }

local function matches(rule, info)
  if rule.target == "track" then return match.track_matches(rule.filter, info) end
  return match.marker_matches(rule.filter, info)
end

-- Returns:
--   counts    rule id -> how many items its filter matches
--   coloured  target -> how many items a rule gives a colour (first
--             matching enabled rule whose mode is not ignore or none)
function M.match_counts(doc, project)
  local counts, coloured = {}, { track = 0, marker = 0, region = 0 }
  for target, key in pairs(ITEMS) do
    local group = M.group(doc, target)
    for _, rule in ipairs(group) do counts[rule.id] = 0 end
    for _, info in ipairs(project[key] or {}) do
      local claimed = false
      for _, rule in ipairs(group) do
        if matches(rule, info) then
          counts[rule.id] = counts[rule.id] + 1
          if not claimed and rule.enabled and rule.colour.mode ~= "ignore" then
            claimed = true
            if rule.colour.mode ~= "none" then
              coloured[target] = coloured[target] + 1
            end
          end
        end
      end
    end
  end
  return counts, coloured
end

return M
