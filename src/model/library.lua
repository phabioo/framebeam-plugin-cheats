-- The cheat list of one game: entries, groups, names, search (pure Lua).
local util = require("model.util")
local formats = require("model.formats")

local L = {}

L.GROUPS = { "db", "mine", "imported" } -- display order
L.MAX_CHEATS = 1000

local counter = 0

--- New unique-enough entry id ([a-z0-9], <= 20 chars).
function L.new_id(clock)
  counter = counter + 1
  return string.format("c%x%03x%04x", (clock or 0) % 0xffffff, counter % 0x1000, math.random(0, 0xffff))
end

--- Entry: { id, name, format, code (lines joined by "\n"), group, enabled, after_reset }
function L.make(fields, clock)
  return {
    id = fields.id or L.new_id(clock),
    name = util.clip(util.trim(fields.name or ""), 60),
    format = fields.format,
    code = fields.code or "",
    group = fields.group or "mine",
    enabled = fields.enabled == true,
    after_reset = fields.after_reset == true or nil,
  }
end

local function key(name) return util.trim(name):lower() end

--- True when another entry (not `except_id`) already has this name.
function L.name_taken(list, name, except_id)
  local k = key(name)
  for _, e in ipairs(list) do
    if e.id ~= except_id and key(e.name) == k then return true end
  end
  return false
end

--- A free name: "Name", else "Name (2)", "Name (3)", ...
function L.unique_name(list, name, taken_extra)
  local function used(n)
    if L.name_taken(list, n) then return true end
    return taken_extra ~= nil and taken_extra[key(n)] == true
  end
  if not used(name) then return name end
  local i = 2
  while used(name .. " (" .. i .. ")") do i = i + 1 end
  return name .. " (" .. i .. ")"
end

function L.find(list, id)
  for i, e in ipairs(list) do if e.id == id then return e, i end end
  return nil
end

function L.matches(entry, query)
  query = util.trim(query or ""):lower()
  if query == "" then return true end
  return entry.name:lower():find(query, 1, true) ~= nil
    or (formats.tags[entry.format] or ""):lower():find(query, 1, true) ~= nil
end

--- Entries per group after the search filter: { db = {...}, mine = {...}, imported = {...} }
function L.groups(list, query)
  local g = { db = {}, mine = {}, imported = {} }
  for _, e in ipairs(list) do
    if L.matches(e, query) then
      local bucket = g[e.group] or g.mine
      bucket[#bucket + 1] = e
    end
  end
  return g
end

--- Number of entries that are on.
function L.on_count(list)
  return util.count(list, function(e) return e.enabled end)
end

return L
