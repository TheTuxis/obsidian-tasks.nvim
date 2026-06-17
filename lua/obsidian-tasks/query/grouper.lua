local task_mod = require("obsidian-tasks.task")

local M = {}

local function date_label(prefix, dt)
  if not dt then return "No " .. prefix .. " date" end
  return prefix .. " " .. dt.raw
end

local function urgency_score(t)
  local s = t.priority * 10
  if t.due_date then
    local diff = (task_mod.date_to_days(t.due_date) - task_mod.today_days()) / 86400
    if diff < 0 then s = s + 20 elseif diff == 0 then s = s + 10 end
  end
  return s
end

-- Grouper functions return a string or a list of strings (for fan-out, e.g. tags).
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
    return date_label("Scheduled", t.scheduled_date)
  end,
  start = function(t)
    return date_label("Started", t.start_date)
  end,
  created = function(t)
    return date_label("Created", t.created_date)
  end,
  done = function(t)
    return date_label("Done", t.done_date)
  end,
  cancelled = function(t)
    return date_label("Cancelled", t.cancelled_date)
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
  id = function(t)
    return t.id and ("ID: " .. t.id) or "(no id)"
  end,
  urgency = function(t)
    return string.format("Urgency %.2f", urgency_score(t))
  end,
  backlink = function(t)
    local fname = vim.fn.fnamemodify(t.file_path, ":t:r")
    return t.heading and (fname .. " > " .. t.heading) or fname
  end,
  -- Returns all tags so each task appears under every matching tag group.
  tag = function(t)
    if #t.tags == 0 then return "(no tags)" end
    return t.tags
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

-- Apply groupers recursively and return ordered list of { key, tasks[] }.
-- When multiple specs are given, nested keys are joined with " > ".
function M.apply(tasks, specs)
  if #specs == 0 then
    return { { key = nil, tasks = tasks } }
  end

  local function apply_level(task_list, spec_index, key_prefix)
    local spec = specs[spec_index]
    local groups = {}
    local order  = {}

    for _, t in ipairs(task_list) do
      local keys = spec.fn(t)
      -- Fan-out: normalize to a list so multi-tag tasks appear in each group.
      if type(keys) ~= "table" then keys = { keys } end
      for _, key in ipairs(keys) do
        if not groups[key] then
          groups[key] = {}
          table.insert(order, key)
        end
        table.insert(groups[key], t)
      end
    end

    local result = {}
    for _, key in ipairs(order) do
      local full_key = key_prefix and (key_prefix .. " > " .. key) or key
      if spec_index < #specs then
        local sub = apply_level(groups[key], spec_index + 1, full_key)
        for _, sg in ipairs(sub) do
          table.insert(result, sg)
        end
      else
        table.insert(result, { key = full_key, tasks = groups[key] })
      end
    end
    return result
  end

  return apply_level(tasks, 1, nil)
end

return M
