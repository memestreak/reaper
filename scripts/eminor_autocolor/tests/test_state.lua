local state = require("lib.state")

local T = {}

function T.round_trips_phase_1_text()
  local s = state.parse("c=123;r=r7;s=4")
  assert(s.c == 123 and s.r == "r7" and s.s == 4)
  assert(state.format(s) == "c=123;r=r7;s=4")
  assert(state.format({}) == "")
end

function T.escapes_text_values()
  local s = { c = 1, i = "a;b=c%d.png", t = "Wide", h = 3 }
  local text = state.format(s)
  assert(not text:find("a;b"), text)
  local back = state.parse(text)
  assert(back.i == "a;b=c%d.png" and back.t == "Wide" and back.h == 3 and back.c == 1)
end

function T.ignores_unknown_keys()
  local s = state.parse("c=5;z=9;q=x")
  assert(s.c == 5 and s.z == nil and s.q == nil)
end

return T
