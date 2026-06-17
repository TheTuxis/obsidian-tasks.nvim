# obsidian-tasks.nvim

A Neovim port of the [obsidian-tasks](https://github.com/obsidian-tasks-group/obsidian-tasks) Obsidian plugin.

Track tasks across your entire markdown vault. Write queries, filter by date and priority, and jump to any task — all without leaving Neovim.

---

## Features

- **Full task syntax** — emoji-based metadata: due dates, priority, scheduled, start, recurrence, and more
- **Vault-wide index** — scans all `.md` files automatically and updates on save
- **Query blocks** — write ` ```tasks ``` ` query blocks in any note; open results in a floating window
- **Rich filtering** — filter by status, dates, priority, tags, description, path, and heading
- **Sorting & grouping** — sort and group results by any field
- **Task toggle** — toggle `[ ]` ↔ `[x]` anywhere, automatically appends the done date
- **Task creation** — guided prompt to insert a new task at the cursor
- **Telescope picker** — fuzzy-search all tasks across your vault

---

## Requirements

- Neovim **0.9+**
- [plenary.nvim](https://github.com/nvim-lua/plenary.nvim) — required
- [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim) — optional, for the task picker

---

## Installation

### lazy.nvim

```lua
{
  "TheTuxis/obsidian-tasks.nvim",
  dependencies = {
    "nvim-lua/plenary.nvim",
    "nvim-telescope/telescope.nvim", -- optional
  },
  ft = "markdown",
  config = function()
    require("obsidian-tasks").setup({
      vault_path = "~/Notes",
    })
  end,
}
```

### packer.nvim

```lua
use {
  "TheTuxis/obsidian-tasks.nvim",
  requires = { "nvim-lua/plenary.nvim" },
  config = function()
    require("obsidian-tasks").setup({
      vault_path = "~/Notes",
    })
  end,
}
```

---

## Configuration

Call `setup()` with any options you want to override. All keys are optional.

```lua
require("obsidian-tasks").setup({
  -- Path to your Obsidian vault (defaults to the current working directory)
  vault_path = "~/Notes",

  -- Date format used when inserting dates (e.g. on task creation)
  date_format = "%Y-%m-%d",

  -- Keymaps (set any to "" to disable)
  keymaps = {
    toggle     = "<leader>tt", -- toggle task status under cursor
    create     = "<leader>tc", -- create a new task at cursor
    open_query = "<leader>tq", -- open floating window for query block under cursor
    picker     = "<leader>tf", -- open Telescope task picker
  },

  -- Enable Telescope picker integration
  telescope = true,

  -- Floating window appearance
  floating_window = {
    border     = "rounded", -- "none", "single", "double", "rounded", "shadow"
    max_height = 30,
    max_width  = 80,
  },
})
```
---

## Screen

![Screen](/docs/screen.png)

---

## Task Syntax

Tasks are standard markdown checkboxes with emoji metadata appended after the description.

```markdown
- [ ] Buy groceries 🔼 📅 2026-06-20
- [x] Submit report ✅ 2026-06-15
- [-] Old idea (cancelled)
- [/] Work in progress
```

### Status

| Checkbox | Meaning     |
|----------|-------------|
| `[ ]`    | To do       |
| `[x]`    | Done        |
| `[-]`    | Cancelled   |
| `[/]`    | In progress |
| `[>]`    | Forwarded   |

### Priority

| Emoji | Priority |
|-------|----------|
| 🔺    | Highest  |
| ⏫    | High     |
| 🔼    | Medium   |
| *(none)* | Normal |
| 🔽    | Low      |
| ⏬    | Lowest   |

### Date Fields

| Emoji     | Field          | Example              |
|-----------|----------------|----------------------|
| 📅 📆 🗓  | Due date       | `📅 2026-06-20`      |
| 🛫        | Start date     | `🛫 2026-06-18`      |
| ⏳ ⌛     | Scheduled date | `⏳ 2026-06-19`      |
| ✅        | Done date      | `✅ 2026-06-15`      |
| ❌        | Cancelled date | `❌ 2026-06-10`      |
| ➕        | Created date   | `➕ 2026-06-01`      |

### Other Fields

| Emoji | Field        | Example                      |
|-------|--------------|------------------------------|
| 🔁    | Recurrence   | `🔁 every week on Monday`    |
| 🆔    | Task ID      | `🆔 my-task-1`               |
| ⛔    | Depends on   | `⛔ my-task-1,my-task-2`     |
| 🏁    | On complete  | `🏁 delete`                  |

### Full Example

```markdown
- [ ] Write quarterly report ⏫ 📅 2026-06-30 🛫 2026-06-20 🔁 every quarter 🆔 q2-report
```

---

## Query Blocks

Place a ` ```tasks ``` ` fenced code block anywhere in your vault. Position your cursor inside it and run `:TasksQuery` (or `<leader>tq`) to open the results in a floating window.

````markdown
```tasks
not done
due before tomorrow
sort by priority
group by due
limit 20
```
````

Inside the floating window:

- Press `<CR>` on any task line to jump to its source file
- Press `q` or `<Esc>` to close

### Filters

**Status**

```
done
not done
status.type is TODO
status.type is DONE
status.type is IN_PROGRESS
status.type is CANCELLED
is recurring
is not recurring
has tags
no tags
```

**Dates** — works with `due`, `scheduled`, `start`, `done`, `cancelled`, `created`

```
due today
due before tomorrow
due after 2026-06-01
due on or before 2026-06-30
has due date
no due date
due in 7 days
due 3 days ago
due next monday
due last friday
```

**Priority**

```
priority is highest
priority is high
priority is medium
priority is none
priority is low
priority is lowest
priority above medium
priority below high
priority not low
```

**Text & path**

```
description includes meeting
description does not include cancelled
description regex matches /^URGENT/
path includes projects/
filename includes daily
heading includes Work
tags include #work
tags does not include #personal
```

### Sorting

```
sort by priority
sort by due
sort by due reverse
sort by description
sort by path
sort by status
sort by urgency
sort by scheduled
sort by created
```

Multiple `sort by` lines are applied in order. A sensible default sort is always appended automatically.

### Grouping

```
group by priority
group by status
group by due
group by path
group by filename
group by heading
group by recurrence
```

### Layout

```
limit 10
limit to 25 tasks
hide priority
hide due
hide scheduled
hide start
hide tags
hide backlink
hide recurring
show priority
```

### Comments

Lines starting with `#` are ignored:

```
# Show only urgent work tasks
not done
priority above medium
path includes work/
```

---

## Commands

| Command              | Description                                          |
|----------------------|------------------------------------------------------|
| `:TasksQuery`        | Open query block under cursor in a floating window   |
| `:TasksToggle`       | Toggle task status on current line                   |
| `:TasksCreate`       | Create a new task at the cursor (guided prompts)     |
| `:TasksPicker`       | Open Telescope picker for all vault tasks            |
| `:TasksRebuildIndex` | Rebuild the full vault task index                    |

---

## Default Keymaps

| Keymap        | Action                      |
|---------------|-----------------------------|
| `<leader>tq`  | Open query result window    |
| `<leader>tt`  | Toggle task under cursor    |
| `<leader>tc`  | Create new task             |
| `<leader>tf`  | Open Telescope task picker  |

All keymaps can be overridden or disabled in `setup()`.

---

## Telescope Picker

`:TasksPicker` opens a fuzzy-search window over all tasks in your vault.

- **Type** to filter by description or file path
- **`<CR>`** — jump to the task in its source file
- **`<C-t>`** — toggle the task status without leaving the picker

---

## Local Development

Clone the repo and use the included minimal init to test without touching your main config:

```bash
git clone git@github.com:TheTuxis/obsidian-tasks.nvim.git
cd obsidian-tasks.nvim
nvim -u minimal_init.lua path/to/your/vault/note.md
```

---

## Roadmap

- [ ] Full relative date expressions (`this week`, `next month`, `last quarter`)
- [ ] Recurrence scheduling (auto-create next occurrence on completion)
- [ ] Task dependency tracking (`is blocking` / `is blocked`)
- [ ] Floating task editor UI
- [ ] Boolean filter combinations (`(done) OR (priority is high)`)
- [ ] Custom Lua filter/sort/group expressions

---

## Contributing

Contributions are welcome. Please open an issue to discuss significant changes before submitting a pull request.

1. Fork the repository
2. Create a feature branch (`git checkout -b feat/my-feature`)
3. Commit your changes
4. Open a pull request

---

## License

[MIT](LICENSE) © TheTuxis

---

## Acknowledgements

This plugin is a Neovim port of [obsidian-tasks](https://github.com/obsidian-tasks-group/obsidian-tasks) by the obsidian-tasks-group. All credit for the task syntax and query language design goes to the original authors.
