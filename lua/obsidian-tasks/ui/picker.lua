local task_mod = require("obsidian-tasks.task")
local index    = require("obsidian-tasks.index")

local M = {}

local function has_telescope()
  return pcall(require, "telescope")
end

local function format_entry(t)
  local status = task_mod.display_status(t.status)
  local due    = t.due_date and (" 📅 " .. t.due_date.raw) or ""
  local pri    = ""
  if t.priority ~= task_mod.PRIORITY.NONE then
    local icons = { [5]="🔺", [4]="⏫", [3]="🔼", [1]="🔽", [0]="⏬" }
    pri = " " .. (icons[t.priority] or "")
  end
  local rel = vim.fn.fnamemodify(t.file_path, ":t:r")
  return string.format("%s %s%s%s  [[%s:%d]]", status, t.description, pri, due, rel, t.line_number)
end

function M.open(opts)
  if not has_telescope() then
    vim.notify("telescope.nvim is required for the task picker", vim.log.levels.ERROR)
    return
  end

  opts = opts or {}
  local show_all = opts.show_all or false

  local telescope   = require("telescope")
  local pickers     = require("telescope.pickers")
  local finders     = require("telescope.finders")
  local conf        = require("telescope.config").values
  local actions     = require("telescope.actions")
  local action_state = require("telescope.actions.state")

  local tasks = index.all_tasks()
  if not show_all then
    tasks = vim.tbl_filter(function(t)
      return t.status ~= task_mod.STATUS.DONE and t.status ~= task_mod.STATUS.CANCELLED
    end, tasks)
  end

  local title = show_all and "Tasks (all)  <C-a> active only" or "Tasks (active)  <C-a> show all"

  pickers.new({}, {
    prompt_title = title,
    finder = finders.new_table({
      results = tasks,
      entry_maker = function(t)
        return {
          value   = t,
          display = format_entry(t),
          ordinal = t.description .. " " .. (t.file_path or ""),
        }
      end,
    }),
    sorter = conf.generic_sorter({}),
    attach_mappings = function(prompt_bufnr, map)
      -- <CR>: jump to task source
      actions.select_default:replace(function()
        actions.close(prompt_bufnr)
        local entry = action_state.get_selected_entry()
        if not entry then return end
        local t = entry.value
        vim.cmd("edit " .. vim.fn.fnameescape(t.file_path))
        vim.api.nvim_win_set_cursor(0, { t.line_number, 0 })
      end)

      -- <C-t>: toggle task status
      map("i", "<C-t>", function()
        local entry = action_state.get_selected_entry()
        if not entry then return end
        local t = entry.value
        actions.close(prompt_bufnr)
        require("obsidian-tasks.commands").toggle_task_in_file(t)
      end)

      -- <C-a>: toggle between active-only and all tasks
      map("i", "<C-a>", function()
        actions.close(prompt_bufnr)
        M.open({ show_all = not show_all })
      end)
      map("n", "<C-a>", function()
        actions.close(prompt_bufnr)
        M.open({ show_all = not show_all })
      end)

      return true
    end,
  }):find()
end

return M
