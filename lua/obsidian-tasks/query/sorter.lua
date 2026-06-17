local task_mod = require("obsidian-tasks.task")

local M = {}

local function days(dt) return task_mod.date_to_days(dt) end

-- Each comparator returns -1, 0, or 1 (a < b → -1)
local COMPARATORS = {
  priority = function(a, b)
    -- Higher number = higher priority; sort descending (highest first)
    if a.priority ~= b.priority then
      return a.priority > b.priority and -1 or 1
    end
    return 0
  end,
  due = function(a, b)
    local da, db = days(a.due_date), days(b.due_date)
    if da == db then return 0 end
    if da == nil then return 1 end  -- no due date sorts last
    if db == nil then return -1 end
    return da < db and -1 or 1
  end,
  scheduled = function(a, b)
    local da, db = days(a.scheduled_date), days(b.scheduled_date)
    if da == db then return 0 end
    if da == nil then return 1 end
    if db == nil then return -1 end
    return da < db and -1 or 1
  end,
  start = function(a, b)
    local da, db = days(a.start_date), days(b.start_date)
    if da == db then return 0 end
    if da == nil then return 1 end
    if db == nil then return -1 end
    return da < db and -1 or 1
  end,
  created = function(a, b)
    local da, db = days(a.created_date), days(b.created_date)
    if da == db then return 0 end
    if da == nil then return 1 end
    if db == nil then return -1 end
    return da < db and -1 or 1
  end,
  description = function(a, b)
    local la, lb = a.description:lower(), b.description:lower()
    if la == lb then return 0 end
    return la < lb and -1 or 1
  end,
  path = function(a, b)
    if a.file_path == b.file_path then return 0 end
    return a.file_path < b.file_path and -1 or 1
  end,
  filename = function(a, b)
    local fa = vim.fn.fnamemodify(a.file_path, ":t")
    local fb = vim.fn.fnamemodify(b.file_path, ":t")
    if fa == fb then return 0 end
    return fa < fb and -1 or 1
  end,
  status = function(a, b)
    -- done/cancelled after todo/in_progress
    local order = {
      [task_mod.STATUS.IN_PROGRESS] = 0,
      [task_mod.STATUS.TODO]        = 1,
      [task_mod.STATUS.FORWARDED]   = 2,
      [task_mod.STATUS.DONE]        = 3,
      [task_mod.STATUS.CANCELLED]   = 4,
    }
    local oa = order[a.status] or 5
    local ob = order[b.status] or 5
    if oa == ob then return 0 end
    return oa < ob and -1 or 1
  end,
  urgency = function(a, b)
    -- Simple urgency: priority weight + overdue penalty
    local function score(t)
      local s = t.priority * 10
      if t.due_date then
        local diff = days(t.due_date) - task_mod.today_days()
        if diff < 0 then s = s + 20 elseif diff == 0 then s = s + 10 end
      end
      return s
    end
    local sa, sb = score(a), score(b)
    if sa == sb then return 0 end
    return sa > sb and -1 or 1 -- higher urgency first
  end,
  recurrence = function(a, b)
    local ra = a.recurrence ~= nil and 0 or 1
    local rb = b.recurrence ~= nil and 0 or 1
    if ra == rb then return 0 end
    return ra < rb and -1 or 1
  end,
  done = function(a, b)
    local da, db = days(a.done_date), days(b.done_date)
    if da == db then return 0 end
    if da == nil then return 1 end
    if db == nil then return -1 end
    return da < db and -1 or 1
  end,
  cancelled = function(a, b)
    local da, db = days(a.cancelled_date), days(b.cancelled_date)
    if da == db then return 0 end
    if da == nil then return 1 end
    if db == nil then return -1 end
    return da < db and -1 or 1
  end,
  id = function(a, b)
    local ia, ib = a.id or "", b.id or ""
    if ia == ib then return 0 end
    return ia < ib and -1 or 1
  end,
  heading = function(a, b)
    local ha, hb = a.heading or "", b.heading or ""
    if ha == hb then return 0 end
    return ha < hb and -1 or 1
  end,
}

-- Parse "sort by <field> [reverse]" and return a comparator spec or nil
function M.parse(line)
  local lower = vim.trim(line:lower())
  local field, rev_str = lower:match("^sort%s+by%s+(%S+)%s*(.*)$")
  if not field then return nil end

  local cmp = COMPARATORS[field]
  if not cmp then return nil end

  local reverse = (rev_str == "reverse")
  return { cmp = cmp, reverse = reverse }
end

-- Apply a list of sort specs to tasks (stable multi-key sort)
function M.apply(tasks, specs)
  if #specs == 0 then return tasks end

  -- Default sort appended if not already present
  local defaults = { "status", "urgency", "due", "priority", "path" }
  local has = {}
  for _, s in ipairs(specs) do has[s.field] = true end

  local final_specs = {}
  for _, s in ipairs(specs) do table.insert(final_specs, s) end
  for _, f in ipairs(defaults) do
    if not has[f] and COMPARATORS[f] then
      table.insert(final_specs, { cmp = COMPARATORS[f], reverse = false, field = f })
    end
  end

  local sorted = vim.deepcopy(tasks)
  table.sort(sorted, function(a, b)
    for _, spec in ipairs(final_specs) do
      local r = spec.cmp(a, b)
      if spec.reverse then r = -r end
      if r < 0 then return true end
      if r > 0 then return false end
    end
    return false
  end)

  return sorted
end

return M
