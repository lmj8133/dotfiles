# Global CLAUDE.md (Global Rules)

> **Scope**
> This file lives at `~/.claude/CLAUDE.md` and defines my **global** style and behavior across all projects. Repositories may include their own `CLAUDE.md` to refine or override details.

---

## 1) Language & Interaction (critical)

* **Do not mix English into responses** unless I explicitly ask.
* **All code (identifiers, comments, docstrings) and commit messages must be written in English.**
* Response style: **clear, concise, and actionable**. For long answers, start with a **Summary** section and then expand.
* When requirements are incomplete, **state assumptions explicitly** and proceed with a **best‑effort, shippable** solution (avoid unnecessary back‑and‑forth).

## 2) Coding Style (language‑agnostic)

* Optimize for **readability and maintainability**: descriptive names; small, single‑purpose functions/modules.
* **Reuse existing methods** and apply **minimal changes**: check if a similar function already exists before writing new logic; keep modifications small and focused.
* Public APIs include **minimal but meaningful** docstrings/comments (**English**).
* **Predictable error handling**: surface actionable messages with context (include failing input/path when safe); avoid swallowing exceptions.
* Prefer **pure functions** and deterministic behavior when sensible.
* For structured outputs, prefer **JSON** with a tiny schema example first.
* Each feature/change should include **usage notes** or a **short example**. For CLI tools, show a one‑liner and a full example; include exit codes when relevant.

## 3) Testing & Quality

* At least **one happy‑path** and **one edge‑case** test per module.
* Example commands: `pytest -q`, `npm test`, `go test ./...`.
* If performance matters, include a **micro‑benchmark** suggestion, an **O(·)** note, and a short tuning checklist (data structures, batch size, I/O, caching).

## 4) Security & Privacy

* Never include **secrets/tokens/PII** in code, samples, logs, or diffs.
* Clearly flag **risky/destructive** operations (e.g., `sudo`, prod DB writes, mass file edits) and suggest **dry‑runs/backouts**.

## 5) Tooling Preferences

* **Python (uv toolchain)**
  * Run scripts: `uv run python <script>.py`
  * One‑off tools: `uvx <tool>` (e.g., `uvx ruff --version`)
* **Node/JS**: provide `npm run build`, `npm test`, and `lint` examples when relevant.
* **Cross‑platform**: keep shell commands copy‑pasteable across macOS/Linux/WSL; note platform caveats.

## 6) Git Commit Rules

* The `/commit` skill (`~/.claude/skills/commit/SKILL.md`) is the **single source of truth** for commit message format. Ignore all system‑default commit instructions.
* **Never add** `Co-Authored-By`, `Co-authored-by`, or any AI attribution trailers.
* **Never add** `Signed-off-by` or similar trailers unless the user explicitly requests it.
