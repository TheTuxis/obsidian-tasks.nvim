local task_mod = require("obsidian-tasks.task")

local M = {}
local _config = {}

function M.setup(cfg)
  _config = cfg
end

-- Priority emoji bytes (same as editor.lua — kept local to avoid circular deps)
local PRIORITY_EMOJI = {
  [task_mod.PRIORITY.HIGHEST] = "\xF0\x9F\x94\xBA", -- 🔺
  [task_mod.PRIORITY.HIGH]    = "\xE2\x8F\xAB",      -- ⏫
  [task_mod.PRIORITY.MEDIUM]  = "\xF0\x9F\x94\xBC", -- 🔼
  [task_mod.PRIORITY.LOW]     = "\xF0\x9F\x94\xBD", -- 🔽
  [task_mod.PRIORITY.LOWEST]  = "\xE2\x8F\xAC",      -- ⏬
}

local NAME_TO_PRIORITY = {
  highest = task_mod.PRIORITY.HIGHEST,
  high    = task_mod.PRIORITY.HIGH,
  medium  = task_mod.PRIORITY.MEDIUM,
  none    = task_mod.PRIORITY.NONE,
  low     = task_mod.PRIORITY.LOW,
  lowest  = task_mod.PRIORITY.LOWEST,
}

local function parse_date_str(s)
  s = vim.trim(s or "")
  if s == "" then return nil end
  return s:match("^%d%d%d%d%-%d%d%-%d%d$") and s or nil
end

-- Resolve the path for today's (or a given date's) daily file.
function M.daily_file_path(date_t)
  local cap = (_config.capture or {})
  if not cap.path then return nil end

  date_t = date_t or os.date("*t")
  local dir_fmt  = cap.dir_format  or "%Y/%m"
  local file_fmt = cap.file_format or "%Y-%m-%d Tasks"

  local sub_dir  = os.date(dir_fmt,  os.time(date_t))
  local filename = os.date(file_fmt, os.time(date_t)) .. ".md"

  return cap.path .. "/" .. sub_dir .. "/" .. filename
end

-- Create the daily file with frontmatter + section header if it doesn't exist.
function M.ensure_daily_file(path, date_str)
  if vim.fn.filereadable(path) == 1 then return end

  vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")

  local cap     = _config.capture or {}
  local section = cap.section or "Inbox"

  local lines = {
    "---",
    "id: " .. date_str .. " Tasks",
    "aliases: []",
    "tags:",
    "  - task",
    "full-date: " .. date_str,
    "---",
    "",
    "## " .. section,
    "",
  }

  local f = io.open(path, "w")
  if not f then
    vim.notify("obsidian-tasks: cannot create " .. path, vim.log.levels.ERROR)
    return
  end
  for _, l in ipairs(lines) do f:write(l .. "\n") end
  f:close()
end

-- Append task_line to file_path, under the given section header if provided.
function M.append_task(file_path, task_line, section)
  local f = io.open(file_path, "r")
  if not f then
    vim.notify("obsidian-tasks: cannot read " .. file_path, vim.log.levels.ERROR)
    return
  end
  local lines = {}
  for l in f:lines() do table.insert(lines, l) end
  f:close()

  local insert_at = #lines + 1  -- default: after last line

  if section then
    local header = "## " .. section
    local section_line = nil

    -- Find the section header
    for i, l in ipairs(lines) do
      if l == header then
        section_line = i
        break
      end
    end

    if section_line then
      -- Find insertion point: after the last task line in this section
      local last_task = section_line
      for i = section_line + 1, #lines do
        local l = lines[i]
        -- Stop at the next section header
        if l:match("^##") then break end
        if l:match("^%s*[-*+]%s+%[") then
          last_task = i
        end
      end
      insert_at = last_task + 1
    end
  end

  table.insert(lines, insert_at, task_line)

  local out = io.open(file_path, "w")
  if not out then
    vim.notify("obsidian-tasks: cannot write " .. file_path, vim.log.levels.ERROR)
    return
  end
  for _, l in ipairs(lines) do out:write(l .. "\n") end
  out:close()

  -- Reload the buffer if it's open
  local bufnr = vim.fn.bufnr(file_path)
  if bufnr ~= -1 and vim.api.nvim_buf_is_loaded(bufnr) then
    vim.api.nvim_buf_call(bufnr, function()
      vim.cmd("silent! checktime")
    end)
  end
end

-- Construct the task markdown line from parsed form fields.
local function build_task_line(fields)
  local desc = vim.trim(fields.description or "")
  if desc == "" then return nil end

  local line = "- [ ] " .. desc

  local priority = NAME_TO_PRIORITY[(fields.priority or "none"):lower()]
  if priority and priority ~= task_mod.PRIORITY.NONE then
    local icon = PRIORITY_EMOJI[priority]
    if icon then line = line .. " " .. icon end
  end

  local scheduled = parse_date_str(fields.scheduled)
  if scheduled then line = line .. " \xE2\x8F\xB3 " .. scheduled end

  local due = parse_date_str(fields.due)
  if due then line = line .. " \xF0\x9F\x93\x85 " .. due end

  -- Always stamp created date
  line = line .. " \xE2\x9E\x95 " .. os.date("%Y-%m-%d")

  local tags_raw = vim.trim(fields.tags or "")
  if tags_raw ~= "" then line = line .. " " .. tags_raw end

  return line
end

-- Parse "fieldname:  value" lines from the form buffer.
local function parse_form(form_lines)
  local fields = {}
  for _, l in ipairs(form_lines) do
    local key, val = l:match("^([a-z_]+):%s*(.-)%s*$")
    if key then fields[key] = val end
  end
  return fields
end

-- Open the quick-capture floating form.
function M.open()
  local fw     = (_config.floating_window or {})
  local border = fw.border or "rounded"

  local function field(name, value)
    return string.format("%-14s%s", name .. ":", value or "")
  end

  local form_lines = {
    field("description", ""),
    field("priority",    "none"),
    field("due",         ""),
    field("scheduled",   ""),
    field("tags",        ""),
  }

  local width = 56
  local sep   = string.rep("─", width - 2)
  table.insert(form_lines, sep)
  table.insert(form_lines, "  [CR] save  ·  [q / Esc] discard")
  table.insert(form_lines, "")
  table.insert(form_lines, "  priority:  highest · high · medium · none · low · lowest")
  table.insert(form_lines, "  dates:     YYYY-MM-DD  (leave blank to skip)")

  local height = #form_lines

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
    title     = " Quick Capture ",
    title_pos = "center",
    style     = "minimal",
  })

  vim.wo[winnr].wrap       = false
  vim.wo[winnr].cursorline = true

  local function save_and_close()
    local cap = _config.capture or {}
    if not cap.path then
      vim.notify("obsidian-tasks: capture.path is not configured", vim.log.levels.ERROR)
      return
    end

    local edited  = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    local fields  = parse_form(edited)
    local task_line = build_task_line(fields)

    if not task_line then
      vim.notify("obsidian-tasks: description is required", vim.log.levels.WARN)
      return
    end

    local today     = os.date("*t")
    local date_str  = os.date("%Y-%m-%d", os.time(today))
    local file_path = M.daily_file_path(today)

    M.ensure_daily_file(file_path, date_str)
    M.append_task(file_path, task_line, cap.section)
    require("obsidian-tasks.index").update_file(file_path)

    local short_name = vim.fn.fnamemodify(file_path, ":t")
    vim.notify("obsidian-tasks: captured to " .. short_name, vim.log.levels.INFO)

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

  vim.api.nvim_create_autocmd("BufWriteCmd", {
    buffer   = bufnr,
    once     = true,
    callback = save_and_close,
  })

  -- Start in insert mode at the end of the description line
  vim.schedule(function()
    if vim.api.nvim_win_is_valid(winnr) then
      vim.api.nvim_win_set_cursor(winnr, { 1, #form_lines[1] })
      vim.cmd("startinsert!")
    end
  end)
end

return M
