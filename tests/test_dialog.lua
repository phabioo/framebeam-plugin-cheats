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
  t.eq(V.find(H.screen(m), "btn_import").label, "Import 1 cheat")
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
  t.ok(H.has_text(s, "1 name already exists."))
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
  local rows = V.find(s, "db_list").children
  t.eq(#rows, 4)
  t.eq(V.find(rows[1], "btn_d1").action, "db_add")
  t.eq(V.find(rows[1], "btn_d1").value, 1)
  t.ok(H.has_text(rows[3], "not supported"))
  t.eq(V.find(rows[3], "btn_d3"), nil)
  t.eq(V.find(rows[4], "btn_d4"), nil)
  t.ok(V.find(s, "btn_db_all") and V.find(s, "db_search"), "Add all and search exist")
  t.eq(V.find(s, "btn_db_all").label, "Add all 2")
  m.action("db_add", 1, "screen")
  local saved = stored(m)
  t.eq(#saved.cheats, 1)
  t.eq(saved.cheats[1].group, "db")
  t.eq(saved.cheats[1].format, "gsa")
  t.ok(H.has_text(V.find(H.screen(m), "db_list").children[1], "Added"))
  t.eq(V.find(H.screen(m), "btn_d1"), nil)
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
  t.eq(#V.find(H.screen(m), "db_list").children, 1)
  m.action("db_search", "zzz", "screen")
  t.ok(V.find(H.screen(m), "db_nomatch"))
  m.action("db_search_clear", nil, "screen")
  m.action("db_add", 2, "screen")
  m.action("dlg_close", nil, "screen")
  m.action("open_db", nil, "panel")
  t.ok(H.has_text(V.find(H.screen(m), "db_list").children[2], "Added"))
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

t.case("database: unavailable is its own problem with warning and retry", function()
  local k, msg = require("ui.dialog").db_problem("unavailable")
  t.eq(k, "unavailable")
  t.eq(msg, nil)
  local m = H.boot({ database = { nil, "unavailable" } })
  m.action("open_db", nil, "panel")
  local s = H.screen(m)
  local p = V.find(s, "db_problem")
  t.eq(p.title, "Cheat database not ready")
  t.ok(p.text:find("has no lists yet", 1, true))
  t.eq(p.tone, "warning")
  t.eq(p.action, "db_retry")
  t.ok(not H.has_text(s, "unavailable"))
end)

t.case("database: format guess from the app is checked against the code", function()
  local m = H.boot({ database = { source = "s", cheats = {
    { name = "Mismatch", code = "0212A4C8 000F", format_guess = "gsa" } } } })
  m.action("open_db", nil, "panel")
  local row = V.find(H.screen(m), "db_list").children[1]
  t.ok(H.has_text(V.find(row, "d1") or row, "CB") and V.find(row, "btn_d1"), "the detected format wins over a wrong guess")
end)

t.case("database: loading shows the looking state and the event reloads it (F2)", function()
  local m = H.boot()
  m.database = { nil, "error: loading" }
  m.action("open_db", nil, "panel")
  local s = H.screen(m)
  t.ok(V.find(s, "db_looking"))
  t.ok(not V.find(s, "db_problem"))
  m.database = DB
  m.fire_event("app", "cheats.database", nil)
  s = H.screen(m)
  t.ok(V.find(s, "db_list"))
  t.ok(not V.find(s, "db_looking"))
end)

t.case("database: event without an open sheet is ignored (F2)", function()
  local m = H.boot({ database = DB })
  m.fire_event("app", "cheats.database", nil)
  t.eq(H.screen(m) and V.find(H.screen(m), "db_list"), nil)
end)

t.case("database: off has no retry, with the settings path (F12); error keeps it", function()
  local m = H.boot({ database = { nil, "off" } })
  m.action("open_db", nil, "panel")
  local p = V.find(H.screen(m), "db_problem")
  t.eq(p.action, nil)
  t.ok(p.text:find("Server › Settings › Cheat database", 1, true))
  local m2 = H.boot({ database = { nil, "error: boom" } })
  m2.action("open_db", nil, "panel")
  t.eq(V.find(H.screen(m2), "db_problem").action, "db_retry")
end)

t.case("database: Show more is a button, Add all comes before the list (F11)", function()
  local cheats = {}
  for i = 1, 60 do cheats[i] = { name = "Cheat " .. i, code = "0212A4C8 000F423F", format_guess = "gsa" } end
  local m = H.boot({ database = { source = "s", cheats = cheats } })
  m.action("open_db", nil, "panel")
  local s = H.screen(m)
  t.eq(V.find(s, "btn_db_more").label, "Show 10 more")
  t.eq(V.find(s, "btn_db_more").variant, "secondary")
  local order = {}
  local function walk(b)
    if b.id then order[#order + 1] = b.id end
    for _, c in ipairs(b.children or {}) do walk(c) end
  end
  walk(s)
  local function idx(id) for i, k in ipairs(order) do if k == id then return i end end end
  t.ok(idx("btn_db_all") < idx("db_list") and idx("db_search") < idx("db_list"))
end)

t.case("import: dropped entries are reported, singular wording (F22)", function()
  local m = H.boot()
  m.action("add", nil, "panel")
  m.action("dlg_tab", 2, "screen")
  m.action("pick_file", nil, "screen")
  m.pick_result("[Good]\n0212A4CC 00000001\n[Broken line cheat]\nZZZZ 12\n", { name = "a.txt", size = 100 })
  local s = H.screen(m)
  t.ok(H.has_text(s, "1 entry could not be read."))
  t.eq(V.find(s, "btn_import").label, "Import 1 cheat")
end)

t.case("enter code: the hint names the lines (F8)", function()
  local m = H.boot()
  m.action("add", nil, "panel")
  H.type_code(m, "Two bad", "0212A4C8 000F423F\n0212A4C 1\n0212A4D0 7F", "gsa")
  t.ok(H.has_text(H.screen(m), "Fix line 2 to add it.") or H.has_text(H.screen(m), "Fix lines 2 and 3 to add it."))
  t.eq(require("ui.dialog").fix_hint(function(k, v) return m.fb.i18n.t(k, v) end, { { n = 2 }, { n = 3 }, { n = 3 } }), "Fix lines 2 and 3 to add it.")
  t.eq(require("ui.dialog").fix_hint(function(k, v) return m.fb.i18n.t(k, v) end, { { n = 1 }, { n = 2 }, { n = 4 } }), "Fix lines 1, 2 and 4 to add it.")
  H.type_code(m, "One bad", "0212A4C8 000F423F\n0212A4C 1", "gsa")
  t.ok(H.has_text(H.screen(m), "Fix line 2 to add it."))
end)
