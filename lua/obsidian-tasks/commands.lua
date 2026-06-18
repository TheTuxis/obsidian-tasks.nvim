local task_mod = require("obsidian-tasks.task")
local index    = require("obsidian-tasks.index")

local M = {}

local _config = {}

function M.setup(cfg)
  _config = cfg
end

-- Toggle the task status on a line in the current buffer
-- todo → done, done → todo, cancelled stays cancelled
local function toggle_status(status)
  if status == task_mod.STATUS.TODO or status == task_mod.STATUS.IN_PROGRESS then
    return task_mod.STATUS.DONE
  elseif status == task_mod.STATUS.DONE then
    return task_mod.STATUS.TODO
  end
  return status -- leave cancelled/forwarded unchanged
end

-- Rewrite a task line with a new status character
local function rewrite_task_line(line, new_status)
  local char = task_mod.status_char(new_status)
  -- Replace the [.] checkbox portion
  local result = line:gsub("%[.-%]", "[" .. char .. "]", 1)

  -- If marking as done and no done date yet, append ✅ date
  if new_status == task_mod.STATUS.DONE and not line:find("\xE2\x9C\x85") then
    local today = os.date("%Y-%m-%d")
    result = result .. " \xE2\x9C\x85 " .. today
  end

  -- If un-marking (done→todo), strip done date
  if new_status == task_mod.STATUS.TODO then
    result = result:gsub("%s*\xE2\x9C\x85%s*%d%d%d%d%-%d%d%-%d%d", "")
  end

  return result
end

-- Toggle the task under the cursor in the current buffer
function M.toggle_task_at_cursor()
  local bufnr  = vim.api.nvim_get_current_buf()
  local row    = vim.api.nvim_win_get_cursor(0)[1]
  local lines  = vim.api.nvim_buf_get_lines(bufnr, row - 1, row, false)
  local line   = lines[1]
  if not line then return end

  local parser = require("obsidian-tasks.parser")
  local t = parser.parse_line(line, vim.api.nvim_buf_get_name(bufnr), row, nil)
  if not t then
    vim.notify("No task found on this line", vim.log.levels.WARN)
    return
  end

  local new_status = toggle_status(t.status)
  local new_line   = rewrite_task_line(line, new_status)

  vim.api.nvim_buf_set_lines(bufnr, row - 1, row, false, { new_line })
end

-- Toggle a task in its source file (used from picker/renderer)
function M.toggle_task_in_file(t)
  local lines = {}
  local f = io.open(t.file_path, "r")
  if not f then
    vim.notify("Cannot open: " .. t.file_path, vim.log.levels.ERROR)
    return
  end
  for line in f:lines() do table.insert(lines, line) end
  f:close()

  local target_line = lines[t.line_number]
  if not target_line then return end

  local new_status = toggle_status(t.status)
  local new_line   = rewrite_task_line(target_line, new_status)
  lines[t.line_number] = new_line

  local out = io.open(t.file_path, "w")
  if not out then
    vim.notify("Cannot write: " .. t.file_path, vim.log.levels.ERROR)
    return
  end
  for _, l in ipairs(lines) do out:write(l .. "\n") end
  out:close()

  -- Reload the buffer if it's open
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_get_name(bufnr) == t.file_path then
      vim.api.nvim_buf_call(bufnr, function()
        vim.cmd("silent! checktime")
      end)
      break
    end
  end

  -- Update index
  index.update_file(t.file_path)
  vim.notify("Task toggled", vim.log.levels.INFO)
end

-- Insert a new task at the cursor position
function M.create_task()
  local row = vim.api.nvim_win_get_cursor(0)[1]
  local today = os.date("%Y-%m-%d")

  -- Simple prompt for description
  vim.ui.input({ prompt = "Task description: " }, function(desc)
    if not desc or desc == "" then return end

    vim.ui.input({ prompt = "Due date (YYYY-MM-DD, leave blank to skip): " }, function(due)
      local task_line = "- [ ] " .. desc
      if due and due:match("^%d%d%d%d%-%d%d%-%d%d$") then
        task_line = task_line .. " \xF0\x9F\x93\x85 " .. due
      end
      task_line = task_line .. " \xE2\x9E\x95 " .. today

      vim.api.nvim_buf_set_lines(0, row, row, false, { task_line })
      vim.api.nvim_win_set_cursor(0, { row + 1, #task_line })
    end)
  end)
end

-- Register all commands and keymaps
function M.register(cfg)
  _config = cfg

  vim.api.nvim_create_user_command("TasksRebuildIndex", function()
    index.rebuild()
    local n = #index.all_tasks()
    vim.notify("Tasks: index rebuilt (" .. n .. " tasks)", vim.log.levels.INFO)
  end, { desc = "Rebuild the obsidian-tasks vault index" })

  vim.api.nvim_create_user_command("TasksToggle", function()
    M.toggle_task_at_cursor()
  end, { desc = "Toggle task under cursor" })

  vim.api.nvim_create_user_command("TasksCreate", function()
    M.create_task()
  end, { desc = "Create a new task at cursor" })

  vim.api.nvim_create_user_command("TasksQuery", function()
    require("obsidian-tasks.renderer").open_query_at_cursor()
  end, { desc = "Open query block result in floating window" })

  vim.api.nvim_create_user_command("TasksPicker", function()
    require("obsidian-tasks.ui.picker").open()
  end, { desc = "Open Telescope task picker" })

  vim.api.nvim_create_user_command("TasksEdit", function()
    require("obsidian-tasks.ui.editor").open_at_cursor()
  end, { desc = "Edit task metadata in a floating form" })

  -- Keymaps (only in markdown buffers)
  local km = cfg.keymaps or {}

  local function map(lhs, rhs, desc)
    if lhs and lhs ~= "" then
      vim.keymap.set("n", lhs, rhs, { silent = true, desc = desc })
    end
  end

  map(km.toggle,     M.toggle_task_at_cursor,                     "Tasks: toggle task")
  map(km.create,     M.create_task,                               "Tasks: create task")
  map(km.open_query, function()
    require("obsidian-tasks.renderer").open_query_at_cursor()
  end, "Tasks: open query")
  map(km.picker, function()
    require("obsidian-tasks.ui.picker").open()
  end, "Tasks: open picker")
  map(km.edit, function()
    require("obsidian-tasks.ui.editor").open_at_cursor()
  end, "Tasks: edit task")
end

return M
