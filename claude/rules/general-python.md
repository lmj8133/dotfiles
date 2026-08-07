---
scope: General Python (CLI tools, data analysis, GUI apps; non-CV/ML)
trigger: Fallback for Python work — applies when no other Python rule matches (no torch/cv2/tensorflow imports). Pure numpy / pandas usage falls under this rule.
---

# General Python Rules

## Environment & Dependencies

<!-- UV_ONLY_START -->
* **Python toolchain: uv** (per global §5).
  * Run: `uv run python <script>.py`
  * Add deps: `uv add <pkg>`
  * One-off tools: `uvx <tool>`
<!-- UV_ONLY_END -->
* Pin runtime deps in `pyproject.toml`. Do not bump versions as a side effect of unrelated work.

## Linting & Formatting

* **Default lint stack: `ruff` (check + format) and `mypy`.** Matches what the `/review` skill enforces.
<!-- UV_ONLY_START -->
* Run via uvx without project-local install: `uvx ruff check .`, `uvx ruff format .`, `uvx mypy .`.
<!-- UV_ONLY_END -->
* When writing new code, write it **clean enough to pass ruff defaults** — don't rely on the user running format afterward.

## Type Hints

* Use type hints on **public functions and module-level APIs**. Internal helpers may skip them when the type is obvious.
* **Match the project's Python version.** Check `pyproject.toml` (`requires-python`) or the active interpreter before using version-sensitive syntax:
  * `list[int]` / `dict[str, X]` / `X | None` — only on **Python 3.10+**
  * Older projects: use `List[int]`, `Optional[X]` from `typing`
* When mypy reports an error, **prefer fixing the type** over silencing. Use `# type: ignore[<error-code>]` only when a third-party library is missing stubs, and add a short comment explaining the reason.

## CLI Tools

* For non-trivial CLIs, prefer **`argparse` from stdlib** unless the project already uses `click` / `typer`. Don't pull in a new framework for a single-command tool.
* Provide a `--help` message that includes one example invocation.
* Exit codes: `0` success, non-zero on failure. State exit code in usage notes when relevant.
* Read paths from arguments / config — **never hardcode** paths to a developer's local directory. Hardcoded paths break portability and prevent collaborators from running the project.

## Data Analysis

* Default stack: **`pandas`** for tabular work; `polars` is fine when explicitly requested or already in the project.
* For one-off analysis scripts, **plain functions over classes**. Don't build a `DataPipeline` class for a 50-line script.

## GUI Apps

* **Match the project's existing GUI toolkit** (PyQt / PySide / Tkinter / customtkinter / etc.) — do not introduce a new toolkit. Read existing imports first.
* Long-running work must not block the UI thread. Use the toolkit's native async / worker mechanism (Qt: `QThread` / `QtConcurrent`; Tkinter: `threading` + `after()`).
* Don't put business logic inside event handlers — extract to plain functions that the handler calls. This makes them testable later.

## Testability — pytest

* If the project **already has pytest** (`tests/` dir, `pytest` in deps, or `[tool.pytest]` in `pyproject.toml`): use it. Add new tests under `tests/`, run with `uv run pytest -q` or `pytest -q`.
* If the project has **no pytest setup**: do not introduce one on your own initiative. Pytest adoption is in progress and the user will signal when to start. If the user explicitly asks to add pytest, confirm the project structure (test layout, fixtures, conftest scope) before scaffolding.
* Either way: **separate logic from I/O / GUI / CLI parsing**. Pure functions are testable; functions that read files, click buttons, or parse `sys.argv` directly are not.

## Logging

* For scripts > ~50 lines or anything user-facing, prefer the stdlib **`logging`** module over `print`. `print` is fine for short one-shot scripts.
* Don't introduce `loguru` or other logging libraries unless the project already uses one.

## Pre-flight Checks (read project, don't ask)

Infer from the project before writing code — only ask if there's a genuine conflict:

* **GUI toolkit** — read existing imports; match what's there. Only ask if the project mixes toolkits with no clear convention
* **Python version** — check `pyproject.toml` `requires-python`; pick syntax that fits. No need to confirm
* **Tests** — if pytest is already set up and the change is non-trivial logic, add a test alongside. If pytest isn't set up, don't introduce it on your own
