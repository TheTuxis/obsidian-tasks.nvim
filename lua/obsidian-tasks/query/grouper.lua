local task_mod = require("obsidian-tasks.task")

local M = {}

local GROUPERS = {
  priority = function(t)
    return task_mod.PRIORITY_NAMES[t.priority] or "None"
  end,
  status = function(t)
    local names = {
      [task_mod.STATUS.TODO]        = "Todo",
      [task_mod.STATUS.DONE]        = "Done",
      [task_mod.STATUS.CANCELLED]   = "Cancelled",
      [task_mod.STATUS.IN_PROGRESS] = "In Progress",
      [task_mod.STATUS.FORWARDED]   = "Forwarded",
    }
    return names[t.status] or "Unknown"
  end,
  due = function(t)
    if not t.due_date then return "No due date" end
    local diff = (task_mod.date_to_days(t.due_date) - task_mod.today_days()) / 86400
    if diff < 0 then return "Overdue" end
    if diff == 0 then return "Due today" end
    if diff == 1 then return "Due tomorrow" end
    if diff <= 7 then return "Due this week" end
    return "Due " .. t.due_date.raw
  end,
  scheduled = function(t)
    if not t.scheduled_date then return "No scheduled date" end
    return "Scheduled " .. t.scheduled_date.raw
  end,
  path = function(t)
    return vim.fn.fnamemodify(t.file_path, ":~:.")
  end,
  filename = function(t)
    return vim.fn.fnamemodify(t.file_path, ":t:r")
  end,
  heading = function(t)
    return t.heading or "(no heading)"
  end,
  recurrence = function(t)
    return t.recurrence and "Recurring" or "Not Recurring"
  end,
  tag = function(t)
    if #t.tags == 0 then return "(no tags)" end
    -- Tasks can appear in multiple tag groups; return all (handled by caller)
    return t.tags[1] -- simplified: group by first tag
  end,
}

-- Parse "group by <field>" and return grouper spec or nil
function M.parse(line)
  local lower = vim.trim(line:lower())
  local field = lower:match("^group%s+by%s+(%S+)$")
  if not field then return nil end

  local fn = GROUPERS[field]
  if not fn then return nil end

  return { field = field, fn = fn }
end

-- Apply groupers and return ordered list of { key, tasks[] }
function M.apply(tasks, specs)
  if #specs == 0 then
    return { { key = nil, tasks = tasks } }
  end

  -- Only support single-level grouping for MVP
  local spec = specs[1]
  local groups = {}
  local order  = {}

  for _, t in ipairs(tasks) do
    local key = spec.fn(t)
    if not groups[key] then
      groups[key] = {}
      table.insert(order, key)
    end
    table.insert(groups[key], t)
  end

  local result = {}
  for _, key in ipairs(order) do
    table.insert(result, { key = key, tasks = groups[key] })
  end
  return result
end

return M
