local config_mod   = require("obsidian-tasks.config")
local index        = require("obsidian-tasks.index")
local commands     = require("obsidian-tasks.commands")
local renderer     = require("obsidian-tasks.renderer")

local M = {}

local _setup_done = false

function M.setup(opts)
  if _setup_done then return end
  _setup_done = true

  local cfg = config_mod.resolve(opts)

  -- Initialize modules with config
  index.init(cfg.vault_path)
  commands.register(cfg)
  renderer.setup(cfg)

  -- Autocmds
  local group = vim.api.nvim_create_augroup("ObsidianTasks", { clear = true })

  -- Rebuild index for any written markdown file
  vim.api.nvim_create_autocmd("BufWritePost", {
    group   = group,
    pattern = "*.md",
    callback = function(ev)
      index.update_file(ev.file)
    end,
  })

  -- Lazy-build index on first markdown buffer open
  vim.api.nvim_create_autocmd("BufEnter", {
    group   = group,
    pattern = "*.md",
    once    = true,
    callback = function()
      vim.schedule(function() index.rebuild() end)
    end,
  })

  -- When loaded lazily via ft = "markdown", BufEnter has already fired for
  -- the current buffer before the autocmd above was registered. Detect this
  -- and trigger the initial rebuild immediately.
  if vim.bo.filetype == "markdown" then
    vim.schedule(function() index.rebuild() end)
  end
end

-- Expose index and query for external use
M.index = index
M.query = require("obsidian-tasks.query")

return M
