-- Small helpers shared by the model and the UI (pure Lua, sandbox-safe).
local M = {}

function M.trim(s)
  return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

--- Deep copy of plain data.
function M.copy(v)
  if type(v) ~= "table" then return v end
  local c = {}
  for k, x in pairs(v) do c[k] = M.copy(x) end
  return c
end

--- Lines of a text (CRLF, CR and LF); keeps empty lines so line numbers stay true.
function M.lines(text)
  local out = {}
  text = tostring(text or ""):gsub("\r\n", "\n"):gsub("\r", "\n")
  for line in (text .. "\n"):gmatch("([^\n]*)\n") do out[#out + 1] = line end
  if #out > 0 and out[#out] == "" then out[#out] = nil end
  return out
end

--- Shortens a string to at most n characters (UTF-8 aware) with an ellipsis.
function M.clip(s, n)
  s = tostring(s or "")
  local len = utf8.len(s)
  if not len then return s:sub(1, n) end
  if len <= n then return s end
  return s:sub(1, (utf8.offset(s, n) or (n + 1)) - 1) .. "…"
end

--- Approximate JSON size in bytes of a plain value (for the 256 KiB store limit).
function M.json_size(v)
  local t = type(v)
  if t == "string" then return #v + 2 + select(2, v:gsub('[%c"\\]', "")) end
  if t == "number" or t == "boolean" then return #tostring(v) end
  if t == "table" then
    local n, size = 0, 2
    for k, x in pairs(v) do
      n = n + 1
      size = size + M.json_size(x) + 1
      if type(k) ~= "number" then size = size + #tostring(k) + 3 end
    end
    return size
  end
  return 4
end

--- Lower-case ASCII slug limited to [a-z0-9_-] (store keys: ^[a-z0-9_.-]{1,64}$).
function M.slug(s, max)
  s = tostring(s or ""):lower():gsub("[^a-z0-9_%-]+", "-"):gsub("^%-+", ""):gsub("%-+$", "")
  return s:sub(1, max or 40)
end

--- Counts entries of a list for which fn(entry) is truthy.
function M.count(list, fn)
  local n = 0
  for _, e in ipairs(list) do if fn(e) then n = n + 1 end end
  return n
end

return M
