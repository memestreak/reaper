local timing = require("lib.timing")

local T = {}

function T.reports_averages_and_maxima()
  local stats = timing.new(100)
  timing.note_tick(stats, 0.000004)
  timing.note_tick(stats, 0.000006)
  timing.note_pass(stats, 0.0003, 2)
  assert(not timing.due(stats, 105))
  assert(timing.due(stats, 110))
  local line = timing.report(stats, 110)
  assert(line:find("2 ticks %(avg 0%.005 ms, max 0%.006 ms%)"), line)
  assert(line:find("1 passes %(avg 0%.300 ms, max 0%.300 ms%), 2 changes"), line)
end

function T.empty_period_reports_zeros()
  local line = timing.report(timing.new(0), 10)
  assert(line:find("0 ticks"), line)
end

return T
