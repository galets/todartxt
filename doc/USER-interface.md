This document describes the **current state** of the Todart_txt (`To-Dart-TXT`) desktop UI as implemented in `lib/features/tasks/task_list_page.dart` and `lib/main.dart`.

---

# UI Description: Todo.txt Client (Current)

## 1. Visual Design

*   **Style:** Clean, high-density, utility-first desktop layout. Light theme only.
*   **Colors:**
    *   App background: `#F3F4F6`, sidebar/toolbar: white.
    *   Task rows alternate `white` / `#FAFAFA`; selected row `blue.shade50`.
    *   Priority badge: `A` = red (`red.shade600`), `B` = orange (`orange.shade600`), `C` and below = blue (`blue.shade600`), white bold text, rounded 4px.
    *   Inline priority text: `(A)` red bold, `(B)` orange bold, others blue bold.
    *   Dates (`YYYY-MM-DD`): gray (`grey.shade600`, 12.5pt).
    *   Description: dark gray `#212121`, 13.5pt.
    *   `@context` pill: teal text (`teal.shade700`, semibold) on `teal.shade50` background with `teal.shade200` border, 10px radius.
    *   `+project` pill: green text (`green.shade800`, semibold) on `green.shade50` background with `green.shade200` border.
    *   `key:value` metadata (e.g. `due:2023-05-01`): gray italic, 12.5pt.
    *   Completed tasks: single `TextSpan` with gray strikethrough; row wrapped in `Opacity(0.55)`.
*   **Typography:** Default Flutter sans-serif (`RichText` / `ListTile`).

## 2. Layout Structure

There is **no native global menu bar**. The window contains (top to bottom):

### A. App / Window Title

*   Window title: `todart_txt` (see screenshot). `MaterialApp.title` is `To-Dart-TXT`.

### B. Toolbar (top, white `Container`)

Left to right:

1.  **Search field:** 220x34 `TextField`, hint `Search…`, magnifier prefix. Live-filters list by case-insensitive substring of `Task.toText()`.
2.  **Search icon** (`Search (/)` tooltip): focuses the search field.
3.  **Add** (`+`): opens Add-task dialog. Always enabled.
4.  **Edit** (pencil): opens Edit-task dialog for selected task. Disabled when nothing selected.
5.  **Delete** (trash): deletes selected task. Disabled when nothing selected.
6.  **Complete** (checkmark): marks selected task completed via `repository.toggleCompleted()`. Disabled when nothing selected; no-op if already completed.
7.  **Undo**: calls `repository.undo()`. Disabled when `!canUndo`.
8.  Vertical divider.
9.  **Save** (disk): calls `repository.save()` (also `Ctrl+S` via `CallbackShortcuts`). Toast/errors swallowed; refreshes UI.
10. Vertical divider.
11. **View** (eye icon, `PopupMenuButton`): checkable toggles `Show dates` (default on), `Show priorities` (default on), `Show tags` (default on). Hidden tokens are skipped in `_highlight()`.
12. **Sort** (sort icon, `PopupMenuButton<_SortMode>`): `none`, `priority` (default), `date`, `project`. Completed tasks always sink to bottom (`completedLast` comparator); then priority string compare / first `YYYY-MM-DD` in text (`9999-99-99` fallback) / first project (`~~~` fallback for none).
13. **Counter** (right-aligned): `${visible.length}/${tasks.length} tasks`, 12pt gray.

### C. Sidebar / Filter Panel (left, fixed 230px, white)

`ListView` with section headers (`FILTERS`, `CONTEXTS`, `PROJECTS`, `PRIORITIES`, `STATUS`; 10pt bold gray, letter-spacing 0.8). Each row is a dense `ListTile` (16px leading icon, 13pt label, gray count trailing, `blue.shade50` when active). Clicking sets `_filter` and clears selection.

*   **FILTERS:**
    *   `All` (inbox icon) — everything.
    *   `Uncategorized` (label_off icon) — `context.isEmpty && project.isEmpty`.
    *   `Due` (event icon) — `toText()` contains `due:\S+`. Count 0 in screenshot.
*   **CONTEXTS:** one row per unique `Task.context` value, sorted alphabetically. Label `@name` with alternate_email icon, count of matching tasks. Visible in screenshot: `@auto(1)`, `@family(2)`, `@finance(6)`, `@galets.net(1)`, `@home(6)`, `@it(28)`, `@me(1)`.
*   **PROJECTS:** one row per unique `Task.project` value (`+name`, folder icon). Empty in screenshot because the sample `todo.txt` uses no `+tags`.
*   **PRIORITIES:** one row per non-null `Task.priority`, sorted (`(A)(4)`, `(B)(5)`, `(C)(4)`, `(D)(2)` in screenshot). Flag icon.
*   **STATUS:** `Complete` (check_circle icon) — `t.completed`.

### D. Main Task List (center/right, expanded)

*   Empty state: `Center(child: Text('No tasks match filter'))`.
*   Otherwise `ListView.builder` over `_visibleIndices` (filter + search + sort applied).
*   Each row: `GestureDetector` + `Container` (horizontal 8, vertical 5) + `Row`:
    *   Leading `Checkbox` (`visualDensity.compact`) bound to `t.completed`; `onChanged` calls `repository.toggleCompleted(i)`.
    *   Priority badge (only if `_showPriorities && t.priority != null && !t.completed`): colored container + white bold 11pt letter.
    *   Expanded `Opacity` + `RichText` from `_highlight(raw, t)`.
*   **Task line rendering (`_highlight`):** token regex `^(\([A-Z]\)|x\b)|\d{4}-\d{2}-\d{2}|[+@]\S+|\S+:\S+|\(.\)|\S+|\s+`. `+`/`@` tokens become tappable `WidgetSpan` pills that set the sidebar filter to that context/project. Other tokens are plain `TextSpan`s with styles from §1. Note: screenshot duplicates badge + inline `(A)` text because both are shown.

### E. Floating Action Button

*   Bottom-right `FloatingActionButton` (`+`, tooltip `Add task`): same as toolbar Add.

---

## 3. Interaction Logic & Parsing Rules

Parser/engine is the `todo_txt` package (`Task.fromText` / `Task.toText`), not hand-rolled regex:

*   Priority, completion (`x ` + dates), `@context`, `+project`, `key:value` are derived from `Task` fields; `Due` filter and date sort additionally regex raw text (`due:\S+`, `\d{4}-\d{2}-\d{2}`).

User interactions (all in-memory + `TaskRepository`, persisted on save):

1.  **Single click:** selects task (blue highlight; enables Edit/Delete/Complete).
2.  **Double click:** opens `AlertDialog` (`Add task` / `Edit task`) with a `TextField` (hint `(A) Call mom +Family @phone due:2023-05-01`), `Cancel`/`Save`; Save parses via `Task.fromText` and calls `repository.add` / `repository.update`.
3.  **Clicking a `@`/`+` pill in the task list:** sets `_filter` to that context/project.
4.  **Checkbox:** toggles completion immediately.
5.  **Search:** live substring filter combined with sidebar filter.
6.  **View menu:** hides/shows dates, priorities (badge + inline), tags (pills).
7.  **Sort menu:** reorders visible list; completed always last.
8.  **Save:** manual via toolbar/`Ctrl+S`; automatic `saveIfDirty()` (fire-and-forget) on widget `dispose` and on `hidden`/`paused`/`detached` lifecycle events.
9.  **Startup:** `main(args)` resolves `todo.txt` path from `args[0]`; shows error scaffold if missing/unloadable, spinner while loading.

## 4. Technical Data Flow

1.  **Load:** CLI path → `TaskRepository.load(path)` → `Task.fromText` per line → `TaskListPage`.
2.  **Derive:** `_contexts` / `_projects` / `_priorities` sets + per-filter counts computed from `repository.tasks` on each build.
3.  **Filter/sort/search:** `_visibleIndices` (filter → search → sort with completed-last) → `ListView`.
4.  **Mutate:** dialog/checkbox/toolbar → `repository.add/update/removeAt/toggleCompleted/undo` → `setState` refresh → explicit or auto `save()`.
