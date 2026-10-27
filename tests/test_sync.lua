local t = require("t")
local S = require("model.sync")
local L = require("model.library")
local mock = require("fb_mock")

local function e(id, name, code, extra)
  local x = { id = id, name = name, format = "gsa", code = code or "0212A4C8 000F423F", group = "mine", enabled = false }
  for k, v in pairs(extra or {}) do x[k] = v end
  return x
end

t.case("store key per game", function()
  t.eq(S.key({ code = "AXVE" }), "cheats.axve")
  t.eq(S.key({ code = "000400000011C400" }), "cheats.000400000011c400")
  t.eq(S.key({ sha256 = "AB12" }), "cheats.ab12")
  t.eq(S.key({ title = "Lumen Drift!" }), "cheats.lumen-drift")
  t.eq(S.key({}), nil)
  t.ok(#S.key({ code = ("A"):rep(100) }) <= 64)
  t.ok(S.key({ code = "A/B C" }):match("^[a-z0-9_.-]+$"))
end)

t.case("normalize drops broken entries", function()
  local d = S.normalize({ cheats = { e("a", "One"), { id = "b" }, e("c", "Three", nil, { format = "nope" }), e("a", "Dup") },
    deleted = { x = true, y = "no" } })
  t.eq(#d.cheats, 1)
  t.eq(d.cheats[1].name, "One")
  t.eq(d.deleted, { x = true })
  t.eq(S.normalize("garbage"), S.empty())
end)

t.case("merge keeps both sides by cheat id", function()
  local a = { cheats = { e("a", "One", nil, { enabled = true }), e("b", "Two") }, deleted = {} }
  local b = { cheats = { e("a", "One"), e("c", "Three") }, deleted = {} }
  local m = S.merge(a, b)
  t.eq(#m.cheats, 3)
  t.eq(m.cheats[1].enabled, true) -- local state wins
  t.eq(m.cheats[3].id, "c")
end)

t.case("merge: same id changed on both sides keeps both", function()
  local a = { cheats = { e("a", "One", "0212A4C8 000F423F") }, deleted = {} }
  local b = { cheats = { e("a", "One", "0212A4C8 00000001", { enabled = true }) }, deleted = {} }
  local m = S.merge(a, b)
  t.eq(#m.cheats, 2)
  t.eq(m.cheats[1].code, "0212A4C8 000F423F")
  t.eq(m.cheats[2].name, "One (2)")
  t.eq(m.cheats[2].code, "0212A4C8 00000001")
  t.eq(m.cheats[2].enabled, false)
end)

t.case("merge: deleted cheats stay deleted", function()
  local a = { cheats = {}, deleted = { b = true } }
  local b = { cheats = { e("b", "Two"), e("c", "Three") }, deleted = {} }
  local m = S.merge(a, b)
  t.eq(#m.cheats, 1)
  t.eq(m.cheats[1].id, "c")
  t.eq(m.deleted, { b = true })
end)

t.case("save writes with the revision and returns the new one", function()
  local m = mock.new()
  local data = { cheats = { e("a", "One") }, deleted = {} }
  local d, rev, status = S.save(m.fb.store, "cheats.axve", data, nil)
  t.eq(status, "ok")
  t.eq(rev, 1)
  local back, rev2 = S.read(m.fb.store, "cheats.axve")
  t.eq(rev2, 1)
  t.eq(back.cheats[1].name, "One")
  _, rev, status = S.save(m.fb.store, "cheats.axve", data, rev)
  t.eq(status, "ok"); t.eq(rev, 2)
end)

t.case("save on conflict merges both versions and writes again", function()
  local m = mock.new()
  local _, rev = S.save(m.fb.store, "cheats.axve", { cheats = { e("a", "One") }, deleted = {} }, nil)
  -- another device adds "Remote" meanwhile
  m.store_external("cheats.axve", { v = 1, cheats = { e("a", "One"), e("r", "Remote") }, deleted = {} })
  local mine = { cheats = { e("a", "One"), e("l", "Local") }, deleted = {} }
  local merged, rev2, status = S.save(m.fb.store, "cheats.axve", mine, rev)
  t.eq(status, "merged")
  t.eq(#merged.cheats, 3)
  local back = S.read(m.fb.store, "cheats.axve")
  t.eq(#back.cheats, 3)
  t.ok(rev2 > rev)
  t.eq(m.fb.store.conflicts("cheats.axve"), {})
end)

t.case("save refuses a value above the store limit", function()
  local m = mock.new()
  local big = { cheats = {}, deleted = {} }
  for i = 1, 400 do big.cheats[i] = e("id" .. i, "Cheat number " .. i, ("0212A4C8 000F423F\n"):rep(40)) end
  local _, _, status = S.save(m.fb.store, "cheats.axve", big, nil)
  t.eq(status, "too_big")
  t.eq(m.store.puts, nil)
end)

t.case("library: names, groups, search", function()
  local list = { e("a", "Infinite Boost"), e("b", "Lumen Walk", nil, { group = "imported" }),
    e("c", "Coral Hop", nil, { group = "db", format = "cb" }) }
  t.ok(L.name_taken(list, " infinite boost "))
  t.ok(not L.name_taken(list, "Infinite Boost", "a"))
  t.eq(L.unique_name(list, "Lumen Walk"), "Lumen Walk (2)")
  t.eq(L.unique_name(list, "New"), "New")
  local g = L.groups(list, "")
  t.eq(#g.db, 1); t.eq(#g.mine, 1); t.eq(#g.imported, 1)
  g = L.groups(list, "boo")
  t.eq(#g.mine, 1); t.eq(#g.db, 0)
  g = L.groups(list, "cb") -- the format tag matches too
  t.eq(#g.db, 1)
  t.eq(L.on_count(list), 0)
  local id1, id2 = L.new_id(5), L.new_id(5)
  t.ok(id1 ~= id2)
  t.ok(#id1 <= 20 and id1:match("^[a-z0-9]+$"))
end)
