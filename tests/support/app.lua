-- Test helpers: boot the controller against the fake uz, inspect UI trees.
local mock = require("uz_mock")
local V = require("ui_validator")
local controller = require("app.controller")

local H = { V = V }

local GSA = "0212A4C8 000F423F"

--- entries: list of { name, format, code, group, enabled } stored before the start.
function H.boot(opts, entries)
  opts = opts or {}
  if entries then
    opts.store = opts.store or {}
    local list = {}
    for i, e in ipairs(entries) do
      list[i] = { id = e.id or ("e" .. i), name = e.name, format = e.format or "gsa", code = e.code or GSA,
        group = e.group or "mine", enabled = e.enabled == true, after_reset = e.after_reset }
    end
    opts.store["cheats.axve"] = { v = 1, cheats = list, deleted = {} }
  end
  local m = mock.new(opts)
  local app = controller.new(m.uz)
  app:start()
  m.app = app
  return m, app
end

--- All texts (text blocks, row titles, button labels, ...) of a tree, joined by newlines.
function H.texts(tree, out)
  out = out or {}
  if type(tree) ~= "table" then return out end
  for _, k in ipairs({ "text", "label", "title", "eyebrow", "meta", "sub", "placeholder" }) do
    if type(tree[k]) == "string" then out[#out + 1] = tree[k] end
  end
  for _, r in ipairs(type(tree.rows) == "table" and tree.rows or {}) do H.texts(r, out) end
  for _, c in ipairs(tree.children or {}) do H.texts(c, out) end
  return out
end

function H.has_text(tree, needle)
  for _, s in ipairs(H.texts(tree)) do
    if s:find(needle, 1, true) then return true end
  end
  return false
end

function H.toggles(tree) return V.all(tree, "toggle") end

--- The toggle of the cheat row with this entry id (nil when the row has none).
function H.row_toggle(tree, id) return V.find(tree, "tg_" .. id) end

function H.panel(m) return m.ui.trees.panel end
function H.screen(m) return m.ui.trees.screen end

--- Fills the Enter code form through the textarea events.
function H.type_code(m, name, code, fmt)
  m.action("ta_name", name, "screen")
  m.action("ta_code", code, "screen")
  if fmt then m.action("fmt", fmt, "screen") end
end

H.GSA = GSA
return H
