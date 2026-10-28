-- Cheat code formats: shapes, validation, detection and normalizing (pure Lua).
--
-- Format ids are the ones of `uz.cheats.formats()`:
--   raw        AAAAAAAA VV            address (8 hex) and one byte (2 hex)
--   gsa        XXXXXXXX YYYYYYYY      GameShark Advance, 8 + 8 hex (or 12 hex in one group)
--   cb         XXXXXXXX YYYY          CodeBreaker, 8 + 4 hex
--   ar_gba     XXXXXXXX YYYYYYYY      Action Replay GBA, 8 + 8 hex (or 12 hex in one group)
--   ar_ds      XXXXXXXX YYYYYYYY      Action Replay DS, 8 + 8 hex
--   gateway    XXXXXXXX YYYYYYYY      Gateway (3DS), 8 + 8 hex
--   game_genie XXX-XXX[-XXX]          Game Genie (Game Boy), hex groups of 3
local util = require("model.util")

local F = {}

F.order = { "gsa", "cb", "ar_gba", "ar_ds", "game_genie", "gateway", "raw" }
F.tags = { gsa = "GSA", cb = "CB", ar_gba = "AR GBA", ar_ds = "AR DS", game_genie = "GG", gateway = "GATEWAY", raw = "RAW" }
-- Group sizes of the accepted line shapes (alternatives per format).
local SHAPES = {
  raw = { { 8, 2 } },
  gsa = { { 8, 8 }, { 12 } },
  cb = { { 8, 4 } },
  ar_gba = { { 8, 8 }, { 12 } },
  ar_ds = { { 8, 8 } },
  gateway = { { 8, 8 } },
  game_genie = { { 3, 3 }, { 3, 3, 3 } },
}
-- Formats that make sense per system, in detection priority.
F.by_system = {
  gb = { "game_genie", "raw" },
  gbc = { "game_genie", "raw" },
  gba = { "gsa", "cb", "ar_gba", "raw" },
  nds = { "ar_ds", "raw" },
  ["3ds"] = { "gateway", "raw" },
}
local MAX_LINES = 64

function F.known(format) return SHAPES[format] ~= nil end

--- Plausible formats for a system (all formats for an unknown one).
function F.for_system(system)
  return F.by_system[tostring(system or ""):lower()] or F.order
end

--- Short text of the shape, e.g. "8 + 8" (Game Genie: "3-3 or 3-3-3").
function F.shape_text(format)
  local alts = {}
  for _, g in ipairs(SHAPES[format] or {}) do
    local parts = {}
    for i, n in ipairs(g) do parts[i] = tostring(n) end
    alts[#alts + 1] = table.concat(parts, format == "game_genie" and "-" or " + ")
  end
  if format == "game_genie" then return table.concat(alts, " or ") end
  return alts[1] or ""
end

local function err(key, vars) return nil, key, vars end

--- Validates one code line for a format. Returns true or nil, error key, vars.
function F.validate_line(format, line)
  local shapes = SHAPES[format]
  if not shapes then return err("err_format") end
  line = util.trim(line)
  if line == "" then return err("err_empty") end
  local tag = F.tags[format]
  local vars = { tag = tag, shape = F.shape_text(format) }
  -- illegal characters first: the first one that is not a hex digit
  local allowed = format == "game_genie" and "^[%x%s%-]*$" or "^[%x%s]*$"
  if not line:match(allowed) then
    local bad = line:match(format == "game_genie" and "[^%x%s%-]" or "[^%x%s]")
    vars.char = bad
    return err("err_not_hex", vars)
  end
  local groups = {}
  if format == "game_genie" then
    for g in line:gmatch("[^%-%s]+") do groups[#groups + 1] = g end
    if line:find("%s") then return err("err_shape", vars) end
  else
    for g in line:gmatch("%S+") do groups[#groups + 1] = g end
  end
  for _, shape in ipairs(shapes) do
    if #shape == #groups then
      local ok = true
      for i, n in ipairs(shape) do if #groups[i] ~= n then ok = false end end
      if ok then return true end
    end
  end
  -- explain against the first shape with the same group count, else the primary one
  local want
  for _, shape in ipairs(shapes) do if #shape == #groups then want = shape; break end end
  if not want then
    if #groups == 1 and #shapes[1] == 2 and format ~= "game_genie" then
      vars.n = #groups[1]
      return err("err_one_group", vars)
    end
    vars.n = #groups
    return err("err_group_count", vars)
  end
  for i, n in ipairs(want) do
    if #groups[i] ~= n then
      vars.n, vars.want = #groups[i], n
      if format == "game_genie" then
        vars.pos = i
        return err("err_gg_group", vars)
      end
      return err(i == 1 and (#want == 1 and "err_digits_total" or "err_digits_before") or "err_digits_after", vars)
    end
  end
  return err("err_shape", vars)
end

--- Normalized code line: upper case, single spaces (Game Genie: dashes).
function F.normalize_line(format, line)
  line = util.trim(line):upper()
  if format == "game_genie" then
    local g = {}
    for x in line:gmatch("[^%-%s]+") do g[#g + 1] = x end
    return table.concat(g, "-")
  end
  return (line:gsub("%s+", " "))
end

--- True when the line is a valid code of any format.
function F.is_code_line(line)
  for _, f in ipairs(F.order) do
    if F.validate_line(f, line) then return true end
  end
  return false
end

--- Non-empty lines with their original line numbers: { {n=, text=}, ... }.
function F.code_lines(text)
  local out = {}
  for i, l in ipairs(util.lines(text)) do
    if util.trim(l) ~= "" then out[#out + 1] = { n = i, text = l } end
  end
  return out
end

local function all_valid(format, lines)
  for _, l in ipairs(lines) do
    if not F.validate_line(format, l.text) then return false end
  end
  return #lines > 0
end

--- Formats under which every line is valid, most likely first (system priority, then the rest).
function F.candidates(text, system)
  local lines = F.code_lines(text)
  local out, seen = {}, {}
  for _, f in ipairs(F.for_system(system)) do
    if all_valid(f, lines) then out[#out + 1] = f; seen[f] = true end
  end
  for _, f in ipairs(F.order) do
    if not seen[f] and all_valid(f, lines) then out[#out + 1] = f end
  end
  return out
end

--- Detects the format of a code text. Returns the format id or nil. Formats of the system win.
function F.detect(text, system)
  local c = F.candidates(text, system)
  return c[1]
end

--- Checks a code text against a chosen format.
-- Returns { lines = {normalized...}, errors = { {n=, key=, vars=} }, count = n, other = format|nil }
-- `other` is a different format under which every line would be valid (the "wrong format" hint).
function F.check(text, format, system)
  local lines = F.code_lines(text)
  local res = { lines = {}, errors = {}, count = #lines }
  if #lines > MAX_LINES then
    res.errors[1] = { n = lines[MAX_LINES + 1].n, key = "err_too_many_lines", vars = { max = MAX_LINES } }
    return res
  end
  for _, l in ipairs(lines) do
    local ok, key, vars = F.validate_line(format, l.text)
    if ok then
      res.lines[#res.lines + 1] = F.normalize_line(format, l.text)
    else
      res.errors[#res.errors + 1] = { n = l.n, key = key, vars = vars }
    end
  end
  if #res.errors > 0 then
    local c = F.candidates(text, system)
    for _, f in ipairs(c) do
      if f ~= format then res.other = f; break end
    end
  end
  return res
end

return F
