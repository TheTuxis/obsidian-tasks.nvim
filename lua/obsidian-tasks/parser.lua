local task_mod = require("obsidian-tasks.task")

local M = {}

-- Match a markdown checkbox line and extract components
-- Returns task table or nil
function M.parse_line(line, file_path, line_number, current_heading)
  -- Pattern: optional indent, list marker, space, [single-char], space, rest.
  -- Status char must be exactly one character that is not [ or ] — this prevents
  -- wiki links like [[Note title]] from being mistaken for checkboxes.
  local indent, marker, status_char, rest =
    line:match("^(%s*)([-*+])%s+%[([^%[%]])%]%s+(.*)$")

  if not indent then return nil end

  local status = task_mod.status_from_char(status_char)
  local meta = task_mod.parse_metadata(rest)

  return task_mod.new({
    status         = status,
    description    = meta.description,
    priority       = meta.priority,
    tags           = meta.tags,
    due_date       = meta.due_date,
    start_date     = meta.start_date,
    scheduled_date = meta.scheduled_date,
    done_date      = meta.done_date,
    cancelled_date = meta.cancelled_date,
    created_date   = meta.created_date,
    recurrence     = meta.recurrence,
    id             = meta.id,
    depends_on     = meta.depends_on,
    on_completion  = meta.on_completion,
    block_link     = meta.block_link,
    file_path      = file_path,
    line_number    = line_number,
    heading        = current_heading,
    indentation    = indent,
    list_marker    = marker,
  })
end

-- Parse all tasks from a list of lines (from a single file)
function M.parse_file_lines(lines, file_path)
  local tasks = {}
  local current_heading = nil
  local in_code_block = false

  for i, line in ipairs(lines) do
    -- Toggle fenced code block state (``` or ~~~, with optional language tag)
    if line:match("^%s*```") or line:match("^%s*~~~") then
      in_code_block = not in_code_block
    end

    if in_code_block then goto continue end

    -- Track ATX headings
    local heading_text = line:match("^#+%s+(.+)$")
    if heading_text then
      current_heading = heading_text
    end

    local t = M.parse_line(line, file_path, i, current_heading)
    if t then
      table.insert(tasks, t)
    end

    ::continue::
  end

  return tasks
end

-- Read a file and parse its tasks
function M.parse_file(file_path)
  local lines = {}
  local f = io.open(file_path, "r")
  if not f then return {} end
  for line in f:lines() do
    table.insert(lines, line)
  end
  f:close()
  return M.parse_file_lines(lines, file_path)
end

-- Detect if a buffer line range is a tasks query block
-- Returns: start_line (1-based), end_line (1-based), query_text or nil
function M.find_query_block_at_cursor(bufnr, cursor_row)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local n = #lines

  -- Walk upward from cursor to find opening ```tasks
  local block_start = nil
  for i = cursor_row, 1, -1 do
    local line = lines[i]
    if line:match("^```tasks%s*$") then
      block_start = i
      break
    elseif line:match("^```") and i ~= cursor_row then
      break -- hit a different code fence
    end
  end

  if not block_start then return nil end

  -- Walk downward to find closing ```
  local block_end = nil
  for i = block_start + 1, n do
    if lines[i]:match("^```%s*$") then
      block_end = i
      break
    end
  end

  if not block_end then return nil end

  -- Collect query lines (between fences)
  local query_lines = {}
  for i = block_start + 1, block_end - 1 do
    table.insert(query_lines, lines[i])
  end

  return block_start, block_end, table.concat(query_lines, "\n")
end

-- Find all tasks query blocks in a buffer
-- Returns list of { start_line, end_line, query_text }
function M.find_all_query_blocks(bufnr)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local blocks = {}
  local i = 1

  while i <= #lines do
    if lines[i]:match("^```tasks%s*$") then
      local block_start = i
      local block_end = nil
      i = i + 1
      while i <= #lines do
        if lines[i]:match("^```%s*$") then
          block_end = i
          break
        end
        i = i + 1
      end
      if block_end then
        local query_lines = {}
        for j = block_start + 1, block_end - 1 do
          table.insert(query_lines, lines[j])
        end
        table.insert(blocks, {
          start_line = block_start,
          end_line   = block_end,
          query_text = table.concat(query_lines, "\n"),
        })
      end
    end
    i = i + 1
  end

  return blocks
end

return M
