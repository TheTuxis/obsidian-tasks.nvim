-- Entry point: loaded automatically by Neovim on startup.
-- Keeps this file thin — all logic lives in lua/obsidian-tasks/.

if vim.g.loaded_obsidian_tasks then return end
vim.g.loaded_obsidian_tasks = true

-- Guard: only load when the user calls setup()
-- (the plugin is opt-in via require('obsidian-tasks').setup())
