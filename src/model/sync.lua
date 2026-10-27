-- Persistence in the plugin user store (`fb.store`): key per game, revisions, merge on conflict.
-- Stored value: { v = 1, cheats = { entry... }, deleted = { [id] = true } }
local util = require("model.util")
local formats = require("model.formats")

local S = {}

local MAX_BYTES = 240 * 1024 -- the store accepts 256 KiB
local MAX_TOMBSTONES = 200

--- Store key of a game: cheats.<code|hash|title>; nil when the game cannot be told apart.
function S.key(game)
  game = game or {}
  local id
  if type(game.code) == "string" and game.code ~= "" then
    id = util.slug(game.code, 40)
  elseif type(game.sha256) == "string" and game.sha256 ~= "" then
    id = util.slug(game.sha256, 40)
  elseif type(game.title) == "string" and game.title ~= "" then
    id = util.slug(game.title, 40)
  end
  if not id or id == "" then return nil end
  return "cheats." .. id
end

function S.empty() return { v = 1, cheats = {}, deleted = {} } end

local function clean_entry(e)
  if type(e) ~= "table" or type(e.id) ~= "string" or e.id == "" or #e.id > 40 then return nil end
  if type(e.name) ~= "string" or type(e.code) ~= "string" then return nil end
  if not formats.known(e.format) then return nil end
  local group = e.group
  if group ~= "db" and group ~= "imported" then group = "mine" end
  return { id = e.id, name = util.clip(e.name, 60), format = e.format, code = e.code, group = group,
           enabled = e.enabled == true, after_reset = e.after_reset == true or nil }
end

--- Validates a stored value; anything unusable becomes an empty list.
function S.normalize(v)
  local out = S.empty()
  if type(v) ~= "table" then return out end
  local seen = {}
  for _, e in ipairs(type(v.cheats) == "table" and v.cheats or {}) do
    local c = clean_entry(e)
    if c and not seen[c.id] then
      seen[c.id] = true
      out.cheats[#out.cheats + 1] = c
    end
  end
  if type(v.deleted) == "table" then
    for id, flag in pairs(v.deleted) do
      if type(id) == "string" and flag == true then out.deleted[id] = true end
    end
  end
  return out
end

local function same(a, b)
  return a.name == b.name and a.code == b.code and a.format == b.format and a.group == b.group
end

--- Merges two versions by cheat id. `a` (the local version) wins for the same id; when the other
-- version changed the same cheat differently both stay (the other one as "<name> (2)").
function S.merge(a, b)
  a, b = S.normalize(a), S.normalize(b)
  local out = S.empty()
  for id in pairs(a.deleted) do out.deleted[id] = true end
  for id in pairs(b.deleted) do out.deleted[id] = true end
  local by_id, names = {}, {}
  local function add(e)
    out.cheats[#out.cheats + 1] = e
    by_id[e.id] = e
    names[e.name:lower()] = true
  end
  for _, e in ipairs(a.cheats) do
    if not out.deleted[e.id] then add(e) end
  end
  for _, e in ipairs(b.cheats) do
    if not out.deleted[e.id] then
      local mine = by_id[e.id]
      if not mine then
        add(e)
      elseif not same(mine, e) then
        local copy = util.copy(e)
        copy.id = e.id .. "b"
        copy.enabled = false
        local name = e.name .. " (2)"
        local i = 2
        while names[name:lower()] do i = i + 1; name = e.name .. " (" .. i .. ")" end
        copy.name = name
        if not by_id[copy.id] then add(copy) end
      end
    end
  end
  -- keep the tombstone list short
  local n = 0
  for id in pairs(out.deleted) do
    n = n + 1
    if n > MAX_TOMBSTONES then out.deleted[id] = nil end
  end
  return out
end

--- Reads the stored list. Returns data, revision.
function S.read(store, key)
  local ok, value, rev = pcall(store.get, key)
  if not ok then return S.empty(), nil, value end
  return S.normalize(value), rev
end

local function other_versions(store, key)
  local out = {}
  if type(store.conflicts) ~= "function" then return out end
  local ok, list = pcall(store.conflicts, key)
  if not ok or type(list) ~= "table" then return out end
  for _, item in ipairs(list) do
    if type(item) == "table" then
      out[#out + 1] = (type(item.value) == "table") and item.value or item
    end
  end
  return out
end

--- Writes the list. On conflict both versions are merged and written again (once).
-- Returns data (possibly merged), revision, status ("ok"|"merged"|"failed"|"too_big"), message.
function S.save(store, key, data, rev)
  local doc = { v = 1, cheats = data.cheats, deleted = data.deleted }
  if util.json_size(doc) > MAX_BYTES then return data, rev, "too_big" end
  local ok, res, msg = pcall(store.put, key, doc, rev)
  if not ok then return data, rev, "failed", res end
  if res == true then
    local _, new_rev = store.get(key)
    return data, new_rev or rev, "ok"
  end
  if msg ~= "conflict" then return data, rev, "failed", msg end
  local server, srv_rev = store.get(key)
  local merged = S.merge(data, server)
  for _, v in ipairs(other_versions(store, key)) do merged = S.merge(merged, v) end
  doc = { v = 1, cheats = merged.cheats, deleted = merged.deleted }
  if util.json_size(doc) > MAX_BYTES then return merged, srv_rev, "too_big" end
  local ok2, res2, msg2 = pcall(store.put, key, doc, srv_rev)
  if ok2 and res2 == true then
    local _, new_rev = store.get(key)
    return merged, new_rev or srv_rev, "merged"
  end
  return merged, srv_rev, "failed", ok2 and msg2 or res2
end

return S
