# Roadmap

Features pending to reach full parity with [obsidian-tasks](https://github.com/obsidian-tasks-group/obsidian-tasks).

Items are ordered by impact within each section. Check them off as they land.

---

## Filters

### Boolean combinations
Support `AND`, `OR`, `NOT`, `XOR` with parentheses between any two filters.

```
(priority is high) OR (due before tomorrow)
NOT (done)
(has tags) AND NOT (path includes archive/)
(due before next week) XOR (scheduled before next week)
```

- [x] Tokenizer: split a filter line into tokens recognizing `(`, `)`, `AND`, `OR`, `NOT`, `XOR`
- [x] Recursive descent parser to build a predicate tree from tokens
- [x] Each leaf calls the existing `filter.parse()` for the inner expression
- [x] Wire into `query/init.lua` before the plain `filter.parse()` fallback

---

### Complex relative dates
All date filters (`due`, `scheduled`, `start`, `done`, `cancelled`, `created`) should support:

```
due in this week
due in this month
due in next quarter
due in last year
due in 2024-W14          ← ISO week
due in 2024-Q2           ← quarter
due in 2024-01           ← month
due 2024-01-01 2024-01-31  ← range between two dates
```

- [ ] `parse_relative_date` in `query/filter.lua`: add `this week`, `last week`, `next week`
- [ ] Add `this month`, `last month`, `next month`
- [ ] Add `this quarter`, `last quarter`, `next quarter`
- [ ] Add `this year`, `last year`, `next year`
- [ ] Add ISO week parsing: `YYYY-Www` → start/end of that week
- [ ] Add quarter parsing: `YYYY-Qn` → start/end of that quarter
- [ ] Add month parsing: `YYYY-MM` → start/end of that month
- [ ] Add two-date range syntax: `due YYYY-MM-DD YYYY-MM-DD`

---

### Dependency filters
Requires the dependency graph to be built at index time (see Features section).

```
id task-1
depends on task-1
depends on task-1,task-2
is blocking
is blocked
```

- [ ] `filter.parse()`: add `id <value>` filter
- [ ] `filter.parse()`: add `depends on <id>[,<id>...]` filter
- [ ] `filter.parse()`: add `is blocking` (other tasks have this task in their `depends_on`)
- [ ] `filter.parse()`: add `is blocked` (this task has unresolved `depends_on`)

---

### Missing filters

```
urgency above 1.5
urgency below 2.0
status.name includes <text>
status.name does not include <text>
status.name regex matches /<regex>/
tags regex matches /#[a-z]+/
tags regex does not match /<regex>/
description regex does not match /<regex>/
path regex matches /<regex>/
path regex does not match /<regex>/
heading regex matches /<regex>/
heading regex does not match /<regex>/
backlink includes [[OtherNote]]
folder <name>
root <name>
exclude sub-items
include sub-items
<field> date is invalid
```

- [ ] `urgency above/below` — compare computed urgency score
- [ ] `status.name` filters (includes / does not include / regex)
- [ ] `tags regex matches / does not match`
- [ ] `description regex does not match`
- [ ] `path regex matches / does not match`
- [ ] `heading regex matches / does not match`
- [ ] `backlink includes` — match against `[[Filename]]` wiki-links in the task line
- [ ] `folder <name>` — match parent directory name
- [ ] `root <name>` — match top-level vault folder
- [ ] `exclude sub-items` / `include sub-items` — filter by indentation level
- [ ] `<field> date is invalid` — detect malformed date strings

---

## Sort

```
sort by done
sort by cancelled
sort by id
sort by heading
```

- [ ] `sorter.lua`: add `done` (by done date)
- [ ] `sorter.lua`: add `cancelled` (by cancelled date)
- [ ] `sorter.lua`: add `id` (alphabetical by task ID)
- [ ] `sorter.lua`: add `heading` (alphabetical by section heading)

---

## Group

```
group by tag        ← task appears in one group per tag
group by created
group by done
group by cancelled
group by start
group by id
group by urgency
group by backlink
```

- [ ] `grouper.lua`: add `created`, `done`, `cancelled`, `start` (date-based groups)
- [ ] `grouper.lua`: add `id`
- [ ] `grouper.lua`: add `urgency` (by urgency value)
- [ ] `grouper.lua`: add `backlink`
- [ ] `grouper.lua`: fix `tag` to support multi-group (a task with 3 tags appears in 3 groups)
- [ ] `query/init.lua`: support multiple `group by` lines for nested grouping

---

## Query instructions

```
limit groups to 5         ← per-group limit, separate from global limit
short                     ← compact one-line display
full                      ← full display (default)
explain                   ← print what each filter does
preset <name>             ← run a named saved query
ignore global query       ← skip the vault-wide global filter
hide blocking
hide blocked
hide id
hide depends on
show blocking
```

- [ ] `query/init.lua`: parse `limit groups to N` and apply per group in `query/init.lua`
- [ ] `query/init.lua`: parse `short` / `full` and pass to renderer
- [ ] `renderer.lua`: compact mode — one line per task, no metadata
- [ ] `query/init.lua`: parse `explain` and render filter descriptions as a header in the window
- [ ] `config.lua` + `query/init.lua`: global query — applied to every query block in the vault
- [ ] `commands.lua`: `:TasksPreset` — save/load named query presets
- [ ] `renderer.lua`: add `hide blocking`, `hide blocked`, `hide id`, `hide depends on`

---

## Features

### Recurrence
When a recurring task is toggled to done, automatically insert a new task below it with the next due date calculated from the recurrence rule.

- [ ] Parse recurrence rules: `every day`, `every week`, `every month`, `every year`
- [ ] Parse `every N days/weeks/months`
- [ ] Parse `every week on Monday,Wednesday`
- [ ] Parse `every month on the 15th`
- [ ] Parse `every January on the 4th`
- [ ] On toggle-to-done: compute next date and insert new task line
- [ ] Respect `when done` vs `when scheduled` recurrence base

---

### Task dependencies
Build and expose a dependency graph across the vault.

- [ ] `index.lua`: after parsing all tasks, build `{ id → task }` map
- [ ] `index.lua`: compute `blocking` and `blocked` sets per task
- [ ] Expose via `index.get_task_by_id(id)`
- [ ] Wire `is blocking` / `is blocked` filters

---

### Global query
A single query defined in plugin config that is prepended to every query block in the vault (unless the block contains `ignore global query`).

- [ ] `config.lua`: add `global_query` string option
- [ ] `query/init.lua`: prepend global query lines before block query lines
- [ ] Skip when block contains `ignore global query`

---

### Custom filter / sort / group functions
Allow Lua expressions for maximum flexibility.

```
filter by function task.priority > 3
sort by function task.urgency * -1
group by function task.due_date and task.due_date.raw or "No date"
```

- [ ] `query/filter.lua`: detect `filter by function <expr>`, compile and run as Lua
- [ ] `query/sorter.lua`: detect `sort by function <expr>`
- [ ] `query/grouper.lua`: detect `group by function <expr>`
- [ ] Sandbox the expression (expose only the `task` table, no `io`/`os`)

---

### On completion actions
When a task is toggled to done, perform the action specified by `🏁`.

```
- [ ] Delete me when done 🏁 delete
- [ ] Archive me when done 🏁 move to Archive/done.md
```

- [ ] `commands.lua`: after toggle-to-done, check `task.on_completion`
- [ ] Implement `delete` — remove the line from the file
- [ ] Implement `move to <path>` — append task to target file and delete from source

---

### Task editor UI
Floating form to create or edit a task's fields interactively.

- [ ] `ui/editor.lua`: floating window with labeled fields (description, due, priority, scheduled, recurrence)
- [ ] Pre-populate fields when editing an existing task
- [ ] Write the updated line back to the source file on save
- [ ] Wire to `:TasksEdit` command and `<leader>te` keymap

---

### Custom statuses
User-defined checkbox characters with custom display icons and behavior.

```lua
require("obsidian-tasks").setup({
  custom_statuses = {
    { char = "!", name = "Important", type = "TODO" },
    { char = "?", name = "Maybe",     type = "TODO" },
  },
})
```

- [ ] `config.lua`: add `custom_statuses` list
- [ ] `task.lua`: merge custom chars into `STATUS_CHARS` and `STATUS_DISPLAY`
- [ ] `query/filter.lua`: `status.type` filter respects custom type mappings

---

### Query placeholders
Dynamic values expanded at query execution time.

```
path includes {{filename}}
due before {{date}}
heading includes {{heading}}
```

- [ ] `query/init.lua`: before parsing, expand `{{filename}}` → current buffer filename
- [ ] Expand `{{date}}` → today's date
- [ ] Expand `{{heading}}` → heading under cursor

---

### Urgency formula
Replace the current simple approximation with the exact obsidian-tasks formula.

Current score: `priority * 10 + overdue bonus`

Full formula weights: due date (12.0–0.2 sliding scale), priority (6.0/5.0/4.0/3.0/2.0/1.0), scheduled (5.0), start (3.0), tags multipliers.

- [ ] `query/sorter.lua`: implement the full urgency calculation in a dedicated `urgency.lua` module
- [ ] Use it in both `sort by urgency` and `urgency above/below` filter

---

### Auto-complete while typing
Suggest emoji completions as the user types a task in a markdown buffer.

- [ ] Detect when cursor is on a task line in insert mode
- [ ] Trigger completion popup with emoji options (📅, ⏳, 🛫, 🔼, 🔁, etc.)
- [ ] Works with nvim-cmp or the built-in `omnifunc`
