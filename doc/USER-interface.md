This document provides a functional and technical specification for implementing a **Todo.txt Client UI**. The goal is to create a desktop-style application that parses, displays, and interacts with a plain-text `todo.txt` file based on the provided specification.

---

# UI Implementation Specification: Todo.txt Client

## 1. Visual Design Philosophy
*   **Style:** Clean, high-density, "Utility-first" interface (similar to classic productivity tools like Evernote or old-school Windows Mail).
*   **Typography:** Use a highly legible Sans-Serif font (e.g., Segoe UI, Roboto) for the task list.
*   **Color Palette:** Neutral backgrounds (light gray/white) with color-coded accents for Priorities (e.g., Red for A, Orange for B) and Contexts/Projects.

## 2. Layout Structure
The interface is divided into four primary functional areas:

### A. Global Menu Bar (Top)
Standard desktop menu containing:
*   `File`: Open/Save/Export.
*   `Actions`: Batch complete, batch delete, move tasks.
*   `View`: Toggle visibility of metadata (dates, priorities, tags).
*   `Sorting`: Sort by Priority, Sort by Date, Sort by Project.
*   `Help`: Documentation.

### B. Toolbar (Below Menu)
A horizontal row of icon-based buttons for rapid actions:
*   **Search (Magnifying Glass):** Focus search bar.
*   **New Task (Plus Icon):** Add a blank line at the top.
*   **Edit (Pencil):** Edit selected task.
*   **Delete (Trash Can):** Remove selected task.
*   **Complete (Checkmark):** Mark selected task with `x [date]`.
*   **Undo (Left Arrow):** Revert last action.
*   **File Management Icons:** Save, Print, Open, etc.

### C. Sidebar / Filter Panel (Left)
A hierarchical navigation tree that allows users to filter the main list.
*   **Top Level Filters:**
    *   `All` (Shows everything)
    *   `Uncategorized` (Tasks without `+` or `@`)
    *   `Due` (Tasks with `due:YYYY-MM-DD`)
*   **Contexts (`@`):** A list of all unique `@tags` found in the file. Clicking one filters the list to only show those tasks.
*   **Projects (`+`):** A list of all unique `+tags`.
*   **Priorities (`(A)`, `(B)`, etc.):** A list of available priority levels.
*   **Status:** A "Complete" folder to view finished tasks (tasks starting with `x`).

### D. Main Task List (Center/Right)
The primary viewing area. Each line represents one task.

#### Task Line Rendering Logic:
The parser must split the raw text string into visual components. Do **not** just show raw text; use "Syntax Highlighting" for the following:

1.  **Priority:** Render as `(A)` in a bold, distinct color (e.g., Red for A, Blue for B).
2.  **Creation Date:** Render in a muted gray color (e.g., `2023-01-01`).
3.  **Task Description:** The "Core" text. Render in standard black/dark gray.
4.  **Projects (`+`):** Render with a blue or green tint (e.g., `+Work`).
5.  **Contexts (`@`):** Render with a purple or teal tint (e.g., `@office`).
6.  **Metadata (`key:value`):** Render in a subtle, italicized, or small font (e.g., *due:2023-05-01*).
7.  **Completed Tasks:** If the line starts with `x`, the entire line should have a strikethrough effect and a lighter opacity (e.g., 50% gray).

---

## 3. Interaction Logic & Parsing Rules

### Parsing Engine Requirements
The developer must implement a regex-based parser that follows these strict rules:
*   **Priority Rule:** Must check for `^[A-Z] ` inside parentheses at the very start of the line.
*   **Completion Rule:** If a line starts with `x `, it is "Completed." The next date is the `Completion Date`. Any subsequent date is the `Creation Date`.
*   **Tag Rule:** `+` and `@` must be preceded by a space and followed by non-whitespace characters. They can appear anywhere after the priority/date prefix.
*   **Metadata Rule:** Any `string:string` pattern must be extracted as metadata.

### User Interactions
1.  **Single Click:** Selects the task.
2.  **Double Click:** Opens an inline text editor to modify the raw string.
3.  **Clicking a Tag in the Task List:** Should automatically update the Sidebar Filter to that specific Project or Context.
4.  **Checkbox Toggle (Optional):** Clicking a virtual checkbox at the start of an incomplete task should automatically prepend `x [today's date] ` to the line in the text file.

## 4. Technical Data Flow
1.  **Load:** Read `.txt` file $\rightarrow$ Parse lines into `Task` objects $\rightarrow$ Populate Sidebar $\rightarrow$ Render List.
2.  **Filter:** User clicks `@home` $\rightarrow$ UI filters `Task` objects where `context.contains("@home")` $\rightarrow$ Re-renders List.
3.  **Save:** Modify `Task` object $\rightarrow$ Serialize `Task` back to string format $\rightarrow$ Overwrite `.txt` file.