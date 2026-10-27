-- Reads cheat files: RetroArch .cht and text files (Gateway `[Name]` blocks, plain AR/GS text).
-- Pure Lua. parse(content, system) -> { kind = "cht"|"txt", cheats = { {name=, lines=, code=, format=} }, bad = n }
local util = require("model.util")
local formats = require("model.formats")

local I = {}

local MAX_NAME = 60
local MAX_CHEATS = 1000

local function clean_name(s, fallback)
  s = util.trim((s or ""):gsub("%c+", " "))
  if s == "" then s = fallback end
  return util.clip(s, MAX_NAME)
end

-- Finishes one raw cheat: detects the format and normalizes the lines.
local function finish(raw_lines, name, system, index)
  local text = table.concat(raw_lines, "\n")
  local fmt = formats.detect(text, system)
  local entry = { name = clean_name(name, "Cheat " .. index), format = fmt }
  if fmt then
    local chk = formats.check(text, fmt, system)
    entry.lines = chk.lines
    entry.code = table.concat(chk.lines, "\n")
    if #chk.errors > 0 then entry.format, entry.lines, entry.code = nil, nil, nil end
  end
  if not entry.format then
    entry.lines, entry.code = raw_lines, text
    entry.invalid = true
  end
  return entry
end

local function unquote(v)
  v = util.trim(v)
  local q = v:match('^"(.*)"$')
  return q or v
end

function I.parse_cht(content, system)
  local by_index, max_index = {}, 0
  for _, line in ipairs(util.lines(content)) do
    local n, field, value = line:match("^%s*cheat(%d+)_([%w_]+)%s*=%s*(.-)%s*$")
    if n then
      n = tonumber(n)
      if n < MAX_CHEATS then
        by_index[n] = by_index[n] or {}
        by_index[n][field] = unquote(value)
        if n > max_index then max_index = n end
      end
    end
  end
  local out, bad = {}, 0
  for n = 0, max_index do
    local c = by_index[n]
    if c and (c.code or c.desc) and c.code and util.trim(c.code) ~= "" then
      local raw = {}
      for part in (c.code:gsub("[%+\n]", "\n")):gmatch("[^\n]+") do
        if util.trim(part) ~= "" then raw[#raw + 1] = util.trim(part) end
      end
      local e = finish(raw, c.desc, system, #out + 1)
      e.enable = c.enable == "true"
      if e.invalid then bad = bad + 1 end
      out[#out + 1] = e
    end
  end
  return { kind = "cht", cheats = out, bad = bad }
end

--- A line of hex digits that is not a valid code (a broken code, not a name).
function I.looks_like_code(line)
  if not line:match("^[%x%s%-]+$") or not line:find("%d") then return false end
  return #line:gsub("[^%x]", "") >= 5
end

function I.parse_txt(content, system)
  local blocks, cur = {}, nil
  local function flush()
    if cur and #cur.lines > 0 then blocks[#blocks + 1] = cur end
    cur = nil
  end
  for _, raw in ipairs(util.lines(content)) do
    local line = util.trim(raw)
    local header = line:match("^%[(.+)%]$")
    if line == "" then
      -- a blank line ends a block that already has code
      if cur and #cur.lines > 0 then flush() end
    elseif line:match("^[#;]") or line:match("^//") then
      -- comment
    elseif header then
      flush()
      cur = { name = header, lines = {} }
    elseif formats.is_code_line(line) or I.looks_like_code(line) then
      cur = cur or { name = nil, lines = {} }
      cur.lines[#cur.lines + 1] = line
    else
      -- a name line: starts a new cheat (or renames one that has no code yet)
      if cur and #cur.lines == 0 then
        cur.name = line
      else
        flush()
        cur = { name = line, lines = {} }
      end
    end
  end
  flush()
  local out, bad = {}, 0
  for _, b in ipairs(blocks) do
    if #out >= MAX_CHEATS then break end
    local e = finish(b.lines, b.name, system, #out + 1)
    if e.invalid then bad = bad + 1 end
    out[#out + 1] = e
  end
  return { kind = "txt", cheats = out, bad = bad }
end

--- Picks the parser by content.
function I.parse(content, system)
  content = tostring(content or ""):gsub("^\239\187\191", "")
  if content:find("cheat%d+_code") or content:match("^%s*cheats%s*=") or content:find("\ncheats%s*=") then
    return I.parse_cht(content, system)
  end
  return I.parse_txt(content, system)
end

return I
