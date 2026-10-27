-- The Cheats tab in the game's side panel (design 11a-1, 11a-2, 11a-3).
local formats = require("model.formats")
local library = require("model.library")

local P = {}

local GROUP_KEYS = { db = "group_db", mine = "group_mine", imported = "group_imported" }

local function text(s, style, tone, extra)
  local b = { type = "text", text = s, style = style }
  if tone then b.tone = tone end
  for k, v in pairs(extra or {}) do b[k] = v end
  return b
end

local function entry_row(v, e)
  local t = v.t
  local supported = v.supported(e.format)
  local meta, meta_tone
  if not supported then
    meta, meta_tone = t("not_supported", { core = v.core_name }), "warning"
  elseif v.rejected[e.id] then
    meta, meta_tone = t("rejected", { reason = v.rejected[e.id] }), "danger"
  elseif e.enabled and e.after_reset then
    meta = t("after_reset_hint")
  end
  local name = text(e.name, "body", nil, { wrap = true })
  local left = name
  if meta then
    left = { type = "column", gap = 4, children = { name, text(meta, "meta", meta_tone) } }
  end
  local children = { left, { type = "badge", text = formats.tags[e.format] or "?" } }
  if e.after_reset then children[#children + 1] = { type = "badge", text = t("tag_after_reset"), tone = "info" } end
  if v.edit then
    children[#children + 1] = { type = "button", label = t("edit"), action = "edit:" .. e.id, variant = "quiet" }
    children[#children + 1] = { type = "button", label = t("remove"), action = "remove:" .. e.id, variant = "danger",
      confirm = { title = t("remove_title", { name = e.name }), text = t("remove_text"),
                  confirm_label = t("remove"), danger = true } }
  elseif v.blocked or not supported then
    children[#children + 1] = { type = "badge", text = t("off") }
  else
    children[#children + 1] = { type = "toggle", id = "tg_" .. e.id, action = "toggle:" .. e.id, checked = e.enabled }
  end
  return { type = "row", id = "row_" .. e.id, gap = 8, align = "center", children = children }
end

local function group_section(v, g, list)
  local t = v.t
  local limit = v.limits[g] or v.page
  local rows = {}
  for i = 1, math.min(#list, limit) do rows[#rows + 1] = entry_row(v, list[i]) end
  if #list > limit then
    rows[#rows + 1] = { type = "button", label = t("show_more", { n = #list - limit }), action = "more:" .. g,
                        variant = "quiet" }
  end
  return { type = "section", id = "grp_" .. g, title = t(GROUP_KEYS[g]) .. " · " .. #list, children = rows }
end

--- v: { t, game_title, on_count, blocked, supported(fmt), core_name, rejected, edit, query, groups, total,
---      limits, page, state ("ok"|"no_game"|"unavailable"), note }
function P.build(v)
  local t = v.t
  if v.state == "unavailable" then
    return { type = "column", gap = 12, children = {
      { type = "empty", title = t("unavailable_title"), text = t("unavailable_text"), tone = "warning" } } }
  elseif v.state == "no_game" then
    return { type = "column", gap = 12, children = {
      { type = "empty", title = t("no_game_title"), text = t("no_game_text") } } }
  end

  local header = { text(t("tab_eyebrow"), "eyebrow") }
  if v.blocked then
    header[#header + 1] = { type = "badge", text = t("off_in_run"), tone = "warning" }
  else
    header[#header + 1] = { type = "badge", text = t("n_on", { n = v.on_count }), tone = v.on_count > 0 and "ok" or "neutral" }
  end
  local kids = { { type = "row", gap = 8, align = "center", children = header } }

  if v.blocked then
    kids[#kids + 1] = { type = "card", id = "blocked", eyebrow = t("blocked_title"), children = {
      text(t("blocked_text"), "meta"),
      { type = "button", id = "btn_recheck", label = t("check_again"), action = "recheck", variant = "quiet" } } }
  end

  kids[#kids + 1] = { type = "row", gap = 8, align = "center", children = {
    { type = "button", id = "btn_add", label = t("add_cheat"), action = "add", variant = "primary" },
    { type = "button", id = "btn_db", label = t("cheat_database"), action = "open_db", variant = "secondary" },
  } }

  if v.total == 0 then
    kids[#kids + 1] = { type = "empty", id = "empty_none", title = t("empty_title", { game = v.game_title }),
      text = t("empty_text"), action_label = t("add_cheat"), action = "add" }
  else
    kids[#kids + 1] = { type = "textfield", id = "search", action = "search", text = v.query,
      placeholder = t("search_placeholder") }
    local tools = { { type = "chip", id = "chip_edit", text = t("edit_list"), action = "edit_mode", selected = v.edit } }
    if v.on_count > 0 and not v.blocked then
      tools[#tools + 1] = { type = "chip", id = "chip_all_off", text = t("turn_all_off"), action = "all_off" }
    end
    kids[#kids + 1] = { type = "row", gap = 8, align = "center", children = tools }
    local shown = 0
    for _, g in ipairs(library.GROUPS) do
      local list = v.groups[g]
      if #list > 0 then
        shown = shown + #list
        kids[#kids + 1] = group_section(v, g, list)
      end
    end
    if shown == 0 then
      kids[#kids + 1] = { type = "empty", id = "empty_match", title = t("no_match", { query = v.query }),
        action_label = t("clear_search"), action = "search_clear" }
    end
  end

  if v.note then kids[#kids + 1] = text(v.note, "meta", "warning", { id = "note" }) end
  return { type = "column", gap = 12, children = kids }
end

return P
