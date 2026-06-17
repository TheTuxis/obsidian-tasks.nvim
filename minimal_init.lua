-- Minimal init for local development and testing.
-- Usage:
--   nvim -u minimal_init.lua path/to/your/vault/note.md
--
-- Adjust the paths below to match your local plugin locations.

local plugin_dir = vim.fn.expand("<sfile>:p:h")
vim.opt.rtp:prepend(plugin_dir)

-- Plenary is required. Point this to wherever you have it installed.
-- Common locations:
--   ~/.local/share/nvim/lazy/plenary.nvim
--   ~/.local/share/nvim/site/pack/packer/start/plenary.nvim
local plenary_path = vim.fn.expand("~/.local/share/nvim/lazy/plenary.nvim")
if vim.fn.isdirectory(plenary_path) == 1 then
  vim.opt.rtp:prepend(plenary_path)
end

require("obsidian-tasks").setup({
  vault_path = vim.fn.getcwd(),
  keymaps = {
    toggle     = "<leader>tt",
    create     = "<leader>tc",
    open_query = "<leader>tq",
    picker     = "<leader>tf",
  },
})
