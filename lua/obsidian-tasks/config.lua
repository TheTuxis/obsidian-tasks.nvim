local M = {}

M.defaults = {
  vault_path   = nil,
  date_format  = "%Y-%m-%d",
  global_query = "",
  keymaps = {
    toggle     = "<leader>tt",
    create     = "<leader>tc",
    open_query = "<leader>tq",
    picker     = "<leader>tf",
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
