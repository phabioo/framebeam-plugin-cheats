local t = require("t")
local I = require("model.importer")

local CHT = [[
cheats = 4

cheat0_desc = "Infinite Boost"
cheat0_code = "0212A4C8 000F423F"
cheat0_enable = false

cheat1_desc = "Lumen Walk"
cheat1_code = "0212A4CC 00000001+0212A4D0 00000002"
cheat1_enable = true

cheat2_desc = "Broken Line"
cheat2_code = "0212A4C 000F423F"
cheat2_enable = false

cheat3_desc = "Debug Menu"
cheat3_code = "0212A4C8 7F"
cheat3_enable = false
]]

t.case(".cht: names, codes, formats, enable flag", function()
  local r = I.parse(CHT, "gba")
  t.eq(r.kind, "cht")
  t.eq(#r.cheats, 4)
  t.eq(r.cheats[1].name, "Infinite Boost")
  t.eq(r.cheats[1].format, "gsa")
  t.eq(r.cheats[1].code, "0212A4C8 000F423F")
  t.eq(r.cheats[1].enable, false)
  t.eq(r.cheats[2].name, "Lumen Walk")
  t.eq(r.cheats[2].code, "0212A4CC 00000001\n0212A4D0 00000002")
  t.eq(r.cheats[2].enable, true)
  t.eq(r.cheats[3].invalid, true)
  t.eq(r.cheats[3].format, nil)
  t.eq(r.cheats[4].format, "raw")
  t.eq(r.bad, 1)
end)

t.case(".cht: system decides ambiguous formats", function()
  local r = I.parse(CHT, "nds")
  t.eq(r.cheats[1].format, "ar_ds")
  r = I.parse(CHT, "3ds")
  t.eq(r.cheats[1].format, "gateway")
end)

t.case(".cht: unquoted values, CRLF and entries without a code", function()
  local r = I.parse('cheats = 2\r\ncheat0_desc = Plain Name\r\ncheat0_code = 0212A4C8 000F\r\ncheat1_desc = "No code"\r\n', "gba")
  t.eq(#r.cheats, 1)
  t.eq(r.cheats[1].name, "Plain Name")
  t.eq(r.cheats[1].format, "cb")
end)

local TXT = [[
# Lumen Drift test list
[Infinite Boost]
0212A4C8 000F423F

[Lumen Walk]
0212A4CC 00000001
0212A4D0 00000002

Coral Hop
0212A4D4 00000003

Odd Code
12345
]]

t.case(".txt: Gateway [Name] blocks and plain name lines", function()
  local r = I.parse(TXT, "3ds")
  t.eq(r.kind, "txt")
  t.eq(#r.cheats, 4)
  t.eq(r.cheats[1].name, "Infinite Boost")
  t.eq(r.cheats[1].format, "gateway")
  t.eq(r.cheats[2].name, "Lumen Walk")
  t.eq(r.cheats[2].code, "0212A4CC 00000001\n0212A4D0 00000002")
  t.eq(r.cheats[3].name, "Coral Hop")
  t.eq(r.cheats[4].name, "Odd Code")
  t.eq(r.cheats[4].invalid, true)
  t.eq(r.bad, 1)
end)

t.case(".txt: plain AR text with blank lines between cheats", function()
  local r = I.parse("Max Money\n0212A4C8 000F423F\n\nFast Steps\n0212A4CC 00000001\n", "nds")
  t.eq(#r.cheats, 2)
  t.eq(r.cheats[1].format, "ar_ds")
  t.eq(r.cheats[2].name, "Fast Steps")
end)

t.case("files without cheats and odd input", function()
  t.eq(#I.parse("", "gba").cheats, 0)
  t.eq(#I.parse("just some words\nand more words\n", "gba").cheats, 0)
  t.eq(#I.parse("\239\187\191[Name]\n0212A4C8 7F\n", "gba").cheats, 1)
  local r = I.parse("0212A4C8 000F423F\n", "gba") -- code without a name
  t.eq(#r.cheats, 1)
  t.eq(r.cheats[1].name, "Cheat 1")
end)

t.case("long names are clipped", function()
  local r = I.parse("[" .. ("N"):rep(100) .. "]\n0212A4C8 7F\n", "gba")
  t.ok(utf8.len(r.cheats[1].name) <= 60)
end)
