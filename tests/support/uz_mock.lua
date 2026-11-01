-- Fake `uz` for tests: ui (validated against the block catalog), cheats, store, events, run, ticks.
-- The API shapes of uz.cheats, uz.store, uz.ui.pick_file and the textarea block follow the binding
-- contract in the Uzume plan 0.20 ("Verträge"); uz.cheats.database() is the contract this plugin adds.
local M = {}
local ui_validator = require("ui_validator")

function M.read_json_flat(s)
  local out = {}
  local esc = { ['"'] = '"', ["\\"] = "\\", ["/"] = "/", n = "\n", t = "\t", r = "\r", b = "\b", f = "\f" }
  local pos = 1
  while true do
    local k, e = s:match('^%s*[{,]?%s*"([^"]*)"%s*:%s*()', pos)
    if not k then break end
    pos = e
    assert(s:sub(pos, pos) == '"', "flat string values only")
    pos = pos + 1
    local buf = {}
    while true do
      local c = s:sub(pos, pos)
      if c == "" then error("unterminated string") end
      if c == '"' then pos = pos + 1; break end
      if c == "\\" then
        local n = s:sub(pos + 1, pos + 1)
        if n == "u" then
          buf[#buf + 1] = utf8.char(tonumber(s:sub(pos + 2, pos + 5), 16))
          pos = pos + 6
        else
          buf[#buf + 1] = assert(esc[n], "bad escape")
          pos = pos + 2
        end
      else
        buf[#buf + 1] = c
        pos = pos + 1
      end
    end
    out[k] = table.concat(buf)
  end
  return out
end

local function read_file(path)
  local f = assert(io.open(path, "rb"))
  local s = f:read("a")
  f:close()
  return s
end

local function check_value(v, depth)
  local tv = type(v)
  if tv == "function" or tv == "userdata" or tv == "thread" then error("value of type " .. tv .. " not allowed", 3) end
  if tv == "table" then
    if depth > 32 then error("value too deep", 3) end
    for k, x in pairs(v) do
      if type(k) == "table" then error("table used as key", 3) end
      check_value(x, depth + 1)
    end
  end
end

local function deep_copy(v)
  if type(v) ~= "table" then return v end
  local c = {}
  for k, x in pairs(v) do c[k] = deep_copy(x) end
  return c
end

local function json_size(v)
  local t = type(v)
  if t == "string" then return #v + 2 end
  if t == "table" then
    local n = 2
    for k, x in pairs(v) do n = n + json_size(x) + 1 + (type(k) == "string" and #k + 3 or 0) end
    return n
  end
  return #tostring(v)
end

-- opts: game, language, formats (list | nil), core_name, database (table | { nil, msg }), store ({key = value}),
--       run (current run table), no_cheats, no_store, no_pick_file, no_close, i18n_dir
function M.new(opts)
  opts = opts or {}
  local mock = { logs = {}, handlers = {}, notes = {}, opened = {}, closed = 0 }
  local uz = { api = 1, plugin = { id = "uzume.cheats", version = "0.1.4" } }
  mock.uz = uz
  uz.game = opts.game or { system = "gba", code = "AXVE", title = "Lumen Drift" }
  if opts.language then uz.game.language = opts.language end

  uz.log = {}
  for _, level in ipairs({ "debug", "info", "warn", "error" }) do
    uz.log[level] = function(...)
      local parts = table.pack(...)
      for i = 1, parts.n do parts[i] = tostring(parts[i]) end
      mock.logs[#mock.logs + 1] = { level = level, text = table.concat(parts, "\t", 1, parts.n) }
    end
  end

  local now = 1000
  uz.clock = function() return now end
  function mock.advance(ms) now = now + ms end

  uz.events = {
    emit = function(name, value) check_value(value, 1) end,
    on = function(plugin_id, name, fn) mock.handlers[#mock.handlers + 1] = { plugin_id, name, fn } end,
  }
  function mock.fire_event(plugin_id, name, value)
    for _, h in ipairs(mock.handlers) do
      if (h[1] == "*" or h[1] == plugin_id) and h[2] == name then h[3](deep_copy(value), plugin_id, name) end
    end
  end

  local tick_fn
  uz.on_tick = function(fn) tick_fn = fn end
  mock.frame = 0
  function mock.tick(n)
    for _ = 1, n or 1 do
      mock.frame = mock.frame + 1
      now = now + 34
      if tick_fn then tick_fn(mock.frame) end
    end
  end

  local dir = opts.i18n_dir or "plugin/i18n"
  local strings = M.read_json_flat(read_file(dir .. "/en.json"))
  if opts.language and opts.language ~= "en" then
    local f = io.open(dir .. "/" .. opts.language .. ".json", "rb")
    if f then
      local s = f:read("a"); f:close()
      for k, v in pairs(M.read_json_flat(s)) do strings[k] = v end
    end
  end
  mock.strings = strings
  uz.i18n = {
    t = function(key, vars)
      local s = strings[key] or key
      return (s:gsub("{([%w_]+)}", function(k)
        if vars and vars[k] ~= nil then return tostring(vars[k]) end
      end))
    end,
  }

  -- uz.ui -------------------------------------------------------------------------------------------
  local ui = { trees = {}, sets = {}, handler = nil }
  mock.ui = ui
  local SLOTS = { panel = true, screen = true }
  uz.ui = {
    set = function(slot, tree)
      if not SLOTS[slot] then error("slot " .. tostring(slot) .. " not declared in manifest", 2) end
      local ok, err = ui_validator.validate(tree)
      if not ok then error("ui tree: " .. err, 2) end
      ui.trees[slot] = deep_copy(tree)
      ui.sets[slot] = (ui.sets[slot] or 0) + 1
    end,
    clear = function(slot) ui.trees[slot] = nil end,
    notify = function(n)
      if type(n) ~= "table" or type(n.text) ~= "string" or #n.text < 1 or #n.text > 300 then error("notify: bad text", 2) end
      if n.title and #n.title > 80 then error("notify: title too long", 2) end
      if n.tone and n.tone ~= "info" and n.tone ~= "important" and n.tone ~= "warning" then error("notify: bad tone", 2) end
      if n.actions then
        if #n.actions > 2 then error("notify: at most 2 actions", 2) end
        for _, a in ipairs(n.actions) do
          if type(a.label) ~= "string" or #a.label < 1 or #a.label > 40 or type(a.action) ~= "string" then
            error("notify: bad action", 2)
          end
          check_value(a.value, 1)
        end
      end
      mock.notes[#mock.notes + 1] = deep_copy(n)
      return #mock.notes
    end,
    on_action = function(fn) ui.handler = fn end,
    open = function(slot)
      if slot ~= "screen" and slot ~= "panel" then error("open: bad slot", 2) end
      mock.opened[#mock.opened + 1] = slot
      return true
    end,
  }
  if not opts.no_close then
    -- not in the documented API today; the plugin uses it only when present
    uz.ui.close = function(slot) mock.closed = mock.closed + 1; return true end
  end
  function mock.action(action, value, slot) return ui.handler(action, deep_copy(value), slot) end

  -- uz.ui.pick_file{ title, filters, max_bytes } -> content via callback(content, info)
  mock.pick = { requests = {} }
  if not opts.no_pick_file then
    uz.ui.pick_file = function(o, cb)
      if type(o) ~= "table" or type(cb) ~= "function" then error("pick_file: options and callback expected", 2) end
      mock.pick.requests[#mock.pick.requests + 1] = deep_copy(o)
      mock.pick.cb = cb
      return true
    end
  end
  --- mock.pick_result(content, info): the user picked a file (content nil = cancelled)
  function mock.pick_result(content, info) mock.pick.cb(content, info) end

  -- uz.cheats ---------------------------------------------------------------------------------------
  mock.cheats = { applied = {}, apply_calls = {}, clears = 0, reject = {}, block = nil }
  if not opts.no_cheats then
    uz.cheats = {
      formats = function()
        if opts.formats == nil then return { "gsa", "cb", "ar_gba", "raw" }, opts.core_name end
        return deep_copy(opts.formats), opts.core_name
      end,
      apply = function(list)
        if type(list) ~= "table" then error("apply: list expected", 2) end
        for _, c in ipairs(list) do
          if type(c.id) ~= "string" or type(c.name) ~= "string" or type(c.format) ~= "string"
             or type(c.code) ~= "string" or c.enabled ~= true then
            error("apply: bad entry", 2)
          end
        end
        mock.cheats.apply_calls[#mock.cheats.apply_calls + 1] = deep_copy(list)
        if mock.cheats.block then return nil, mock.cheats.block end
        local res = { applied = 0, rejected = {} }
        mock.cheats.applied = {}
        for _, c in ipairs(list) do
          if mock.cheats.reject[c.id] then
            res.rejected[#res.rejected + 1] = { id = c.id, reason = mock.cheats.reject[c.id] }
          else
            res.applied = res.applied + 1
            mock.cheats.applied[#mock.cheats.applied + 1] = deep_copy(c)
          end
        end
        return res
      end,
      clear = function() mock.cheats.clears = mock.cheats.clears + 1; mock.cheats.applied = {} end,
      database = function()
        local d = mock.database ~= nil and mock.database or opts.database
        if d == nil then return nil, "not_found" end
        if d[1] == nil and d[2] ~= nil then return nil, d[2] end
        return deep_copy(d)
      end,
      -- true | false, reason; driven by mock.rule ("off" blocks)
      allowed = function()
        if mock.rule == "off" then return false, "run_rule" end
        return true
      end,
    }
  end

  -- uz.store ----------------------------------------------------------------------------------------
  local store = { data = {}, conflicts = {} }
  mock.store = store
  for k, v in pairs(opts.store or {}) do store.data[k] = { value = deep_copy(v), rev = 1 } end
  if not opts.no_store then
    uz.store = {
      get = function(key)
        local d = store.data[key]
        if not d then return nil, 0 end
        return deep_copy(d.value), d.rev
      end,
      put = function(key, value, rev)
        if type(key) ~= "string" or not key:match("^[a-z0-9_.-]+$") or #key > 64 then error("store: bad key " .. tostring(key), 2) end
        check_value(value, 1)
        if json_size(value) > 256 * 1024 then error("store: value larger than 256 KiB", 2) end
        local d = store.data[key]
        local cur = d and d.rev or 0
        store.puts = (store.puts or 0) + 1
        if rev ~= nil and rev ~= cur then
          store.conflicts[key] = store.conflicts[key] or {}
          table.insert(store.conflicts[key], { value = deep_copy(value), revision = rev })
          return nil, "conflict"
        end
        store.data[key] = { value = deep_copy(value), rev = cur + 1 }
        store.conflicts[key] = nil
        return true
      end,
      conflicts = function(key) return deep_copy(store.conflicts[key] or {}) end,
    }
  end
  --- mock.store_external(key, value): another device changed the key (bumps the revision)
  function mock.store_external(key, value)
    local d = store.data[key]
    store.data[key] = { value = deep_copy(value), rev = (d and d.rev or 0) + 1 }
  end

  -- uz.run (only when opts.run is given; the plugin has no run.state permission, so this models
  -- an app that lets it read the run) -----------------------------------------------------------------
  mock.rule = opts.rule

  return mock
end

return M
