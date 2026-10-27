-- Wires the cheat list to Uzume: store, core cheats, run rule, UI actions, toasts, hotkeys.
local util = require("model.util")
local formats = require("model.formats")
local library = require("model.library")
local sync = require("model.sync")
local draft_model = require("model.draft")
local importer = require("model.importer")
local panel = require("ui.panel")
local dialog = require("ui.dialog")

local C = {}
C.__index = C

local PAGE = 25 -- rows per group before "Show more"
local MAX_IMPORT_BYTES = 256 * 1024
local PENDING_MS = 5000

local function try(fn, ...)
  local r = table.pack(pcall(fn, ...))
  if not r[1] then return nil, r[2], true end
  return table.unpack(r, 2, r.n)
end

function C.new(fb)
  local self = setmetatable({}, C)
  self.fb = fb
  self.t = fb.i18n.t
  local game = fb.game or {}
  self.game = game
  self.system = tostring(game.system or ""):lower()
  self.game_title = util.clip(game.title or game.code or self.t("this_game"), 60)
  self.list, self.deleted, self.rev = {}, {}, nil
  self.query, self.edit = "", false
  self.limits = {}
  self.rejected = {}
  self.pending = {} -- id -> clock of the last turn-on
  self.blocked = nil
  self.note = nil
  self.dlg = nil
  self.fmt_set, self.core_name = nil, nil
  return self
end

function C:supported(format)
  return self.fmt_set == nil or self.fmt_set[format] == true
end

function C:available()
  local fb = self.fb
  return type(fb.cheats) == "table" and type(fb.cheats.apply) == "function" and type(fb.store) == "table"
    and type(fb.store.get) == "function"
end

-- Run rule via fb.cheats.allowed(): "off" (not allowed), "allowed", or nil when it cannot be asked.
function C:rule_state()
  local fn = type(self.fb.cheats) == "table" and self.fb.cheats.allowed or nil
  if type(fn) ~= "function" then return nil end
  local ok, allowed = pcall(fn)
  if not ok or allowed == nil then return nil end
  return allowed and "allowed" or "off"
end

---------------------------------------------------------------------------------------------------
-- Rendering

function C:view()
  local list = self.list
  return {
    t = self.t, state = "ok", game_title = self.game_title, on_count = library.on_count(list),
    blocked = self.blocked ~= nil, supported = function(f) return self:supported(f) end,
    core_name = self.core_name, rejected = self.rejected, edit = self.edit, query = self.query,
    groups = library.groups(list, self.query), total = #list, limits = self.limits, page = PAGE, note = self.note,
  }
end

function C:render_panel()
  local fb = self.fb
  local v
  if self.state ~= "ok" then
    v = { t = self.t, state = self.state }
  else
    v = self:view()
  end
  fb.ui.set("panel", panel.build(v))
end

function C:dialog_view()
  local dlg = self.dlg
  local v = {
    t = self.t, dlg = dlg, system = self.system, game_title = self.game_title, core_name = self.core_name,
    supported = function(f) return self:supported(f) end, list = self.list,
  }
  v.analysis = draft_model.analyze(dlg, { system = self.system, list = self.list, supported = v.supported })
  return v
end

function C:render_screen()
  local fb = self.fb
  local t = self.t
  if self.state ~= "ok" then
    fb.ui.set("screen", { type = "column", gap = 12, children = {
      { type = "empty", title = t(self.state == "unavailable" and "unavailable_title" or "no_game_title"),
        text = t(self.state == "unavailable" and "unavailable_text" or "no_game_text") } } })
    return
  end
  if not self.dlg then
    fb.ui.set("screen", { type = "column", gap = 12, children = {
      { type = "text", text = t("landing_text"), style = "meta" },
      { type = "row", gap = 8, align = "center", children = {
        { type = "button", label = t("add_cheat"), action = "add", variant = "primary" },
        { type = "button", label = t("cheat_database"), action = "open_db", variant = "secondary" } } } } })
    return
  end
  fb.ui.set("screen", dialog.build(self:dialog_view()))
end

function C:render()
  self:render_panel()
  self:render_screen()
end

---------------------------------------------------------------------------------------------------
-- Store

function C:persist()
  local fb = self.fb
  if not self.key then return end
  local data = { cheats = self.list, deleted = self.deleted }
  local merged, rev, status = sync.save(fb.store, self.key, data, self.rev)
  self.rev = rev
  if status == "merged" then
    self.list, self.deleted = merged.cheats, merged.deleted
    self.note = nil
    self:apply()
  elseif status == "too_big" then
    self.note = self.t("note_too_big")
  elseif status == "failed" then
    self.note = self.t("note_save_failed")
  else
    self.note = nil
  end
end

---------------------------------------------------------------------------------------------------
-- Core cheats

function C:active_list()
  local out = {}
  for _, e in ipairs(self.list) do
    if e.enabled and self:supported(e.format) then
      out[#out + 1] = { id = e.id, name = e.name, format = e.format, code = e.code, enabled = true }
    end
  end
  return out
end

function C:notify(n)
  local fb = self.fb
  if type(fb.ui.notify) == "function" then try(fb.ui.notify, n) end
end

--- Sends the full list of enabled supported entries to the core.
function C:apply()
  if self.blocked then return end
  local fb = self.fb
  local list = self:active_list()
  local res, msg, raised = try(fb.cheats.apply, list)
  self.rejected = {}
  if raised then
    fb.log.warn("cheats.apply failed: " .. tostring(msg))
    return
  end
  if res == nil then
    msg = tostring(msg or "")
    if msg:find("run_rule", 1, true) or msg:find("blocked", 1, true) then
      self:set_blocked("run_rule")
    elseif msg:find("consent", 1, true) then
      self:consent_denied()
    else
      self.note = self.t("note_apply_failed", { reason = util.clip(msg, 80) })
    end
    return
  end
  local changed = false
  for _, r in ipairs(type(res.rejected) == "table" and res.rejected or {}) do
    local e = library.find(self.list, r.id)
    if e then
      self.rejected[e.id] = tostring(r.reason or "?")
      if e.enabled then
        e.enabled, changed = false, true
        self:notify({ tone = "warning", text = self.t("rejected_toast", { name = util.clip(e.name, 80), reason = util.clip(tostring(r.reason or "?"), 80) }) })
      end
    end
  end
  if changed then
    self:persist()
    local again = self:active_list()
    try(fb.cheats.apply, again)
  end
end

function C:set_blocked(reason)
  if self.blocked == reason then return end
  self.blocked = reason
  local changed = false
  for _, e in ipairs(self.list) do
    if e.enabled then e.enabled, changed = false, true end
  end
  self.pending = {}
  if changed then self:persist() end
  if type(self.fb.cheats.clear) == "function" then try(self.fb.cheats.clear) end
  self:render()
end

function C:consent_denied()
  local now = self.fb.clock()
  local reverted = false
  for id, at in pairs(self.pending) do
    local e = library.find(self.list, id)
    if e and e.enabled and now - at <= PENDING_MS then e.enabled, reverted = false, true end
  end
  if not reverted then
    for _, e in ipairs(self.list) do
      if e.enabled then e.enabled, reverted = false, true end
    end
  end
  self.pending = {}
  if reverted then self:persist() end
  self:notify({ tone = "info", text = self.t("consent_denied_toast") })
  self:apply()
  self:render()
end

--- Reads the run rule again (event cheats.allowed, "Check again").
function C:recheck()
  local state = self:rule_state()
  if state == "off" then
    self:set_blocked("run_rule")
  else
    self.blocked = nil
    self:render()
  end
end

---------------------------------------------------------------------------------------------------
-- List actions

function C:set_enabled(id, on)
  local e = library.find(self.list, id)
  if not e or self.blocked then return end
  if on and not self:supported(e.format) then return end
  e.enabled = on
  if on then self.pending[id] = self.fb.clock() else self.pending[id] = nil end
  self:persist()
  self:apply()
  if on and e.enabled and not self.blocked then
    self:notify({ tone = "info", text = self.t("is_on", { name = util.clip(e.name, 120) }),
      actions = { { label = self.t("turn_off"), action = "toast_off", value = id } } })
  end
  self:render()
end

function C:all_off()
  local changed = false
  for _, e in ipairs(self.list) do
    if e.enabled then e.enabled, changed = false, true end
  end
  self.pending = {}
  if changed then
    self:persist()
    self:apply()
  end
  self:render()
end

function C:remove(id)
  local e, i = library.find(self.list, id)
  if not e then return end
  table.remove(self.list, i)
  self.deleted[id] = true
  self.rejected[id] = nil
  self:persist()
  if e.enabled then self:apply() end
  self:render()
end

function C:add_entries(entries)
  local added = {}
  for _, e in ipairs(entries) do
    if #self.list >= library.MAX_CHEATS then
      self.note = self.t("note_too_many", { n = library.MAX_CHEATS })
      break
    end
    e.name = library.unique_name(self.list, e.name)
    self.list[#self.list + 1] = e
    added[#added + 1] = e
  end
  if #added > 0 then self:persist() end
  return added
end

---------------------------------------------------------------------------------------------------
-- Dialog

function C:open_screen()
  local fb = self.fb
  self:render_screen()
  if type(fb.ui.open) == "function" then try(fb.ui.open, "screen") end
end

function C:open_add()
  self.dlg = { tab = 1, name = "", fmt = "auto", code = "", after_reset = false }
  self:open_screen()
end

function C:open_edit(id)
  local e = library.find(self.list, id)
  if not e then return end
  self.dlg = { tab = 1, editing = id, name = e.name, fmt = e.format, code = e.code, after_reset = e.after_reset == true }
  self:open_screen()
end

function C:open_db()
  self.dlg = { tab = 3, name = "", fmt = "auto", code = "", after_reset = false }
  self:load_db()
  self:open_screen()
end

function C:close_dialog()
  local fb = self.fb
  self.dlg = nil
  self:render_screen()
  if type(fb.ui.close) == "function" then try(fb.ui.close, "screen") end
end

--- After adding: close the sheet when the app can, else show the done view.
function C:finish(text)
  local dlg = self.dlg
  if type(self.fb.ui.close) == "function" then
    self:close_dialog()
    self:notify({ tone = "info", text = text })
    self:render_panel()
  else
    dlg.done = text
    self:render()
  end
end

function C:confirm_add()
  local dlg = self.dlg
  if not dlg then return end
  local a = draft_model.analyze(dlg, { system = self.system, list = self.list, supported = function(f) return self:supported(f) end })
  if not a.ready then self:render_screen(); return end
  local name = util.trim(dlg.name)
  local code = table.concat(a.chk.lines, "\n")
  if dlg.editing then
    local e = library.find(self.list, dlg.editing)
    if e then
      e.name, e.format, e.code = util.clip(name, 60), a.fmt, code
      e.after_reset = dlg.after_reset == true or nil
      self:persist()
      if e.enabled then self:apply() end
    end
    self.dlg = nil
    self:render_screen()
    if type(self.fb.ui.close) == "function" then try(self.fb.ui.close, "screen") end
    self:render_panel()
    return
  end
  local entry = library.make({ name = name, format = a.fmt, code = code, group = "mine", after_reset = dlg.after_reset },
    self.fb.clock())
  local added = self:add_entries({ entry })
  if #added == 0 then self:render(); return end
  dlg.name, dlg.code, dlg.fmt, dlg.after_reset = "", "", "auto", false
  self:finish(self.t("added_one", { name = util.clip(added[1].name, 80) }))
end

function C:pick_file()
  local fb, t, dlg = self.fb, self.t, self.dlg
  if not dlg then return end
  if type(fb.ui.pick_file) ~= "function" then
    dlg.imp = { error = t("pick_unavailable"), cheats = {}, selected = {} }
    self:render_screen()
    return
  end
  local ok, err = pcall(fb.ui.pick_file, { title = t("pick_title"), filters = { "*.cht", "*.txt" },
    max_bytes = MAX_IMPORT_BYTES }, function(content, info) self:on_file(content, info) end)
  if not ok then
    dlg.imp = { error = util.clip(tostring(err), 200), cheats = {}, selected = {} }
    self:render_screen()
  end
end

function C:on_file(content, info)
  local dlg, t = self.dlg, self.t
  if not dlg then return end
  if type(content) ~= "string" then
    if type(info) == "string" and info ~= "" then
      dlg.imp = { error = util.clip(info, 200), cheats = {}, selected = {} }
      self:render_screen()
    end
    return
  end
  local name = type(info) == "table" and info.name or (type(info) == "string" and info) or nil
  local size = type(info) == "table" and info.size or #content
  local parsed = importer.parse(content, self.system)
  local imp = { name = name and name:upper() or t("file_unnamed"), size = size, cheats = parsed.cheats, selected = {}, shown = 40 }
  for i, c in ipairs(parsed.cheats) do
    if not c.invalid and self:supported(c.format) then imp.selected[i] = true end
  end
  dlg.imp = imp
  self:render_screen()
end

function C:import_go()
  local dlg = self.dlg
  if not dlg or not dlg.imp then return end
  local entries = {}
  for i, c in ipairs(dlg.imp.cheats) do
    if dlg.imp.selected[i] and not c.invalid and self:supported(c.format) then
      entries[#entries + 1] = library.make({ name = c.name, format = c.format, code = c.code, group = "imported" }, self.fb.clock())
    end
  end
  local added = self:add_entries(entries)
  if #added == 0 then self:render(); return end
  dlg.imp = nil
  self:finish(self.t("imported_n", { n = #added }))
end

function C:load_db()
  local fb, t, dlg = self.fb, self.t, self.dlg
  if not dlg then return end
  local db = { added = {}, shown = 50, query = "" }
  local fn = type(fb.cheats) == "table" and fb.cheats.database or nil
  if type(fn) ~= "function" then
    db.problem, db.message = "error", t("db_unavailable")
    dlg.db = db
    return
  end
  local ok, res, msg = pcall(fn)
  if not ok then
    db.problem, db.message = "error", tostring(res)
  elseif type(res) ~= "table" then
    db.problem, db.message = dialog.db_problem(msg)
  else
    db.source, db.updated_at = res.source, res.updated_at
    db.cheats = {}
    for _, c in ipairs(type(res.cheats) == "table" and res.cheats or {}) do
      if type(c) == "table" and type(c.name) == "string" and type(c.code) == "string" then
        local fmt, lines
        for _, cand in ipairs({ formats.known(c.format_guess) and c.format_guess or false, formats.detect(c.code, self.system) or false }) do
          if cand then
            local chk = formats.check(c.code, cand, self.system)
            if #chk.errors == 0 and chk.count > 0 then fmt, lines = cand, chk.lines; break end
          end
        end
        db.cheats[#db.cheats + 1] = { name = util.clip(util.trim(c.name), 60), format = fmt, code = lines and table.concat(lines, "\n") or c.code }
      end
    end
    if #db.cheats == 0 then db.problem = "none" end
  end
  dlg.db = db
  self:mark_db_added()
end

function C:mark_db_added()
  local db = self.dlg and self.dlg.db
  if not db or not db.cheats then return end
  for i, c in ipairs(db.cheats) do
    for _, e in ipairs(self.list) do
      if e.group == "db" and e.code == c.code and e.name:lower():find(c.name:lower(), 1, true) == 1 then
        db.added[i] = true
        break
      end
    end
  end
end

function C:db_add(indexes)
  local db = self.dlg and self.dlg.db
  if not db or not db.cheats then return end
  local entries, idx = {}, {}
  for _, i in ipairs(indexes) do
    local c = db.cheats[i]
    if c and c.format and not db.added[i] and self:supported(c.format) then
      entries[#entries + 1] = library.make({ name = c.name, format = c.format, code = c.code, group = "db" }, self.fb.clock())
      idx[#idx + 1] = i
    end
  end
  local added = self:add_entries(entries)
  for k = 1, #added do db.added[idx[k]] = true end
  self:render()
end

---------------------------------------------------------------------------------------------------
-- Action routing

local function text_value(v)
  if type(v) == "table" then v = v.value or v.text end
  return type(v) == "string" and v or ""
end

local TEXTAREAS = { ta_name = "name", ta_code = "code" }

function C:on_action(action, value, slot)
  local fb, dlg = self.fb, self.dlg
  if slot == "hotkey" then
    if action == "add-cheat" then self:open_add()
    elseif action == "cheats-off" then self:all_off() end
    return
  end
  if slot == "toast" then
    if action == "toast_off" then self:set_enabled(value, false) end
    return
  end
  -- a textarea change may arrive as {id, value}
  if action == "change" and type(value) == "table" and value.id then action, value = value.id, value.value end

  local id = action:match("^toggle:(.+)$")
  if id then return self:set_enabled(id, value == true) end
  id = action:match("^edit:(.+)$")
  if id then return self:open_edit(id) end
  id = action:match("^remove:(.+)$")
  if id then return self:remove(id) end
  local group = action:match("^more:(.+)$")
  if group then
    self.limits[group] = (self.limits[group] or PAGE) + PAGE
    return self:render_panel()
  end
  local idx = action:match("^imp:(%d+)$")
  if idx then
    if dlg and dlg.imp then dlg.imp.selected[tonumber(idx)] = (value == true) or nil end
    return self:render_screen()
  end

  if TEXTAREAS[action] then
    if dlg then dlg[TEXTAREAS[action]] = text_value(value) end
    return self:render_screen()
  end

  if action == "add" then self:open_add()
  elseif action == "open_db" then self:open_db()
  elseif action == "search" then
    self.query = text_value(value)
    self:render_panel()
  elseif action == "search_clear" then
    self.query = ""
    self:render_panel()
  elseif action == "edit_mode" then
    self.edit = not self.edit
    self:render_panel()
  elseif action == "all_off" then self:all_off()
  elseif action == "recheck" then self:recheck()
  elseif not dlg then
    return
  elseif action == "dlg_tab" then
    dlg.tab = math.max(1, math.min(3, tonumber(value) or 1))
    if dlg.tab == 3 and not dlg.db then self:load_db() end
    self:render_screen()
  elseif action == "fmt" then
    dlg.fmt = (value == "auto" or formats.known(value)) and value or "auto"
    self:render_screen()
  elseif action == "use_fmt" then
    if formats.known(value) then dlg.fmt = value end
    self:render_screen()
  elseif action == "after_reset" then
    dlg.after_reset = value == true
    self:render_screen()
  elseif action == "confirm_add" then self:confirm_add()
  elseif action == "dlg_close" then self:close_dialog()
  elseif action == "dlg_again" then
    dlg.done = nil
    self:render_screen()
  elseif action == "pick_file" then self:pick_file()
  elseif action == "imp_all" then
    if dlg.imp then
      for i, c in ipairs(dlg.imp.cheats) do
        dlg.imp.selected[i] = (value == true and not c.invalid and self:supported(c.format)) or nil
      end
    end
    self:render_screen()
  elseif action == "imp_more" then
    if dlg.imp then dlg.imp.shown = (dlg.imp.shown or 40) + 40 end
    self:render_screen()
  elseif action == "import_go" then self:import_go()
  elseif action == "db_search" then
    if dlg.db then dlg.db.query, dlg.db.shown = text_value(value), 50 end
    self:render_screen()
  elseif action == "db_search_clear" then
    if dlg.db then dlg.db.query, dlg.db.shown = "", 50 end
    self:render_screen()
  elseif action == "db_more" then
    if dlg.db then dlg.db.shown = (dlg.db.shown or 50) + 50 end
    self:render_screen()
  elseif action == "db_retry" then
    self:load_db()
    self:render_screen()
  elseif action == "db_add" then self:db_add({ tonumber(value) })
  elseif action == "db_add_all" then
    local all = {}
    if dlg.db and dlg.db.cheats then
      local q = util.trim(dlg.db.query or ""):lower()
      for i, c in ipairs(dlg.db.cheats) do
        if q == "" or c.name:lower():find(q, 1, true) then all[#all + 1] = i end
      end
    end
    self:db_add(all)
  end
end

---------------------------------------------------------------------------------------------------

function C:start()
  local fb = self.fb
  if not self:available() then
    self.state = "unavailable"
    self:render()
    return
  end
  self.key = sync.key(self.game)
  if not self.key then
    self.state = "no_game"
    self:render()
    return
  end
  self.state = "ok"
  local data, rev = sync.read(fb.store, self.key)
  self.list, self.deleted, self.rev = data.cheats, data.deleted, rev

  local list, core = try(fb.cheats.formats)
  if type(list) == "table" then
    self.fmt_set = {}
    for _, f in ipairs(list) do self.fmt_set[f] = true end
  end
  self.core_name = type(core) == "string" and core ~= "" and core or self.t("core_default")

  fb.ui.on_action(function(action, value, slot) self:on_action(action, value, slot) end)
  fb.events.on("app", "cheats.blocked", function(v)
    local reason = type(v) == "table" and v.reason or nil
    if reason == "consent_denied" then self:consent_denied()
    else self:set_blocked("run_rule") end
  end)
  fb.events.on("app", "cheats.allowed", function() self:recheck() end)

  if self:rule_state() == "off" then
    self.blocked = "run_rule"
    local changed = false
    for _, e in ipairs(self.list) do
      if e.enabled then e.enabled, changed = false, true end
    end
    if changed then self:persist() end
  elseif library.on_count(self.list) > 0 then
    self:apply()
  end
  self:render()
end

return C
