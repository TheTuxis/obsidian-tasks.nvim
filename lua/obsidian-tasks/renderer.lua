local task_mod = require("obsidian-tasks.task")
local query    = require("obsidian-tasks.query")
local index    = require("obsidian-tasks.index")

local M = {}

local _config = {}

function M.setup(cfg)
  _config = cfg
end

-- Format a single task as a display line
local function format_task(t, hide)
  local parts = {}

  -- Status icon
  table.insert(parts, task_mod.display_status(t.status))

  -- Description
  table.insert(parts, t.description)

  -- Priority (if not hidden and not NONE)
  if not hide["priority"] and t.priority ~= task_mod.PRIORITY.NONE then
    local icons = { [5]="🔺", [4]="⏫", [3]="🔼", [1]="🔽", [0]="⏬" }
    local icon = icons[t.priority]
    if icon then table.insert(parts, icon) end
  end

  -- Due date
  if not hide["due"] and t.due_date then
    table.insert(parts, "📅 " .. t.due_date.raw)
  end

  -- Scheduled date
  if not hide["scheduled"] and t.scheduled_date then
    table.insert(parts, "⏳ " .. t.scheduled_date.raw)
  end

  -- Start date
  if not hide["start"] and t.start_date then
    table.insert(parts, "🛫 " .. t.start_date.raw)
  end

  -- Recurrence
  if not hide["recurring"] and t.recurrence then
    table.insert(parts, "🔁 " .. t.recurrence)
  end

  -- Tags
  if not hide["tags"] and #t.tags > 0 then
    table.insert(parts, table.concat(t.tags, " "))
  end

  -- Backlink
  if not hide["backlink"] then
    local rel = vim.fn.fnamemodify(t.file_path, ":t:r")
    table.insert(parts, "  [[" .. rel .. "]]")
  end

  return table.concat(parts, " ")
end

-- Build the lines to show in the floating window
function M.build_lines(groups, errors, hide)
  local lines = {}

  if #errors > 0 then
    for _, err in ipairs(errors) do
      table.insert(lines, "⚠ " .. err)
    end
    table.insert(lines, "")
  end

  local total = 0
  for _, grp in ipairs(groups) do
    total = total + #grp.tasks
  end

  if total == 0 then
    table.insert(lines, "(no tasks match)")
    return lines
  end

  for _, grp in ipairs(groups) do
    if grp.key ~= nil then
      table.insert(lines, "## " .. grp.key)
    end

    for _, t in ipairs(grp.tasks) do
      table.insert(lines, format_task(t, hide))
    end

    if grp.key ~= nil then
      table.insert(lines, "")
    end
  end

  return lines, total
end

-- Open a floating window showing query results
function M.open_floating(query_text)
  local all_tasks = index.all_tasks()
  local groups, errors = query.run(query_text, all_tasks)

  -- Parse hide spec from query for rendering
  local spec = require("obsidian-tasks.query").parse(query_text)
  local hide = spec.hide or {}

  local lines, total = M.build_lines(groups, errors, hide)
  total = total or 0

  local fw = _config.floating_window or {}
  local border = fw.border or "rounded"
  local max_h  = fw.max_height or 30
  local max_w  = fw.max_width or 80

  -- Calculate window dimensions
  local width = 0
  for _, l in ipairs(lines) do
    -- count display width (rough: #bytes for ASCII, approximate for emoji)
    local w = vim.fn.strdisplaywidth(l)
    if w > width then width = w end
  end
  width  = math.min(math.max(width + 2, 40), max_w)
  local height = math.min(#lines, max_h)

  local ui = vim.api.nvim_list_uis()[1]
  local col = math.floor((ui.width  - width)  / 2)
  local row = math.floor((ui.height - height) / 2)

  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  vim.bo[bufnr].modifiable = false
  vim.bo[bufnr].buftype    = "nofile"
  vim.bo[bufnr].filetype   = "markdown"

  local title = " " .. total .. " task" .. (total == 1 and "" or "s") .. " "

  local winnr = vim.api.nvim_open_win(bufnr, true, {
    relative  = "editor",
    row       = row,
    col       = col,
    width     = width,
    height    = height,
    border    = border,
    title     = title,
    title_pos = "center",
    style     = "minimal",
  })

  vim.wo[winnr].wrap       = false
  vim.wo[winnr].cursorline = true

  -- Keymaps to close
  local close = function()
    if vim.api.nvim_win_is_valid(winnr) then vim.api.nvim_win_close(winnr, true) end
  end
  vim.keymap.set("n", "q",     close, { buffer = bufnr, nowait = true, silent = true })
  vim.keymap.set("n", "<Esc>", close, { buffer = bufnr, nowait = true, silent = true })

  -- Jump to source with <CR>
  vim.keymap.set("n", "<CR>", function()
    local cursor_line = vim.api.nvim_win_get_cursor(winnr)[1]
    local task_line   = lines[cursor_line]
    if not task_line then return end

    -- Extract [[Filename]] backlink
    local fname = task_line:match("%[%[(.-)%]%]")
    if not fname then return end

    -- Find the task in all tasks
    for _, grp in ipairs(groups) do
      for _, t in ipairs(grp.tasks) do
        local rel = vim.fn.fnamemodify(t.file_path, ":t:r")
        if rel == fname then
          close()
          vim.cmd("edit " .. vim.fn.fnameescape(t.file_path))
          vim.api.nvim_win_set_cursor(0, { t.line_number, 0 })
          return
        end
      end
    end
  end, { buffer = bufnr, nowait = true, silent = true })

  return winnr
end

-- Find the query block under cursor and open floating window
function M.open_query_at_cursor(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local parser = require("obsidian-tasks.parser")
  local cursor = vim.api.nvim_win_get_cursor(0)
  local row    = cursor[1]

  local _, _, query_text = parser.find_query_block_at_cursor(bufnr, row)
  if not query_text then
    vim.notify("No tasks query block under cursor", vim.log.levels.WARN)
    return
  end

  M.open_floating(query_text)
end

return M
