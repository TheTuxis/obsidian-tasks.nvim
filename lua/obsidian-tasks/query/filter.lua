local task_mod = require("obsidian-tasks.task")

local M = {}

-- Helper: date comparison (nil dates sort last / treated as "no date")
local function days(dt)
  return task_mod.date_to_days(dt)
end

local function today()
  return task_mod.today_days()
end

local function parse_relative_date(expr)
  -- Returns an os.time() value or nil
  local t = today()
  local lower = expr:lower()

  if lower == "today"     then return t end
  if lower == "yesterday" then return t - 86400 end
  if lower == "tomorrow"  then return t + 86400 end

  -- "in X days" / "X days ago"
  local n = lower:match("^in%s+(%d+)%s+days?$")
  if n then return t + tonumber(n) * 86400 end

  n = lower:match("^(%d+)%s+days?%s+ago$")
  if n then return t - tonumber(n) * 86400 end

  n = lower:match("^in%s+(%d+)%s+weeks?$")
  if n then return t + tonumber(n) * 7 * 86400 end

  n = lower:match("^(%d+)%s+weeks?%s+ago$")
  if n then return t - tonumber(n) * 7 * 86400 end

  -- "next monday" etc.
  local weekdays = { sunday=0, monday=1, tuesday=2, wednesday=3, thursday=4, friday=5, saturday=6 }
  local day_name = lower:match("^next%s+(%a+)$")
  if day_name and weekdays[day_name] then
    local target_wday = weekdays[day_name]
    local cur_wday    = tonumber(os.date("%w", t))
    local diff = (target_wday - cur_wday + 7) % 7
    if diff == 0 then diff = 7 end
    return t + diff * 86400
  end

  -- "last monday" etc.
  day_name = lower:match("^last%s+(%a+)$")
  if day_name and weekdays[day_name] then
    local target_wday = weekdays[day_name]
    local cur_wday    = tonumber(os.date("%w", t))
    local diff = (cur_wday - target_wday + 7) % 7
    if diff == 0 then diff = 7 end
    return t - diff * 86400
  end

  -- YYYY-MM-DD
  local y, mo, d = expr:match("^(%d%d%d%d)-(%d%d)-(%d%d)$")
  if y then
    return os.time({ year=tonumber(y), month=tonumber(mo), day=tonumber(d), hour=0, min=0, sec=0 })
  end

  return nil
end

-- Build a filter function for a date field given an expression like:
--   "before tomorrow", "after 2024-01-01", "on today", "today", "on or before tomorrow", ...
local function make_date_filter(get_date, expr)
  local lower = vim.trim(expr:lower())

  -- Normalize "on or before X" / "on or after X"
  local mode, rest

  if lower:match("^on or before%s+") then
    mode = "on_or_before"
    rest = lower:match("^on or before%s+(.+)$")
  elseif lower:match("^on or after%s+") then
    mode = "on_or_after"
    rest = lower:match("^on or after%s+(.+)$")
  elseif lower:match("^before%s+") then
    mode = "before"
    rest = lower:match("^before%s+(.+)$")
  elseif lower:match("^after%s+") then
    mode = "after"
    rest = lower:match("^after%s+(.+)$")
  elseif lower:match("^on%s+") then
    mode = "on"
    rest = lower:match("^on%s+(.+)$")
  else
    mode = "on"
    rest = lower
  end

  local target = parse_relative_date(rest)
  if not target then return nil end

  return function(t)
    local d = days(get_date(t))
    if not d then return false end
    if mode == "before"       then return d < target end
    if mode == "after"        then return d > target end
    if mode == "on_or_before" then return d <= target end
    if mode == "on_or_after"  then return d >= target end
    return d == target -- "on"
  end
end

-- Priority name → level
local PRIORITY_LEVELS = {
  highest = task_mod.PRIORITY.HIGHEST,
  high    = task_mod.PRIORITY.HIGH,
  medium  = task_mod.PRIORITY.MEDIUM,
  none    = task_mod.PRIORITY.NONE,
  low     = task_mod.PRIORITY.LOW,
  lowest  = task_mod.PRIORITY.LOWEST,
}

-- Parse a filter instruction line and return a predicate function(task) → bool, or nil on no match
function M.parse(line)
  local lower = vim.trim(line:lower())

  -- done / not done
  if lower == "done" then
    return function(t) return task_mod.is_complete(t) end
  end
  if lower == "not done" then
    return function(t) return not task_mod.is_complete(t) end
  end

  -- status.type is X
  local status_type = lower:match("^status%.type%s+is%s+(%S+)$")
  if status_type then
    local map = {
      todo        = task_mod.STATUS.TODO,
      done        = task_mod.STATUS.DONE,
      in_progress = task_mod.STATUS.IN_PROGRESS,
      cancelled   = task_mod.STATUS.CANCELLED,
      forwarded   = task_mod.STATUS.FORWARDED,
    }
    local s = map[status_type]
    if s then return function(t) return t.status == s end end
  end

  -- is recurring / is not recurring
  if lower == "is recurring" then
    return function(t) return t.recurrence ~= nil end
  end
  if lower == "is not recurring" then
    return function(t) return t.recurrence == nil end
  end

  -- has tags / no tags
  if lower == "has tags" then
    return function(t) return #t.tags > 0 end
  end
  if lower == "no tags" then
    return function(t) return #t.tags == 0 end
  end

  -- tags include #tag
  local tag_inc = line:match("^[Tt]ags%s+include%s+(%S+)$")
  if tag_inc then
    local tag_lower = tag_inc:lower()
    return function(t)
      for _, tag in ipairs(t.tags) do
        if tag:lower():find(tag_lower, 1, true) then return true end
      end
      return false
    end
  end

  local tag_exc = line:match("^[Tt]ags%s+does%s+not%s+include%s+(%S+)$")
  if tag_exc then
    local tag_lower = tag_exc:lower()
    return function(t)
      for _, tag in ipairs(t.tags) do
        if tag:lower():find(tag_lower, 1, true) then return false end
      end
      return true
    end
  end

  -- description includes / does not include
  local desc_inc = line:match("^[Dd]escription%s+includes%s+(.+)$")
  if desc_inc then
    local needle = desc_inc:lower()
    return function(t) return t.description:lower():find(needle, 1, true) ~= nil end
  end

  local desc_exc = line:match("^[Dd]escription%s+does%s+not%s+include%s+(.+)$")
  if desc_exc then
    local needle = desc_exc:lower()
    return function(t) return t.description:lower():find(needle, 1, true) == nil end
  end

  local desc_regex = line:match("^[Dd]escription%s+regex%s+matches%s+/(.+)/$")
  if desc_regex then
    return function(t) return t.description:match(desc_regex) ~= nil end
  end

  -- path includes / does not include / regex
  local path_inc = line:match("^[Pp]ath%s+includes%s+(.+)$")
  if path_inc then
    local needle = path_inc:lower()
    return function(t) return t.file_path:lower():find(needle, 1, true) ~= nil end
  end

  local path_exc = line:match("^[Pp]ath%s+does%s+not%s+include%s+(.+)$")
  if path_exc then
    local needle = path_exc:lower()
    return function(t) return t.file_path:lower():find(needle, 1, true) == nil end
  end

  -- filename includes
  local fname_inc = line:match("^[Ff]ilename%s+includes%s+(.+)$")
  if fname_inc then
    local needle = fname_inc:lower()
    return function(t)
      local fname = vim.fn.fnamemodify(t.file_path, ":t"):lower()
      return fname:find(needle, 1, true) ~= nil
    end
  end

  -- heading includes
  local heading_inc = line:match("^[Hh]eading%s+includes%s+(.+)$")
  if heading_inc then
    local needle = heading_inc:lower()
    return function(t)
      if not t.heading then return false end
      return t.heading:lower():find(needle, 1, true) ~= nil
    end
  end

  -- priority is X
  local priority_is = lower:match("^priority%s+is%s+(%S+)$")
  if priority_is then
    local level = PRIORITY_LEVELS[priority_is]
    if level ~= nil then
      return function(t) return t.priority == level end
    end
  end

  -- priority above X
  local priority_above = lower:match("^priority%s+above%s+(%S+)$")
  if priority_above then
    local level = PRIORITY_LEVELS[priority_above]
    if level ~= nil then
      return function(t) return t.priority > level end
    end
  end

  -- priority below X
  local priority_below = lower:match("^priority%s+below%s+(%S+)$")
  if priority_below then
    local level = PRIORITY_LEVELS[priority_below]
    if level ~= nil then
      return function(t) return t.priority < level end
    end
  end

  -- priority not X
  local priority_not = lower:match("^priority%s+not%s+(%S+)$")
  if priority_not then
    local level = PRIORITY_LEVELS[priority_not]
    if level ~= nil then
      return function(t) return t.priority ~= level end
    end
  end

  -- Date filters: due / scheduled / start / done / cancelled / created
  local date_field_map = {
    due       = function(t) return t.due_date end,
    scheduled = function(t) return t.scheduled_date end,
    start     = function(t) return t.start_date end,
    done      = function(t) return t.done_date end,
    cancelled = function(t) return t.cancelled_date end,
    created   = function(t) return t.created_date end,
  }

  for field_name, getter in pairs(date_field_map) do
    -- "has due date" / "no due date"
    if lower == "has " .. field_name .. " date" then
      return function(t) return getter(t) ~= nil end
    end
    if lower == "no " .. field_name .. " date" then
      return function(t) return getter(t) == nil end
    end

    -- "due before tomorrow" etc.
    local date_expr = lower:match("^" .. field_name .. "%s+(.+)$")
    if date_expr then
      local fn = make_date_filter(getter, date_expr)
      if fn then return fn end
    end
  end

  return nil -- unrecognized filter line
end

return M
