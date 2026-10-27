-- The add / import dialog, shown as the plugin's `screen` sheet (design 11b-1 to 11b-4, 11c-1, 11c-2).
local formats = require("model.formats")
local util = require("model.util")

local D = {}

local function text(s, style, tone, extra)
  local b = { type = "text", text = s, style = style }
  if tone then b.tone = tone end
  for k, v in pairs(extra or {}) do b[k] = v end
  return b
end

local function fmt_label(t, f) return t("fmt_" .. f) end

--- Error line for the Enter code tab.
local function line_error(t, e)
  local vars = util.copy(e.vars or {})
  vars.n_line = e.n
  return t("line_error", { n = e.n, msg = t(e.key, vars) })
end
D.line_error = line_error

local function enter_page(v)
  local t, dlg = v.t, v.dlg
  local a = v.analysis
  local kids = {}
  kids[#kids + 1] = text(t("lbl_name"), "meta")
  kids[#kids + 1] = { type = "textarea", id = "ta_name", value = dlg.name, lines = 1 }
  if a.name_state == "taken" then kids[#kids + 1] = text(t("name_taken"), "meta", "danger", { id = "name_err" }) end

  local opts = { { value = "auto", label = t("fmt_detect") } }
  for _, f in ipairs(formats.for_system(v.system)) do opts[#opts + 1] = { value = f, label = fmt_label(t, f) } end
  kids[#kids + 1] = { type = "row", gap = 8, align = "center", children = {
    text(t("lbl_format"), "meta"),
    { type = "select", id = "sel_fmt", options = opts, selected = dlg.fmt, action = "fmt" },
  } }
  if dlg.fmt == "auto" then
    kids[#kids + 1] = text(a.detected and t("found_format", { tag = formats.tags[a.detected] }) or t("not_detected"),
      "meta", a.detected and "ok" or nil, { id = "detect" })
  end

  kids[#kids + 1] = text(t("lbl_code"), "meta")
  kids[#kids + 1] = { type = "textarea", id = "ta_code", value = dlg.code, lines = 6, mono = true }

  if a.blank then
    kids[#kids + 1] = text(t("code_hint"), "meta", nil, { id = "status" })
  elseif not a.fmt then
    kids[#kids + 1] = text(t("pick_format_hint"), "meta", "danger", { id = "status" })
  elseif #a.chk.errors == 0 then
    kids[#kids + 1] = text(t("code_ok", { n = a.chk.count, format = fmt_label(t, a.fmt) }), "body", "ok", { id = "status" })
    if a.unsupported then
      kids[#kids + 1] = text(t("fmt_unsupported_note", { core = v.core_name }), "meta", "warning", { id = "unsupported" })
    end
    kids[#kids + 1] = text(t("goes_to_mine"), "meta")
  else
    for i, e in ipairs(a.chk.errors) do
      if i > 8 then
        kids[#kids + 1] = text(t("more_errors", { n = #a.chk.errors - 8 }), "meta", "danger")
        break
      end
      kids[#kids + 1] = text(line_error(t, e), "meta", "danger", { id = "err" .. i })
    end
    if a.chk.other and dlg.fmt ~= "auto" then
      kids[#kids + 1] = text(t("looks_like", { other = fmt_label(t, a.chk.other), chosen = fmt_label(t, a.fmt) }), "meta")
      kids[#kids + 1] = { type = "button", id = "btn_use_fmt", label = t("use_format", { format = fmt_label(t, a.chk.other) }),
        action = "use_fmt", value = a.chk.other, variant = "secondary" }
    end
  end

  kids[#kids + 1] = { type = "toggle", id = "tg_reset", action = "after_reset", label = t("after_reset_label"),
    checked = dlg.after_reset == true }

  local buttons = {}
  if a.ready then
    buttons[#buttons + 1] = { type = "button", id = "btn_confirm", label = dlg.editing and t("save_cheat") or t("add_cheat"),
      action = "confirm_add", variant = "primary" }
  end
  buttons[#buttons + 1] = { type = "button", id = "btn_cancel", label = t("cancel"), action = "dlg_close", variant = "quiet" }
  kids[#kids + 1] = { type = "row", gap = 8, align = "center", children = buttons }
  if not a.ready then
    kids[#kids + 1] = text(a.name_state == "empty" and t("need_name") or t("fix_to_add"), "meta", nil, { id = "not_ready" })
  end
  return { type = "column", gap = 8, children = kids }
end

--- Import rows: selectable when the code is valid and the core can use the format.
local function import_state(v, c)
  if c.invalid then return false, v.t("imp_invalid") end
  if not v.supported(c.format) then return false, v.t("not_supported_short") end
  return true
end

local function import_page(v)
  local t, imp = v.t, v.dlg.imp
  local kids = {}
  if not imp then
    kids[#kids + 1] = text(t("imp_hint"), "meta")
    kids[#kids + 1] = { type = "button", id = "btn_pick", label = t("choose_file"), action = "pick_file", variant = "primary" }
    return { type = "column", gap = 8, children = kids }
  end
  if imp.error then
    kids[#kids + 1] = { type = "empty", id = "imp_error", title = t("imp_error_title"), text = imp.error, tone = "danger",
      action_label = t("choose_file"), action = "pick_file" }
    return { type = "column", gap = 8, children = kids }
  end
  local cheats = imp.cheats
  local usable, selected = 0, 0
  for i, c in ipairs(cheats) do
    if import_state(v, c) then
      usable = usable + 1
      if imp.selected[i] then selected = selected + 1 end
    end
  end
  kids[#kids + 1] = { type = "row", gap = 8, align = "center", children = {
    text(t("file_line", { name = imp.name or "", kb = math.max(1, math.floor((imp.size or 0) / 1024 + 0.5)) }), "meta", nil, { id = "file_line" }),
    { type = "button", id = "btn_pick", label = t("choose_another"), action = "pick_file", variant = "quiet" },
  } }
  if #cheats == 0 then
    kids[#kids + 1] = { type = "empty", id = "imp_none", title = t("imp_none_title"), text = t("imp_hint") }
    return { type = "column", gap = 8, children = kids }
  end
  kids[#kids + 1] = text(t("found_n", { found = #cheats, usable = usable, core = v.core_name }), "body", nil, { id = "found" })
  if usable > 0 then
    kids[#kids + 1] = { type = "toggle", id = "tg_all", action = "imp_all", label = t("imp_all", { n = usable }),
      checked = selected == usable }
  end
  local shown = math.min(#cheats, imp.shown or 40)
  for i = 1, shown do
    local c = cheats[i]
    local ok, why = import_state(v, c)
    local children = {}
    if ok then
      children[#children + 1] = { type = "toggle", id = "it" .. i, action = "imp:" .. i, checked = imp.selected[i] == true }
    else
      children[#children + 1] = { type = "badge", text = t("off") }
    end
    local name = text(c.name, "body", nil, { wrap = true })
    if why then
      name = { type = "column", gap = 4, children = { name, text(why, "meta", "warning") } }
    end
    children[#children + 1] = name
    children[#children + 1] = { type = "badge", text = formats.tags[c.format] or "?" }
    kids[#kids + 1] = { type = "row", id = "irow" .. i, gap = 8, align = "center", children = children }
  end
  if #cheats > shown then
    kids[#kids + 1] = { type = "button", id = "btn_imp_more", label = t("and_n_more", { n = #cheats - shown }),
      action = "imp_more", variant = "quiet" }
  end
  if selected > 0 then
    local dup = 0
    local seen = {}
    for _, e in ipairs(v.list) do seen[e.name:lower()] = true end
    for i, c in ipairs(cheats) do
      if imp.selected[i] and seen[c.name:lower()] then dup = dup + 1 end
    end
    if dup > 0 then
      kids[#kids + 1] = text(t("names_exist", { n = dup }), "meta", "warning", { id = "dups" })
      kids[#kids + 1] = text(t("keep_both"), "meta")
    end
    kids[#kids + 1] = { type = "button", id = "btn_import", label = t("import_n", { n = selected }), action = "import_go",
      variant = "primary" }
  end
  return { type = "column", gap = 8, children = kids }
end

--- Why the database gave nothing: classify the message of fb.cheats.database().
function D.db_problem(msg)
  local m = tostring(msg or ""):lower()
  if m:find("offline") or m:find("unreach") or m:find("network") or m:find("timeout") then return "offline" end
  if m:find("%f[%w]off%f[%W]") or m:find("disabled") then return "off" end
  if m:find("not_found") or m:find("not found") or m:find("no match") or m:find("no_match") or m:find("none") then
    return "none"
  end
  return "error"
end

local function db_page(v)
  local t, db = v.t, v.dlg.db
  local kids = {}
  if not db then
    kids[#kids + 1] = text(t("db_looking", { game = v.game_title }), "meta", nil, { id = "db_looking" })
    return { type = "column", gap = 8, children = kids }
  end
  if db.problem then
    local key = db.problem
    local body
    if key == "error" then body = util.clip(db.message or "", 200) end
    kids[#kids + 1] = { type = "empty", id = "db_problem", title = t("db_" .. key .. "_title"),
      text = body or t("db_" .. key .. "_text"), tone = key == "error" and "danger" or nil,
      action_label = t("db_retry"), action = "db_retry" }
    return { type = "column", gap = 8, children = kids }
  end
  kids[#kids + 1] = text(t("db_matched", { game = v.game_title, system = tostring(v.system or ""):upper() }), "eyebrow")
  if db.source then
    kids[#kids + 1] = text(t("db_source", { source = util.clip(tostring(db.source), 60),
      date = util.clip(tostring(db.updated_at or "?"), 24) }), "meta", nil, { id = "db_source" })
  end
  kids[#kids + 1] = { type = "textfield", id = "db_search", action = "db_search", text = db.query or "",
    placeholder = t("search_placeholder") }
  local rows, visible, addable = {}, 0, 0
  local q = util.trim(db.query or ""):lower()
  for i, c in ipairs(db.cheats) do
    local tag = formats.tags[c.format] or "?"
    local added = db.added[i] == true
    local ok = c.format ~= nil and v.supported(c.format)
    if not added and ok then addable = addable + 1 end
    if q == "" or c.name:lower():find(q, 1, true) then
      visible = visible + 1
      if visible <= (db.shown or 50) then
        local row = { id = "d" .. i, title = c.name }
        if added then
          row.meta = tag .. " · " .. t("db_added")
          row.tone = "ok"
        elseif not ok then
          row.meta = tag .. " · " .. t("not_supported_short")
          row.tone = "warning"
        else
          row.meta = tag .. " · " .. t("db_add")
          row.action, row.value = "db_add", i
        end
        rows[#rows + 1] = row
      end
    end
  end
  if visible == 0 then
    kids[#kids + 1] = { type = "empty", id = "db_nomatch", title = t("no_match", { query = db.query or "" }),
      action_label = t("clear_search"), action = "db_search_clear" }
  else
    kids[#kids + 1] = { type = "list", id = "db_list", rows = rows }
  end
  if visible > (db.shown or 50) then
    kids[#kids + 1] = { type = "button", id = "btn_db_more", label = t("and_n_more", { n = visible - (db.shown or 50) }),
      action = "db_more", variant = "quiet" }
  end
  local buttons = {}
  if addable > 0 then
    buttons[#buttons + 1] = { type = "button", id = "btn_db_all", label = t("db_add_all", { n = addable }),
      action = "db_add_all", variant = "primary" }
  end
  buttons[#buttons + 1] = { type = "button", id = "btn_close", label = t("close"), action = "dlg_close", variant = "quiet" }
  kids[#kids + 1] = { type = "row", gap = 8, align = "center", children = buttons }
  return { type = "column", gap = 8, children = kids }
end

--- v = { t, dlg, system, game_title, core_name, supported(fmt), list }
function D.build(v)
  local t, dlg = v.t, v.dlg
  local head = {
    text(t("dlg_eyebrow", { system = tostring(v.system or ""):upper() }), "eyebrow"),
    text(dlg.editing and t("dlg_edit_title", { game = v.game_title }) or t("dlg_title", { game = v.game_title }), "title"),
  }
  if dlg.done then
    head[#head + 1] = text(dlg.done, "body", "ok", { id = "done" })
    head[#head + 1] = { type = "row", gap = 8, align = "center", children = {
      { type = "button", id = "btn_again", label = t("add_more"), action = "dlg_again", variant = "secondary" },
      { type = "button", id = "btn_close", label = t("close"), action = "dlg_close", variant = "primary" },
    } }
    return { type = "column", gap = 12, children = head }
  end
  if dlg.editing then
    head[#head + 1] = enter_page(v)
    return { type = "column", gap = 12, children = head }
  end
  local tabs = { t("tab_enter"), t("tab_import"), t("tab_database") }
  local empty = { type = "column", children = {} }
  local pages = { empty, empty, empty }
  if dlg.tab == 1 then pages[1] = enter_page(v)
  elseif dlg.tab == 2 then pages[2] = import_page(v)
  else pages[3] = db_page(v) end
  head[#head + 1] = { type = "tabs", id = "dlg_tabs", tabs = tabs, selected = dlg.tab, action = "dlg_tab", children = pages }
  return { type = "column", gap = 12, children = head }
end

return D
