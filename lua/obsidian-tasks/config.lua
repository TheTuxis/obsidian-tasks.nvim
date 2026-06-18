local M = {}

M.defaults = {
  vault_path   = nil,
  date_format  = "%Y-%m-%d",
  global_query = "",
  capture = {
    path        = nil,               -- absolute path to daily notes folder (required)
    dir_format  = "%Y/%m",           -- subdirectory pattern inside path
    file_format = "%Y-%m-%d Tasks",  -- daily filename without .md
    section     = "Inbox",           -- ## section to append under; nil = end of file
  },
  keymaps = {
    toggle     = "<leader>tt",
    create     = "<leader>tc",
    open_query = "<leader>tq",
    picker     = "<leader>tf",
    edit       = "<leader>te",
    capture    = "<leader>tC",
  },
  telescope = true,
  floating_window = {
    border     = "rounded",
    max_height = 30,
    max_width  = 80,
  },
}

function M.resolve(opts)
  local cfg = vim.tbl_deep_extend("force", {}, M.defaults, opts or {})
  cfg.vault_path = vim.fn.expand(cfg.vault_path or vim.fn.getcwd()):gsub("[/\\]$", "")
  return cfg
end

return M
