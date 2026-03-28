# Todo Operations

Shared workflow logic for `/liang-tdd:add-todo` and `/liang-tdd:check-todos`.

## Critical Rule: AskUserQuestion for ALL Questions

**NEVER ask questions as inline text.** Every question to the user MUST use the
AskUserQuestion tool. This applies to confirmations, selections, and actions.

---

## Storage Layout

```
.planning/vibe/todos/
├── pending/
│   ├── 2026-03-28-force-sync-toggle.md
│   └── 2026-03-28-income-expenses-viewer.md
└── done/
    └── 2026-03-15-fix-csv-headers.md
```

**File naming:** `{YYYY-MM-DD}-{slug}.md`

**Frontmatter format:**
```markdown
---
created: YYYY-MM-DD
title: Short descriptive title
---

Description of the task, idea, or future mission. Enough context for a future
conversation to understand what this is about without additional questions.
```

---

## Add Todo

### Step 1: Ensure Directories

```bash
mkdir -p .planning/vibe/todos/pending .planning/vibe/todos/done
```

### Step 2: Extract Content

**With arguments** (e.g., `/liang-tdd:add-todo Force sync toggle`):
- Use the argument text as the title
- Generate a description by expanding on the title with any relevant context
  from the current conversation

**Without arguments:**
- Analyze the recent conversation to identify actionable items, ideas, or
  decisions that should be captured
- Formulate candidate todos (title + description for each)
- Use AskUserQuestion to present candidates and ask which to save:
  - Each candidate as an option with its description
  - "None" option to cancel
- Only save confirmed items

### Step 3: Check Duplicates

```bash
ls .planning/vibe/todos/pending/*.md 2>/dev/null
```

For each existing todo, read its title. If a close match exists, use
AskUserQuestion:
- header: "Duplicate?"
- question: "Similar todo exists: '[existing title]'. What would you like to do?"
- options:
  - "Skip" — keep existing, don't add
  - "Replace" — overwrite existing with new content
  - "Add anyway" — create as separate todo

### Step 4: Generate Slug and Write File

Slugify the title: lowercase, replace spaces/special chars with hyphens, trim to
50 chars max.

Get today's date: `date +%Y-%m-%d`

Write to `.planning/vibe/todos/pending/{date}-{slug}.md`:

```markdown
---
created: {date}
title: {title}
---

{description}
```

### Step 5: Git Commit

```bash
git add .planning/vibe/todos/pending/{filename}
git commit -m "todo: capture — {title}"
```

### Step 6: Confirm

Print:
```
Todo saved: .planning/vibe/todos/pending/{filename}

  {title}

Continue with current work, or /liang-tdd:check-todos to manage todos.
```

---

## Check Todos

### Step 1: Scan Pending

```bash
ls .planning/vibe/todos/pending/*.md 2>/dev/null
```

If no files found, print:
```
No pending todos.

Capture ideas during sessions with /liang-tdd:add-todo.
```
Then exit.

### Step 2: List Todos

Read each pending todo file. Extract `title` and `created` from frontmatter.
Calculate age as relative time (e.g., "2d ago", "5h ago", "just now").

Use AskUserQuestion:
- header: "Todos"
- question: "Select a todo to view details and take action:"
- options: each todo as `{title} ({age})` with description from the file body
  (first 100 chars)

### Step 3: Load Full Context

Read the selected todo file completely. Display:

```
## {title}

**Created:** {date} ({age})

{full description}
```

### Step 4: Offer Actions

Use AskUserQuestion:
- header: "Action"
- question: "What would you like to do with this todo?"
- options:
  - "Promote to mission" — start /liang-tdd:add-mission with this title as topic
  - "Edit" — modify the title or description
  - "Delete" — remove this todo
  - "Back to list" — return to the todo list

### Step 5: Execute Action

**Promote to mission:**
1. Move file to done/:
   ```bash
   mv .planning/vibe/todos/pending/{filename} .planning/vibe/todos/done/
   ```
2. Git commit:
   ```bash
   git add .planning/vibe/todos/done/{filename}
   git rm --cached .planning/vibe/todos/pending/{filename} 2>/dev/null || true
   git commit -m "todo: promote to mission — {title}"
   ```
3. Invoke the skill:
   ```
   /liang-tdd:add-mission {title}
   ```

**Edit:**
1. Use AskUserQuestion to ask for updated title and/or description
2. Rewrite the file with updated content
3. Git commit:
   ```bash
   git add .planning/vibe/todos/pending/{filename}
   git commit -m "todo: edit — {title}"
   ```
4. Return to Step 4 (offer actions again)

**Delete:**
1. Use AskUserQuestion to confirm:
   - header: "Confirm"
   - question: "Delete todo '{title}'? This cannot be undone."
   - options: "Yes, delete" / "No, keep it"
2. If confirmed:
   ```bash
   git rm .planning/vibe/todos/pending/{filename}
   git commit -m "todo: delete — {title}"
   ```
3. Return to Step 2 (list remaining todos)

**Back to list:**
Return to Step 2.
