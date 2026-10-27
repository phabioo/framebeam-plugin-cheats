local t = require("t")
local H = require("app")
local V = H.V

local CHT = [[
cheats = 4
cheat0_desc = "Infinite Boost"
cheat0_code = "0212A4C8 000F423F"
cheat0_enable = true
cheat1_desc = "Lumen Walk"
cheat1_code = "0212A4CC 00000001"
cheat2_desc = "Debug Menu"
cheat2_code = "0212A4D0 7F"
cheat3_desc = "Broken"
cheat3_code = "0212A4C 1"
]]

local function stored(m) return m.store.data["cheats.axve"] and m.store.data["cheats.axve"].value end

t.case("import: choose file, preview, unsupported and invalid rows are not selectable", function()
  local m = H.boot({ formats = { "gsa", "cb" }, core_name = "mGBA" })
  m.action("add", nil, "panel")
  m.action("dlg_tab", 2, "screen")
  local s = H.screen(m)
  t.ok(V.find(s, "btn_pick"))
  t.ok(H.has_text(s, "Uzume reads .cht and .txt files"))
  m.action("pick_file", nil, "screen")
  t.eq(m.pick.requests[1].filters, { "*.cht", "*.txt" })
  t.ok(m.pick.requests[1].max_bytes > 0)
  m.pick_result(CHT, { name = "lumen-drift.cht", size = 4096 })
  s = H.screen(m)
  t.ok(H.has_text(s, "LUMEN-DRIFT.CHT · 4 KB"))
  t.ok(H.has_text(s, "4 cheats found; 2 work with mGBA."))
  t.ok(V.find(s, "it1") and V.find(s, "it2"))
  t.eq(V.find(s, "it3").disabled, true, "raw is not supported by this core")
  t.eq(V.find(s, "it4").disabled, true, "invalid code")
  t.ok(H.has_text(s, "not a valid code"))
  t.ok(H.has_text(s, "not supported"))
  t.eq(V.find(s, "btn_import").label, "Import 2 cheats")
  m.action("imp:2", false, "screen")
  t.eq(V.find(H.screen(m), "btn_import").label, "Import 1 cheats")
  m.action("imp_all", true, "screen")
  t.eq(V.find(H.screen(m), "btn_import").label, "Import 2 cheats")
  m.action("imp_all", false, "screen")
  t.eq(V.find(H.screen(m), "btn_import"), nil)
  m.action("imp_all", true, "screen")
  m.action("import_go", nil, "screen")
  local saved = stored(m)
  t.eq(#saved.cheats, 2)
  t.eq(saved.cheats[1].group, "imported")
  t.eq(saved.cheats[1].enabled, false, "the enable flag of the file is ignored")
  t.eq(saved.cheats[2].name, "Lumen Walk")
  t.eq(m.notes[#m.notes].text, "2 cheats imported to Imported.")
  t.eq(m.closed, 1)
  t.ok(H.has_text(H.panel(m), "Imported · 2"))
  t.eq(#m.cheats.apply_calls, 0)
end)

t.case("import: duplicate names are kept with (2)", function()
  local m = H.boot(nil, { { name = "Infinite Boost" } })
  m.action("add", nil, "panel")
  m.action("dlg_tab", 2, "screen")
  m.action("pick_file", nil, "screen")
  m.pick_result("[Infinite Boost]\n0212A4CC 00000001\n[Lumen Walk]\n0212A4D0 00000002\n", { name = "a.txt", size = 100 })
  local s = H.screen(m)
  t.ok(H.has_text(s, "1 names already exist."))
  t.ok(H.has_text(s, 'Keep both adds "(2)" to the new names.'))
  m.action("import_go", nil, "screen")
  local names = {}
  for _, c in ipairs(stored(m).cheats) do names[#names + 1] = c.name end
  t.eq(names, { "Infinite Boost", "Infinite Boost (2)", "Lumen Walk" })
end)

t.case("import: file without cheats, cancelled picker, read error, no picker", function()
  local m = H.boot()
  m.action("add", nil, "panel")
  m.action("dlg_tab", 2, "screen")
  m.action("pick_file", nil, "screen")
  m.pick_result(nil)
  t.ok(V.find(H.screen(m), "btn_pick") and not V.find(H.screen(m), "imp_error"))
  m.action("pick_file", nil, "screen")
  m.pick_result("nothing useful here\n", { name = "x.txt" })
  t.ok(V.find(H.screen(m), "imp_none"))
  t.ok(H.has_text(H.screen(m), "No cheats found in this file"))
  m.action("pick_file", nil, "screen")
  m.pick_result(nil, "file is too large")
  t.ok(H.has_text(H.screen(m), "file is too large"))

  local m2 = H.boot({ no_pick_file = true })
  m2.action("add", nil, "panel")
  m2.action("dlg_tab", 2, "screen")
  m2.action("pick_file", nil, "screen")
  t.ok(H.has_text(H.screen(m2), "can't open files"))
end)

t.case("import: long files are shown in pages", function()
  local lines = {}
  for i = 1, 90 do lines[#lines + 1] = string.format("[Cheat %d]\n0212A4C8 %08X", i, i) end
  local m = H.boot()
  m.action("add", nil, "panel")
  m.action("dlg_tab", 2, "screen")
  m.action("pick_file", nil, "screen")
  m.pick_result(table.concat(lines, "\n"), { name = "big.txt" })
  t.eq(#H.toggles(H.screen(m)), 41, "all-toggle plus 40 rows")
  t.ok(H.has_text(H.screen(m), "...and 50 more"))
  m.action("imp_more", nil, "screen")
  t.eq(#H.toggles(H.screen(m)), 81)
  m.action("import_go", nil, "screen")
  t.eq(#stored(m).cheats, 90)
end)

local DB = { source = "server.example.com", updated_at = "2026-10-21", cheats = {
  { name = "Infinite Boost", code = "0212A4C8 000F423F", format_guess = "gsa" },
  { name = "Lumen Walk", code = "0212A4CC 00000001" },
  { name = "Debug Menu", code = "0212A4D0 7F", format_guess = "raw" },
  { name = "Junk", code = "xyz" },
} }

t.case("database: list, add one, add all, added marks (11c-1)", function()
  local m = H.boot({ database = DB, formats = { "gsa", "cb" }, core_name = "mGBA" })
  m.action("open_db", nil, "panel")
  t.eq(m.opened, { "screen" })
  local s = H.screen(m)
  t.eq(V.find(s, "dlg_tabs").selected, 3)
  t.ok(H.has_text(s, "MATCHED Lumen Drift · GBA"))
  t.ok(H.has_text(s, "FROM server.example.com · UPDATED 2026-10-21"))
  local rows = V.find(s, "db_list").rows
  t.eq(#rows, 4)
  t.eq(rows[1].meta, "GSA · Add")
  t.eq(rows[1].action, "db_add")
  t.eq(rows[3].meta, "RAW · not supported")
  t.eq(rows[3].action, nil)
  t.eq(rows[4].action, nil)
  t.eq(V.find(s, "btn_db_all").label, "Add all 2")
  m.action("db_add", 1, "screen")
  local saved = stored(m)
  t.eq(#saved.cheats, 1)
  t.eq(saved.cheats[1].group, "db")
  t.eq(saved.cheats[1].format, "gsa")
  t.eq(V.find(H.screen(m), "db_list").rows[1].meta, "GSA · Added")
  t.eq(V.find(H.screen(m), "btn_db_all").label, "Add all 1")
  m.action("db_add_all", nil, "screen")
  t.eq(#stored(m).cheats, 2)
  t.eq(V.find(H.screen(m), "btn_db_all"), nil)
  t.ok(H.has_text(H.panel(m), "From the cheat database · 2"))
  t.eq(#m.cheats.apply_calls, 0)
end)

t.case("database: opened from the dialog tab, search, reopen shows added", function()
  local m = H.boot({ database = DB })
  m.action("add", nil, "panel")
  m.action("dlg_tab", 3, "screen")
  t.ok(V.find(H.screen(m), "db_list"))
  m.action("db_search", "walk", "screen")
  t.eq(#V.find(H.screen(m), "db_list").rows, 1)
  m.action("db_search", "zzz", "screen")
  t.ok(V.find(H.screen(m), "db_nomatch"))
  m.action("db_search_clear", nil, "screen")
  m.action("db_add", 2, "screen")
  m.action("dlg_close", nil, "screen")
  m.action("open_db", nil, "panel")
  t.eq(V.find(H.screen(m), "db_list").rows[2].meta, "GSA · Added")
end)

t.case("database: no match, off, offline, error, empty (11c-2)", function()
  local function problem(opts, title)
    local m = H.boot(opts)
    m.action("open_db", nil, "panel")
    local s = H.screen(m)
    t.ok(V.find(s, "db_problem"), title)
    t.ok(H.has_text(s, title), title)
    return s
  end
  problem({}, "No cheats for this game in the database")
  problem({ database = { nil, "off" } }, "The cheat database is off")
  problem({ database = { nil, "offline" } }, "The server can't be reached")
  local s = problem({ database = { nil, "error: boom 500" } }, "The cheat database didn't answer")
  t.ok(H.has_text(s, "boom 500"))
  t.ok(not H.has_text(s, "error:"))
  problem({ database = { source = "s", cheats = {} } }, "No cheats for this game in the database")
  local m = H.boot({ no_cheats = false })
  m.fb.cheats.database = nil
  m.action("open_db", nil, "panel")
  t.ok(H.has_text(H.screen(m), "no cheat database"))
end)

t.case("database: format guess from the app is checked against the code", function()
  local m = H.boot({ database = { source = "s", cheats = {
    { name = "Mismatch", code = "0212A4C8 000F", format_guess = "gsa" } } } })
  m.action("open_db", nil, "panel")
  local rows = V.find(H.screen(m), "db_list").rows
  t.eq(rows[1].meta, "CB · Add", "the detected format wins over a wrong guess")
end)
