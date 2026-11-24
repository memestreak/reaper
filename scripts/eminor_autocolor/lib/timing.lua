-- lib/timing.lua
--
-- Measures how much of REAPER's UI time the engine uses, so the "never
-- noticeable" promise can be checked rather than assumed. When the timing
-- log is on (ExtState "eminor_autocolor" / "timing_log" = "1"; there is no
-- action for it at the moment), the engine prints a
-- summary line to the ReaScript console every REPORT_SECONDS.
--
-- REAPER redraws at about 30 frames a second, so a frame has about 33 ms.
-- An idle tick should cost a few microseconds and a pass well under 1 ms.
-- Pure Lua: tested outside REAPER.

local M = {}

M.REPORT_SECONDS = 10

function M.new(now)
  return {
    since = now,
    ticks = 0, tick_total = 0, tick_max = 0,
    passes = 0, pass_total = 0, pass_max = 0, changes = 0,
  }
end

-- `seconds` is the time the whole tick took, including any pass.
function M.note_tick(stats, seconds)
  stats.ticks = stats.ticks + 1
  stats.tick_total = stats.tick_total + seconds
  if seconds > stats.tick_max then stats.tick_max = seconds end
end

function M.note_pass(stats, seconds, changes)
  stats.passes = stats.passes + 1
  stats.pass_total = stats.pass_total + seconds
  if seconds > stats.pass_max then stats.pass_max = seconds end
  stats.changes = stats.changes + (changes or 0)
end

function M.due(stats, now)
  return now - stats.since >= M.REPORT_SECONDS
end

local function ms(seconds)
  return string.format("%.3f ms", seconds * 1000)
end

-- One line summing up the period, e.g.
--   "10.0 s: 300 ticks (avg 0.004 ms, max 0.020 ms), 2 passes (avg 0.310 ms, max 0.400 ms), 3 changes, 0.01% of UI time"
function M.report(stats, now)
  local elapsed = math.max(now - stats.since, 1e-9)
  local avg_tick = stats.ticks > 0 and stats.tick_total / stats.ticks or 0
  local avg_pass = stats.passes > 0 and stats.pass_total / stats.passes or 0
  return string.format(
      "%.1f s: %d ticks (avg %s, max %s), %d passes (avg %s, max %s), %d changes, %.2f%% of UI time",
      elapsed, stats.ticks, ms(avg_tick), ms(stats.tick_max),
      stats.passes, ms(avg_pass), ms(stats.pass_max), stats.changes,
      100 * stats.tick_total / elapsed)
end

return M
