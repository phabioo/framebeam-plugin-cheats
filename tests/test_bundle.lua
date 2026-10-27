local t = require("t")
local mock = require("fb_mock")

local function read(path)
  local f = assert(io.open(path, "rb"))
  local s = f:read("a")
  f:close()
  return s
end

t.case("plugin/main.lua is up to date", function()
  local p = assert(io.popen("lua5.4 tools/bundle.lua --check 2>&1"))
  local out = p:read("a")
  local ok = p:close()
  t.ok(ok, out)
end)

t.case("bundled plugin loads in the mock sandbox and shows the panel", function()
  local m = mock.new({ language = "de" })
  _G.fb = m.fb
  local chunk = assert(loadfile("plugin/main.lua"))
  chunk()
  _G.fb = nil
  t.eq(m.logs[1].text, "Cheats 0.1.0 geladen.")
  t.ok(m.ui.trees.panel and m.ui.trees.screen)
end)

t.case("sources use no sandbox-forbidden globals", function()
  local p = assert(io.popen("ls src/*.lua src/*/*.lua"))
  for path in p:lines() do
    local src = read(path)
    for _, bad in ipairs({ "io%.", "os%.", "package%.", "debug%.", "dofile", "loadstring", "[^%w_]load%(" }) do
      t.ok(not src:find(bad), path .. " uses " .. bad)
    end
  end
  p:close()
end)

t.case("manifest", function()
  local s = read("plugin/manifest.json")
  for _, needle in ipairs({
    '"id": "uzume.cheats"', '"name": "Cheats"', '"version": "0.1.0"', '"api": 1',
    '"permissions": ["ui", "cheats", "store"]', '"entry": "main.lua"', '"panel": { "title": "Cheats" }',
    '"screen": { "title": "Cheats" }', '"add-cheat"', '"cheats-off"',
    '{ "system": "gb" }', '{ "system": "gbc" }', '{ "system": "gba" }', '{ "system": "nds" }', '{ "system": "3ds" }',
  }) do
    t.ok(s:find(needle, 1, true), "manifest lacks " .. needle)
  end
  t.ok(not s:find("memory.write", 1, true))
end)

t.case("i18n: German has exactly the keys of English", function()
  local en = mock.read_json_flat(read("plugin/i18n/en.json"))
  local de = mock.read_json_flat(read("plugin/i18n/de.json"))
  for k in pairs(en) do t.ok(de[k] ~= nil, "de lacks " .. k) end
  for k in pairs(de) do t.ok(en[k] ~= nil, "en lacks " .. k) end
  -- same placeholders in both languages
  for k, v in pairs(en) do
    local a, b = {}, {}
    for p in v:gmatch("{([%w_]+)}") do a[p] = true end
    for p in de[k]:gmatch("{([%w_]+)}") do b[p] = true end
    t.eq(a, b, "placeholders of " .. k)
  end
end)

t.case("i18n: every key used in the sources exists", function()
  local en = mock.read_json_flat(read("plugin/i18n/en.json"))
  local p = assert(io.popen("ls src/*.lua src/*/*.lua"))
  for path in p:lines() do
    local src = read(path)
    for key in src:gmatch('[^%w_]t%("([%w_]+)"') do
      if key:sub(-1) ~= "_" then t.ok(en[key] ~= nil, path .. " uses missing key " .. key) end
    end
  end
  p:close()
  -- keys built from a prefix
  local fmts = { "gsa", "cb", "ar_gba", "ar_ds", "game_genie", "gateway", "raw" }
  for _, f in ipairs(fmts) do t.ok(en["fmt_" .. f], "fmt_" .. f) end
  for _, k in ipairs({ "none", "off", "offline", "error" }) do
    t.ok(en["db_" .. k .. "_title"] and en["db_" .. k .. "_text"] == nil == (k == "error"), "db_" .. k)
  end
  for _, g in ipairs({ "db", "mine", "imported" }) do t.ok(en["group_" .. g]) end
  for _, k in ipairs({ "err_empty", "err_format", "err_not_hex", "err_digits_before", "err_digits_after", "err_digits_total",
    "err_one_group", "err_group_count", "err_gg_group", "err_shape", "err_too_many_lines" }) do
    t.ok(en[k], k)
  end
end)
