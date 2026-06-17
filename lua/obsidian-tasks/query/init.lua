local filter_mod  = require("obsidian-tasks.query.filter")
local boolean_mod = require("obsidian-tasks.query.boolean")
local sorter_mod  = require("obsidian-tasks.query.sorter")
local grouper_mod = require("obsidian-tasks.query.grouper")

local M = {}

-- Parse a query block text into a query spec table
function M.parse(query_text)
  local spec = {
    filters      = {},
    sorts        = {},
    groups       = {},
    limit        = nil,
    limit_groups = nil,
    hide         = {},
    errors       = {},
  }

  local lines = vim.split(query_text, "\n", { plain = true })

  -- Handle line continuations (trailing \)
  local joined = {}
  local accum = nil
  for _, line in ipairs(lines) do
    if accum then
      line = accum .. " " .. vim.trim(line)
      accum = nil
    end
    if line:match("\\$") then
      accum = line:sub(1, -2)
    else
      table.insert(joined, line)
    end
  end
  if accum then table.insert(joined, accum) end

  for _, raw_line in ipairs(joined) do
    local line = vim.trim(raw_line)

    -- Skip blank lines and comments
    if line == "" or line:match("^#") then goto continue end

    -- limit [to] N [tasks]
    local limit_n = line:match("^[Ll]imit%s+to%s+(%d+)")
      or line:match("^[Ll]imit%s+(%d+)")
    if limit_n then
      spec.limit = tonumber(limit_n)
      goto continue
    end

    -- limit groups to N
    local limit_g = line:match("^[Ll]imit%s+groups%s+to%s+(%d+)")
    if limit_g then
      spec.limit_groups = tonumber(limit_g)
      goto continue
    end

    -- sort by
    if line:lower():match("^sort%s+by") then
      local s = sorter_mod.parse(line)
      if s then
        -- store field name for dedup in sorter
        local field = line:lower():match("^sort%s+by%s+(%S+)")
        s.field = field
        table.insert(spec.sorts, s)
      else
        table.insert(spec.errors, "Unknown sort: " .. line)
      end
      goto continue
    end

    -- group by
    if line:lower():match("^group%s+by") then
      local g = grouper_mod.parse(line)
      if g then
        table.insert(spec.groups, g)
      else
        table.insert(spec.errors, "Unknown group: " .. line)
      end
      goto continue
    end

    -- hide / show
    local hide_field = line:match("^[Hh]ide%s+(.+)$")
    if hide_field then
      spec.hide[hide_field:lower()] = true
      goto continue
    end
    local show_field = line:match("^[Ss]how%s+(.+)$")
    if show_field then
      spec.hide[show_field:lower()] = false
      goto continue
    end

    -- ignore global query (placeholder)
    if line:lower() == "ignore global query" then goto continue end
    if line:lower() == "explain"             then goto continue end

    -- Try boolean expression first, then plain filter
    local fn
    if boolean_mod.is_boolean(line) then
      local bool_errors
      fn, bool_errors = boolean_mod.parse(line, filter_mod.parse)
      if bool_errors then
        for _, e in ipairs(bool_errors) do
          table.insert(spec.errors, e)
        end
      end
    end
    if not fn then
      fn = filter_mod.parse(line)
    end
    if fn then
      table.insert(spec.filters, fn)
    else
      table.insert(spec.errors, "Unrecognized: " .. line)
    end

    ::continue::
  end

  return spec
end

-- Execute a parsed query spec against a list of tasks
-- Returns list of { key, tasks[] } (groups)
function M.execute(spec, all_tasks)
  -- 1. Filter
  local filtered = {}
  for _, t in ipairs(all_tasks) do
    local pass = true
    for _, fn in ipairs(spec.filters) do
      if not fn(t) then
        pass = false
        break
      end
    end
    if pass then table.insert(filtered, t) end
  end

  -- 2. Sort
  local sorted = sorter_mod.apply(filtered, spec.sorts)

  -- 3. Group
  local groups = grouper_mod.apply(sorted, spec.groups)

  -- 4a. Limit groups
  if spec.limit_groups and #groups > spec.limit_groups then
    local trimmed = {}
    for i = 1, spec.limit_groups do trimmed[i] = groups[i] end
    groups = trimmed
  end

  -- 4b. Limit tasks
  if spec.limit then
    local total = 0
    for _, grp in ipairs(groups) do
      local remaining = spec.limit - total
      if remaining <= 0 then
        grp.tasks = {}
      elseif #grp.tasks > remaining then
        local trimmed = {}
        for i = 1, remaining do trimmed[i] = grp.tasks[i] end
        grp.tasks = trimmed
        total = spec.limit
      else
        total = total + #grp.tasks
      end
    end
  end

  return groups
end

-- High-level: parse query text and run against tasks, return groups
function M.run(query_text, all_tasks)
  local spec = M.parse(query_text)
  return M.execute(spec, all_tasks), spec.errors
end

return M
