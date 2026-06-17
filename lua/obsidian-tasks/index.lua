local parser = require("obsidian-tasks.parser")

local M = {}

-- Internal state
local _tasks_by_file = {} -- { [file_path] = tasks[] }
local _all_tasks     = {} -- flat list
local _vault_path    = nil
local _initialized   = false

local function rebuild_flat()
  _all_tasks = {}
  for _, tasks in pairs(_tasks_by_file) do
    for _, t in ipairs(tasks) do
      table.insert(_all_tasks, t)
    end
  end
end

-- Recursively scan directory and collect .md files
local function scan_dir(dir, result)
  local handle = vim.uv.fs_scandir(dir)
  if not handle then return end

  while true do
    local name, typ = vim.uv.fs_scandir_next(handle)
    if not name then break end

    local full_path = dir .. "/" .. name
    if typ == "directory" and not name:match("^%.") then
      scan_dir(full_path, result)
    elseif typ == "file" and name:match("%.md$") then
      table.insert(result, full_path)
    end
  end
end

function M.init(vault_path)
  _vault_path = vault_path
  _initialized = false
end

function M.rebuild()
  if not _vault_path then return end

  _tasks_by_file = {}
  local md_files = {}
  scan_dir(_vault_path, md_files)

  for _, path in ipairs(md_files) do
    _tasks_by_file[path] = parser.parse_file(path)
  end

  rebuild_flat()
  _initialized = true
end

-- Update index for a single file (called on BufWritePost)
function M.update_file(file_path)
  if not _initialized then
    M.rebuild()
    return
  end

  _tasks_by_file[file_path] = parser.parse_file(file_path)
  rebuild_flat()
end

function M.all_tasks()
  if not _initialized then
    M.rebuild()
  end
  return _all_tasks
end

function M.tasks_for_file(file_path)
  return _tasks_by_file[file_path] or {}
end

function M.is_initialized()
  return _initialized
end

return M
