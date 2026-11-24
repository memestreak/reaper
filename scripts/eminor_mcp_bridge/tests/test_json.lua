local json = require("lib.json")

local T = {}

function T.plain_values()
  assert(json.encode(nil) == "null")
  assert(json.encode(true) == "true")
  assert(json.encode(3) == "3")
  assert(json.encode(2.5) == "2.5")
  assert(json.encode(5.0) == "5")
  assert(json.encode("hi") == '"hi"')
end

function T.strings_are_escaped()
  assert(json.encode('a"b\\c\n\1') == '"a\\"b\\\\c\\n\\u0001"')
end

function T.arrays_and_objects()
  assert(json.encode({ 1, "two", false }) == '[1,"two",false]')
  assert(json.encode({}) == "[]")
  assert(json.encode({ b = 1, a = { 2 } }) == '{"a":[2],"b":1}')
end

function T.numbers_json_cannot_hold_become_null()
  assert(json.encode({ 0 / 0, math.huge }) == "[null,null]")
end

function T.other_types_become_text()
  assert(json.encode(print):match('^"function'))
end

function T.a_table_containing_itself_is_an_error()
  local loop = {}
  loop.me = loop
  assert(not pcall(json.encode, loop))
end

function T.the_same_table_twice_is_fine()
  local shared = { 1 }
  assert(json.encode({ shared, shared }) == "[[1],[1]]")
end

return T
