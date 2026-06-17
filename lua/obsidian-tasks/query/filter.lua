local task_mod = require("obsidian-tasks.task")

local M = {}

-- Helper: date comparison (nil dates sort last / treated as "no date")
local function days(dt)
  return task_mod.date_to_days(dt)
end

local function today()
  return task_mod.today_days()
end

local function week_start(t)
  local wday = tonumber(os.date("%w", t))  -- 0=Sun...6=Sat
  return t - wday * 86400
end

local function month_start(t)
  local d = os.date("*t", t)
  return os.time({ year = d.year, month = d.month, day = 1, hour = 0, min = 0, sec = 0 })
end

local function quarter_start(t)
  local d = os.date("*t", t)
  local qm = math.floor((d.month - 1) / 3) * 3 + 1
  return os.time({ year = d.year, month = qm, day = 1, hour = 0, min = 0, sec = 0 })
end

local function year_start(t)
  local d = os.date("*t", t)
  return os.time({ year = d.year, month = 1, day = 1, hour = 0, min = 0, sec = 0 })
end

local function add_months(t, n)
  local d = os.date("*t", t)
  local total = d.month - 1 + n
  local y = d.year + math.floor(total / 12)
  local m = total % 12 + 1
  return os.time({ year = y, month = m, day = d.day, hour = 0, min = 0, sec = 0 })
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

  -- "this/next/last week" (Sunday–Saturday)
  if lower == "this week" then
    local ws = week_start(t)
    return { start = ws, stop = ws + 6 * 86400 }
  end
  if lower == "next week" then
    local ws = week_start(t) + 7 * 86400
    return { start = ws, stop = ws + 6 * 86400 }
  end
  if lower == "last week" then
    local ws = week_start(t) - 7 * 86400
    return { start = ws, stop = ws + 6 * 86400 }
  end

  -- "this/next/last month"
  if lower == "this month" then
    local ms = month_start(t)
    return { start = ms, stop = add_months(ms, 1) - 86400 }
  end
  if lower == "next month" then
    local ms = add_months(month_start(t), 1)
    return { start = ms, stop = add_months(ms, 1) - 86400 }
  end
  if lower == "last month" then
    local ms = add_months(month_start(t), -1)
    return { start = ms, stop = month_start(t) - 86400 }
  end

  -- "this/next/last quarter"
  if lower == "this quarter" then
    local qs = quarter_start(t)
    return { start = qs, stop = add_months(qs, 3) - 86400 }
  end
  if lower == "next quarter" then
    local qs = add_months(quarter_start(t), 3)
    return { start = qs, stop = add_months(qs, 3) - 86400 }
  end
  if lower == "last quarter" then
    local qs = add_months(quarter_start(t), -3)
    return { start = qs, stop = quarter_start(t) - 86400 }
  end

  -- "this/next/last year"
  if lower == "this year" then
    local ys = year_start(t)
    return { start = ys, stop = add_months(ys, 12) - 86400 }
  end
  if lower == "next year" then
    local ys = add_months(year_start(t), 12)
    return { start = ys, stop = add_months(ys, 12) - 86400 }
  end
  if lower == "last year" then
    local ys = add_months(year_start(t), -12)
    return { start = ys, stop = year_start(t) - 86400 }
  end

  -- Two-date range: YYYY-MM-DD YYYY-MM-DD
  local y1, m1, d1, y2, m2, d2 =
    expr:match("^(%d%d%d%d)-(%d%d)-(%d%d)%s+(%d%d%d%d)-(%d%d)-(%d%d)$")
  if y1 then
    return {
      start = os.time({ year=tonumber(y1), month=tonumber(m1), day=tonumber(d1), hour=0, min=0, sec=0 }),
      stop  = os.time({ year=tonumber(y2), month=tonumber(m2), day=tonumber(d2), hour=0, min=0, sec=0 }),
    }
  end

  -- YYYY-MM-DD
  local y, mo, d = expr:match("^(%d%d%d%d)-(%d%d)-(%d%d)$")
  if y then
    return os.time({ year=tonumber(y), month=tonumber(mo), day=tonumber(d), hour=0, min=0, sec=0 })
  end

  -- ISO week: YYYY-Www
  local iso_y, iso_w = expr:match("^(%d%d%d%d)-[Ww](%d+)$")
  if iso_y then
    local iy, iw = tonumber(iso_y), tonumber(iso_w)
    -- ISO week 1 contains Jan 4; its Monday is the week1 start
    local jan4 = os.time({ year=iy, month=1, day=4, hour=0, min=0, sec=0 })
    local jan4_wday = tonumber(os.date("%w", jan4))
    local iso_dow = jan4_wday == 0 and 7 or jan4_wday  -- 1=Mon...7=Sun
    local week1_mon = jan4 - (iso_dow - 1) * 86400
    local ws = week1_mon + (iw - 1) * 7 * 86400
    return { start = ws, stop = ws + 6 * 86400 }
  end

  -- ISO quarter: YYYY-Qn
  local iso_qy, iso_qn = expr:match("^(%d%d%d%d)-[Qq]([1-4])$")
  if iso_qy then
    local iy, iq = tonumber(iso_qy), tonumber(iso_qn)
    local qm = (iq - 1) * 3 + 1
    local qs = os.time({ year=iy, month=qm, day=1, hour=0, min=0, sec=0 })
    return { start = qs, stop = add_months(qs, 3) - 86400 }
  end

  -- ISO month: YYYY-MM
  local iso_my, iso_mm = expr:match("^(%d%d%d%d)-(%d%d)$")
  if iso_my then
    local iy, im = tonumber(iso_my), tonumber(iso_mm)
    local ms = os.time({ year=iy, month=im, day=1, hour=0, min=0, sec=0 })
    return { start = ms, stop = add_months(ms, 1) - 86400 }
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

  -- Range target (this week, next month, ISO week/quarter/month, two-date range, etc.)
  if type(target) == "table" then
    return function(t)
      local d = days(get_date(t))
      if not d then return false end
      if mode == "before"       then return d < target.start end
      if mode == "after"        then return d > target.stop end
      if mode == "on_or_before" then return d <= target.stop end
      if mode == "on_or_after"  then return d >= target.start end
      return d >= target.start and d <= target.stop
    end
  end

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

-- Urgency score (mirrors sorter formula)
local function urgency_score(t)
  local s = t.priority * 10
  if t.due_date then
    local diff = (days(t.due_date) - today()) / 86400
    if diff < 0 then s = s + 20 elseif diff == 0 then s = s + 10 end
  end
  return s
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

  -- urgency above / below / is
  local urgency_above = lower:match("^urgency%s+above%s+([%d%.]+)$")
  if urgency_above then
    local thr = tonumber(urgency_above)
    if thr then return function(t) return urgency_score(t) > thr end end
  end

  local urgency_below = lower:match("^urgency%s+below%s+([%d%.]+)$")
  if urgency_below then
    local thr = tonumber(urgency_below)
    if thr then return function(t) return urgency_score(t) < thr end end
  end

  local urgency_eq = lower:match("^urgency%s+is%s+([%d%.]+)$")
  if urgency_eq then
    local thr = tonumber(urgency_eq)
    if thr then return function(t) return urgency_score(t) == thr end end
  end

  -- status.name is X / includes X
  local status_name_is = lower:match("^status%.name%s+is%s+(.+)$")
  if status_name_is then
    local name_map = {
      todo        = task_mod.STATUS.TODO,
      done        = task_mod.STATUS.DONE,
      ["in progress"] = task_mod.STATUS.IN_PROGRESS,
      in_progress = task_mod.STATUS.IN_PROGRESS,
      cancelled   = task_mod.STATUS.CANCELLED,
      forwarded   = task_mod.STATUS.FORWARDED,
    }
    local s = name_map[status_name_is]
    if s then return function(t) return t.status == s end end
  end

  local status_name_inc = lower:match("^status%.name%s+includes%s+(.+)$")
  if status_name_inc then
    local needle = status_name_inc
    local STATUS_NAMES = {
      [task_mod.STATUS.TODO]        = "todo",
      [task_mod.STATUS.DONE]        = "done",
      [task_mod.STATUS.IN_PROGRESS] = "in progress",
      [task_mod.STATUS.CANCELLED]   = "cancelled",
      [task_mod.STATUS.FORWARDED]   = "forwarded",
    }
    return function(t)
      local name = STATUS_NAMES[t.status] or ""
      return name:find(needle, 1, true) ~= nil
    end
  end

  -- folder includes / does not include
  local folder_inc = line:match("^[Ff]older%s+includes%s+(.+)$")
  if folder_inc then
    local needle = folder_inc:lower()
    return function(t)
      local dir = vim.fn.fnamemodify(t.file_path, ":h"):lower()
      return dir:find(needle, 1, true) ~= nil
    end
  end

  local folder_exc = line:match("^[Ff]older%s+does%s+not%s+include%s+(.+)$")
  if folder_exc then
    local needle = folder_exc:lower()
    return function(t)
      local dir = vim.fn.fnamemodify(t.file_path, ":h"):lower()
      return dir:find(needle, 1, true) == nil
    end
  end

  -- root includes / does not include (first directory component of the relative path)
  local root_inc = line:match("^[Rr]oot%s+includes%s+(.+)$")
  if root_inc then
    local needle = root_inc:lower()
    return function(t)
      local rel = vim.fn.fnamemodify(t.file_path, ":.")
      local first = rel:match("^([^/]+)/") or ""
      return first:lower():find(needle, 1, true) ~= nil
    end
  end

  local root_exc = line:match("^[Rr]oot%s+does%s+not%s+include%s+(.+)$")
  if root_exc then
    local needle = root_exc:lower()
    return function(t)
      local rel = vim.fn.fnamemodify(t.file_path, ":.")
      local first = rel:match("^([^/]+)/") or ""
      return first:lower():find(needle, 1, true) == nil
    end
  end

  -- backlink includes / does not include (filename > heading)
  local backlink_inc = line:match("^[Bb]acklink%s+includes%s+(.+)$")
  if backlink_inc then
    local needle = backlink_inc:lower()
    return function(t)
      local fname = vim.fn.fnamemodify(t.file_path, ":t:r"):lower()
      local bl = t.heading and (fname .. " > " .. t.heading:lower()) or fname
      return bl:find(needle, 1, true) ~= nil
    end
  end

  local backlink_exc = line:match("^[Bb]acklink%s+does%s+not%s+include%s+(.+)$")
  if backlink_exc then
    local needle = backlink_exc:lower()
    return function(t)
      local fname = vim.fn.fnamemodify(t.file_path, ":t:r"):lower()
      local bl = t.heading and (fname .. " > " .. t.heading:lower()) or fname
      return bl:find(needle, 1, true) == nil
    end
  end

  -- id is X / id includes X
  local id_is = lower:match("^id%s+is%s+(.+)$")
  if id_is then
    return function(t) return t.id == id_is end
  end

  local id_inc = lower:match("^id%s+includes%s+(.+)$")
  if id_inc then
    return function(t) return t.id ~= nil and t.id:find(id_inc, 1, true) ~= nil end
  end

  -- depends on includes X
  local dep_inc = lower:match("^depends%s+on%s+includes%s+(.+)$")
  if dep_inc then
    return function(t)
      if not t.depends_on then return false end
      for _, dep in ipairs(t.depends_on) do
        if dep:find(dep_inc, 1, true) then return true end
      end
      return false
    end
  end

  -- regex filters for tags / path / heading / filename
  local tags_regex = line:match("^[Tt]ags%s+regex%s+matches%s+/(.+)/$")
  if tags_regex then
    return function(t)
      for _, tag in ipairs(t.tags) do
        if tag:match(tags_regex) then return true end
      end
      return false
    end
  end

  local path_regex = line:match("^[Pp]ath%s+regex%s+matches%s+/(.+)/$")
  if path_regex then
    return function(t) return t.file_path:match(path_regex) ~= nil end
  end

  local heading_regex = line:match("^[Hh]eading%s+regex%s+matches%s+/(.+)/$")
  if heading_regex then
    return function(t)
      if not t.heading then return false end
      return t.heading:match(heading_regex) ~= nil
    end
  end

  local fname_regex = line:match("^[Ff]ilename%s+regex%s+matches%s+/(.+)/$")
  if fname_regex then
    return function(t)
      return vim.fn.fnamemodify(t.file_path, ":t:r"):match(fname_regex) ~= nil
    end
  end

  return nil -- unrecognized filter line
end

return M
