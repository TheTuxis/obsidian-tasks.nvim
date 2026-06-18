local task_mod = require("obsidian-tasks.task")

local M = {}
local _config = {}

function M.setup(cfg)
  _config = cfg
end

-- Status ↔ name conversions
local STATUS_TO_NAME = {
  [task_mod.STATUS.TODO]        = "todo",
  [task_mod.STATUS.DONE]        = "done",
  [task_mod.STATUS.CANCELLED]   = "cancelled",
  [task_mod.STATUS.IN_PROGRESS] = "in_progress",
  [task_mod.STATUS.FORWARDED]   = "forwarded",
}
local NAME_TO_STATUS = {}
for s, n in pairs(STATUS_TO_NAME) do NAME_TO_STATUS[n] = s end

-- Priority ↔ name conversions
local PRIORITY_TO_NAME = {
  [task_mod.PRIORITY.HIGHEST] = "highest",
  [task_mod.PRIORITY.HIGH]    = "high",
  [task_mod.PRIORITY.MEDIUM]  = "medium",
  [task_mod.PRIORITY.NONE]    = "none",
  [task_mod.PRIORITY.LOW]     = "low",
  [task_mod.PRIORITY.LOWEST]  = "lowest",
}
local NAME_TO_PRIORITY = {}
for p, n in pairs(PRIORITY_TO_NAME) do NAME_TO_PRIORITY[n] = p end

-- Priority emoji bytes for line reconstruction
local PRIORITY_EMOJI = {
  [task_mod.PRIORITY.HIGHEST] = "\xF0\x9F\x94\xBA", -- 🔺
  [task_mod.PRIORITY.HIGH]    = "\xE2\x8F\xAB",      -- ⏫
  [task_mod.PRIORITY.MEDIUM]  = "\xF0\x9F\x94\xBC", -- 🔼
  [task_mod.PRIORITY.LOW]     = "\xF0\x9F\x94\xBD", -- 🔽
  [task_mod.PRIORITY.LOWEST]  = "\xE2\x8F\xAC",      -- ⏬
}

local function fmt_date(dt)
  return dt and dt.raw or ""
end

local function parse_date_str(s)
  s = vim.trim(s or "")
  if s == "" then return nil end
  local y, m, d = s:match("^(%d%d%d%d)-(%d%d)-(%d%d)$")
  if not y then return nil end
  return { year = tonumber(y), month = tonumber(m), day = tonumber(d), raw = s }
end

-- Reconstruct the raw markdown task line from an updated task table.
local function task_to_line(t)
  local ch   = task_mod.status_char(t.status)
  local line = t.indentation .. t.list_marker .. " [" .. ch .. "] " .. t.description

  if t.priority ~= task_mod.PRIORITY.NONE then
    local icon = PRIORITY_EMOJI[t.priority]
    if icon then line = line .. " " .. icon end
  end

  -- Canonical metadata order (matches obsidian-tasks)
  if t.recurrence     then line = line .. " \xF0\x9F\x94\x81 " .. t.recurrence end
  if t.created_date   then line = line .. " \xE2\x9E\x95 "     .. t.created_date.raw end
  if t.start_date     then line = line .. " \xF0\x9F\x9B\xAB " .. t.start_date.raw end
  if t.scheduled_date then line = line .. " \xE2\x8F\xB3 "     .. t.scheduled_date.raw end
  if t.due_date       then line = line .. " \xF0\x9F\x93\x85 " .. t.due_date.raw end
  if t.done_date      then line = line .. " \xE2\x9C\x85 "     .. t.done_date.raw end
  if t.cancelled_date then line = line .. " \xE2\x9D\x8C "     .. t.cancelled_date.raw end

  if t.id then line = line .. " \xF0\x9F\x86\x94 " .. t.id end

  if t.depends_on and #t.depends_on > 0 then
    line = line .. " \xE2\x9B\x94 " .. table.concat(t.depends_on, ",")
  end

  if t.on_completion then line = line .. " \xF0\x9F\x8F\x81 " .. t.on_completion end

  if #t.tags > 0 then
    line = line .. " " .. table.concat(t.tags, " ")
  end

  if t.block_link then line = line .. " ^" .. t.block_link end

  return line
end

-- Parse editor form lines back into an updated task table.
-- Fields whose label is unrecognized or blank fall back to the original.
local function parse_form(form_lines, original)
  local fields = {}
  for _, l in ipairs(form_lines) do
    -- "fieldname:   value"  — label must start at column 0
    local key, val = l:match("^([a-z_]+):%s*(.-)%s*$")
    if key then fields[key] = val end
  end

  local t = vim.deepcopy(original)

  if fields.description and fields.description ~= "" then
    t.description = fields.description
  end

  local s = NAME_TO_STATUS[(fields.status or ""):lower()]
  if s then t.status = s end

  local p = NAME_TO_PRIORITY[(fields.priority or ""):lower()]
  if p ~= nil then t.priority = p end

  t.due_date        = parse_date_str(fields.due)
  t.scheduled_date  = parse_date_str(fields.scheduled)
  t.start_date      = parse_date_str(fields.start)
  t.done_date       = parse_date_str(fields.done)
  t.created_date    = parse_date_str(fields.created)
  t.recurrence      = (fields.recurrence ~= "" and fields.recurrence) or nil

  local tags_raw = vim.trim(fields.tags or "")
  t.tags = tags_raw ~= "" and vim.split(tags_raw, "%s+", { trimempty = true }) or {}

  local id_val = vim.trim(fields.id or "")
  t.id = id_val ~= "" and id_val or nil

  return t
end

-- Write new_line back to the task's source file at line_number (1-based).
local function write_line(file_path, line_number, new_line)
  -- Prefer editing a loaded buffer so undo history is preserved.
  local bufnr = vim.fn.bufnr(file_path)
  if bufnr ~= -1 and vim.api.nvim_buf_is_loaded(bufnr) then
    vim.api.nvim_buf_set_lines(bufnr, line_number - 1, line_number, false, { new_line })
    return true
  end

  -- File not open — patch on disk.
  local f = io.open(file_path, "r")
  if not f then return false, "cannot open " .. file_path end
  local lines = {}
  for l in f:lines() do table.insert(lines, l) end
  f:close()

  if line_number < 1 or line_number > #lines then
    return false, "line " .. line_number .. " is out of range"
  end
  lines[line_number] = new_line

  local out = io.open(file_path, "w")
  if not out then return false, "cannot write " .. file_path end
  for _, l in ipairs(lines) do out:write(l .. "\n") end
  out:close()
  return true
end

-- Open a floating form editor for a task table.
function M.open(t)
  local fw     = _config.floating_window or {}
  local border = fw.border or "rounded"

  -- All labels are padded to 14 characters so values align.
  local function field(name, value)
    return string.format("%-14s%s", name .. ":", value or "")
  end

  local form_lines = {
    field("description", t.description),
    field("status",      STATUS_TO_NAME[t.status] or "todo"),
    field("priority",    PRIORITY_TO_NAME[t.priority] or "none"),
    field("due",         fmt_date(t.due_date)),
    field("scheduled",   fmt_date(t.scheduled_date)),
    field("start",       fmt_date(t.start_date)),
    field("done",        fmt_date(t.done_date)),
    field("created",     fmt_date(t.created_date)),
    field("recurrence",  t.recurrence or ""),
    field("tags",        table.concat(t.tags or {}, " ")),
    field("id",          t.id or ""),
  }

  -- Compute window width to fit the longest line + padding.
  local width = 62
  for _, l in ipairs(form_lines) do
    local w = vim.fn.strdisplaywidth(l) + 4
    if w > width then width = w end
  end
  width = math.min(width, fw.max_width or 80)

  local sep = string.rep("─", width - 2)
  table.insert(form_lines, sep)
  table.insert(form_lines, "  [CR] save  ·  [:w] save  ·  [q/<Esc>] discard")
  table.insert(form_lines, "")
  table.insert(form_lines, "  status:    todo · done · cancelled · in_progress · forwarded")
  table.insert(form_lines, "  priority:  highest · high · medium · none · low · lowest")
  table.insert(form_lines, "  dates:     YYYY-MM-DD  (leave blank to remove)")

  local height = math.min(#form_lines, fw.max_height or 30)

  local ui  = vim.api.nvim_list_uis()[1]
  local col = math.floor((ui.width  - width)  / 2)
  local row = math.floor((ui.height - height) / 2)

  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, form_lines)
  vim.bo[bufnr].buftype   = "acwrite"
  vim.bo[bufnr].bufhidden = "wipe"
  vim.bo[bufnr].filetype  = "obsidian-tasks-editor"

  local winnr = vim.api.nvim_open_win(bufnr, true, {
    relative  = "editor",
    row       = row,
    col       = col,
    width     = width,
    height    = height,
    border    = border,
    title     = " Edit Task ",
    title_pos = "center",
    style     = "minimal",
  })

  vim.wo[winnr].wrap       = false
  vim.wo[winnr].cursorline = true

  local function save_and_close()
    local edited   = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    local updated  = parse_form(edited, t)
    local new_line = task_to_line(updated)

    local ok, err = write_line(t.file_path, t.line_number, new_line)
    if ok then
      require("obsidian-tasks.index").update_file(t.file_path)
      vim.notify("obsidian-tasks: task updated", vim.log.levels.INFO)
    else
      vim.notify("obsidian-tasks: " .. (err or "write failed"), vim.log.levels.ERROR)
    end

    if vim.api.nvim_win_is_valid(winnr) then
      vim.api.nvim_win_close(winnr, true)
    end
  end

  local function discard()
    if vim.api.nvim_win_is_valid(winnr) then
      vim.api.nvim_win_close(winnr, true)
    end
  end

  vim.keymap.set("n", "<CR>",  save_and_close, { buffer = bufnr, nowait = true, silent = true })
  vim.keymap.set("n", "q",     discard,        { buffer = bufnr, nowait = true, silent = true })
  vim.keymap.set("n", "<Esc>", discard,        { buffer = bufnr, nowait = true, silent = true })

  -- :w triggers save via BufWriteCmd (buftype=acwrite)
  vim.api.nvim_create_autocmd("BufWriteCmd", {
    buffer   = bufnr,
    once     = true,
    callback = save_and_close,
  })

  -- Place cursor at end of the description value and start insert
  vim.schedule(function()
    if vim.api.nvim_win_is_valid(winnr) then
      local desc_line = form_lines[1]
      vim.api.nvim_win_set_cursor(winnr, { 1, #desc_line })
      vim.cmd("startinsert!")
    end
  end)
end

-- Open editor for the task on the current cursor line.
function M.open_at_cursor()
  local bufnr = vim.api.nvim_get_current_buf()
  local row   = vim.api.nvim_win_get_cursor(0)[1]
  local line  = vim.api.nvim_buf_get_lines(bufnr, row - 1, row, false)[1] or ""
  local fpath = vim.api.nvim_buf_get_name(bufnr)

  local t = require("obsidian-tasks.parser").parse_line(line, fpath, row, nil)
  if not t then
    vim.notify("obsidian-tasks: no task on this line", vim.log.levels.WARN)
    return
  end

  M.open(t)
end

return M
