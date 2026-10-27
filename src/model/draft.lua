-- Analysis of the "Enter code" form: format, line errors, name check (pure Lua).
local formats = require("model.formats")
local library = require("model.library")
local util = require("model.util")

local D = {}

--- draft = { name, fmt ("auto"|format id), code, editing (entry id|nil) }
-- ctx = { system, list (existing entries), supported(format) -> boolean }
-- Returns { fmt, detected, chk, blank, name_state ("empty"|"taken"|"ok"), ready, unsupported }
function D.analyze(draft, ctx)
  local res = { blank = util.trim(draft.code or "") == "" }
  res.detected = formats.detect(draft.code or "", ctx.system)
  if draft.fmt == "auto" then res.fmt = res.detected else res.fmt = draft.fmt end
  local name = util.trim(draft.name or "")
  if name == "" then
    res.name_state = "empty"
  elseif library.name_taken(ctx.list, name, draft.editing) then
    res.name_state = "taken"
  else
    res.name_state = "ok"
  end
  if res.fmt and not res.blank then
    res.chk = formats.check(draft.code, res.fmt, ctx.system)
    res.unsupported = not ctx.supported(res.fmt)
  end
  res.ready = res.name_state == "ok" and res.chk ~= nil and #res.chk.errors == 0 and res.chk.count > 0
  return res
end

return D
