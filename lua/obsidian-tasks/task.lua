local M = {}

-- Status constants
M.STATUS = {
  TODO        = "todo",
  DONE        = "done",
  CANCELLED   = "cancelled",
  IN_PROGRESS = "in_progress",
  FORWARDED   = "forwarded",
}

-- Priority constants (numeric for comparison: higher = more urgent)
M.PRIORITY = {
  HIGHEST = 5,
  HIGH    = 4,
  MEDIUM  = 3,
  NONE    = 2,
  LOW     = 1,
  LOWEST  = 0,
}

M.PRIORITY_NAMES = {
  [5] = "Highest",
  [4] = "High",
  [3] = "Medium",
  [2] = "None",
  [1] = "Low",
  [0] = "Lowest",
}

local STATUS_CHARS = {
  [" "] = M.STATUS.TODO,
  ["x"] = M.STATUS.DONE,
  ["X"] = M.STATUS.DONE,
  ["-"] = M.STATUS.CANCELLED,
  ["/"] = M.STATUS.IN_PROGRESS,
  [">"] = M.STATUS.FORWARDED,
}

local STATUS_DISPLAY = {
  [M.STATUS.TODO]        = "☐",
  [M.STATUS.DONE]        = "☑",
  [M.STATUS.CANCELLED]   = "☒",
  [M.STATUS.IN_PROGRESS] = "◐",
  [M.STATUS.FORWARDED]   = "→",
}

-- Emoji definitions for metadata fields
local EMOJI = {
  -- Priority (order matters: check longest/most specific first)
  priority = {
    { emoji = "\xF0\x9F\x94\xBA", level = M.PRIORITY.HIGHEST }, -- 🔺
    { emoji = "\xE2\x8F\xAB",     level = M.PRIORITY.HIGH },    -- ⏫
    { emoji = "\xF0\x9F\x94\xBC", level = M.PRIORITY.MEDIUM },  -- 🔼
    { emoji = "\xF0\x9F\x94\xBD", level = M.PRIORITY.LOW },     -- 🔽
    { emoji = "\xE2\x8F\xAC",     level = M.PRIORITY.LOWEST },  -- ⏬
  },
  -- Dates
  due = {
    "\xF0\x9F\x93\x85", -- 📅
    "\xF0\x9F\x93\x86", -- 📆
    "\xF0\x9F\x97\x93", -- 🗓
  },
  start      = { "\xF0\x9F\x9B\xAB" }, -- 🛫
  scheduled  = { "\xE2\x8F\xB3", "\xE2\x8C\x9B" }, -- ⏳ ⌛
  done_date  = { "\xE2\x9C\x85" }, -- ✅
  cancelled_date = { "\xE2\x9D\x8C" }, -- ❌
  created    = { "\xE2\x9E\x95" }, -- ➕
  -- Other
  recurrence    = { "\xF0\x9F\x94\x81" }, -- 🔁
  on_completion = { "\xF0\x9F\x8F\x81" }, -- 🏁
  id            = { "\xF0\x9F\x86\x94" }, -- 🆔
  depends_on    = { "\xE2\x9B\x94" },     -- ⛔
}

-- Variant selector suffix (optional, strip it)
local VS16 = "\xEF\xB8\x8F"

local function strip_vs16(s)
  return s:gsub(VS16, "")
end

-- Parse a YYYY-MM-DD date string into a table {year, month, day} or nil
local function parse_date(s)
  if not s then return nil end
  local y, m, d = s:match("^(%d%d%d%d)-(%d%d)-(%d%d)$")
  if y then
    return { year = tonumber(y), month = tonumber(m), day = tonumber(d), raw = s }
  end
  return nil
end

-- Convert date table to os.time comparable integer (days since epoch proxy)
function M.date_to_days(dt)
  if not dt then return nil end
  return os.time({ year = dt.year, month = dt.month, day = dt.day, hour = 0, min = 0, sec = 0 })
end

function M.today_days()
  local t = os.date("*t")
  return os.time({ year = t.year, month = t.month, day = t.day, hour = 0, min = 0, sec = 0 })
end

-- Parse the trailing metadata portion of a task description
-- Returns: { description, priority, due_date, start_date, scheduled_date,
--            done_date, cancelled_date, created_date, recurrence, id, depends_on, on_completion, tags }
function M.parse_metadata(raw_desc)
  local desc = strip_vs16(raw_desc)

  local result = {
    priority       = M.PRIORITY.NONE,
    tags           = {},
    recurrence     = nil,
    id             = nil,
    depends_on     = nil,
    on_completion  = nil,
    due_date       = nil,
    start_date     = nil,
    scheduled_date = nil,
    done_date      = nil,
    cancelled_date = nil,
    created_date   = nil,
  }

  -- Extract tags (#word)
  for tag in desc:gmatch("#([%w_/-]+)") do
    table.insert(result.tags, "#" .. tag)
  end

  -- Priority emojis
  for _, p in ipairs(EMOJI.priority) do
    if desc:find(p.emoji, 1, true) then
      result.priority = p.level
      desc = desc:gsub(vim.pesc(p.emoji), "")
      break
    end
  end

  -- Date fields
  local date_fields = {
    { key = "due_date",        emojis = EMOJI.due },
    { key = "start_date",      emojis = EMOJI.start },
    { key = "scheduled_date",  emojis = EMOJI.scheduled },
    { key = "done_date",       emojis = EMOJI.done_date },
    { key = "cancelled_date",  emojis = EMOJI.cancelled_date },
    { key = "created_date",    emojis = EMOJI.created },
  }

  for _, field in ipairs(date_fields) do
    for _, emoji in ipairs(field.emojis) do
      local pattern = vim.pesc(emoji) .. "%s*(%d%d%d%d%-%d%d%-%d%d)"
      local date_str = desc:match(pattern)
      if date_str then
        result[field.key] = parse_date(date_str)
        desc = desc:gsub(vim.pesc(emoji) .. "%s*%d%d%d%d%-%d%d%-%d%d", "")
        break
      end
    end
  end

  -- Recurrence (match word-like text: letters, spaces, digits, hyphens, slashes, commas)
  for _, emoji in ipairs(EMOJI.recurrence) do
    local val = desc:match(vim.pesc(emoji) .. "%s*([%a%s%d%-/,]+)")
    if val then
      result.recurrence = vim.trim(val)
      desc = desc:gsub(vim.pesc(emoji) .. "%s*[%a%s%d%-/,]*", "")
      break
    end
  end

  -- On completion
  for _, emoji in ipairs(EMOJI.on_completion) do
    local val = desc:match(vim.pesc(emoji) .. "%s*(%S+)")
    if val then
      result.on_completion = val
      desc = desc:gsub(vim.pesc(emoji) .. "%s*%S+", "")
      break
    end
  end

  -- ID
  for _, emoji in ipairs(EMOJI.id) do
    local val = desc:match(vim.pesc(emoji) .. "%s*(%S+)")
    if val then
      result.id = val
      desc = desc:gsub(vim.pesc(emoji) .. "%s*%S+", "")
      break
    end
  end

  -- Depends on
  for _, emoji in ipairs(EMOJI.depends_on) do
    local val = desc:match(vim.pesc(emoji) .. "%s*(%S+)")
    if val then
      result.depends_on = vim.split(val, ",", { plain = true })
      desc = desc:gsub(vim.pesc(emoji) .. "%s*%S+", "")
      break
    end
  end

  -- Block link (^anchor)
  local block_link = desc:match("%s%^(%S+)%s*$")
  if block_link then
    result.block_link = block_link
    desc = desc:gsub("%s%^%S+%s*$", "")
  end

  result.description = vim.trim(desc)
  return result
end

-- Create a new task table from parsed components
function M.new(opts)
  return {
    status         = opts.status or M.STATUS.TODO,
    description    = opts.description or "",
    priority       = opts.priority or M.PRIORITY.NONE,
    tags           = opts.tags or {},
    due_date       = opts.due_date,
    start_date     = opts.start_date,
    scheduled_date = opts.scheduled_date,
    done_date      = opts.done_date,
    cancelled_date = opts.cancelled_date,
    created_date   = opts.created_date,
    recurrence     = opts.recurrence,
    id             = opts.id,
    depends_on     = opts.depends_on,
    on_completion  = opts.on_completion,
    block_link     = opts.block_link,
    -- Location
    file_path      = opts.file_path,
    line_number    = opts.line_number,
    heading        = opts.heading,
    indentation    = opts.indentation or "",
    list_marker    = opts.list_marker or "-",
  }
end

function M.status_char(status)
  local chars = {
    [M.STATUS.TODO]        = " ",
    [M.STATUS.DONE]        = "x",
    [M.STATUS.CANCELLED]   = "-",
    [M.STATUS.IN_PROGRESS] = "/",
    [M.STATUS.FORWARDED]   = ">",
  }
  return chars[status] or " "
end

function M.status_from_char(ch)
  return STATUS_CHARS[ch] or M.STATUS.TODO
end

function M.display_status(status)
  return STATUS_DISPLAY[status] or "☐"
end

function M.is_complete(task)
  return task.status == M.STATUS.DONE or task.status == M.STATUS.CANCELLED
end

return M
