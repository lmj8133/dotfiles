# Global CLAUDE.md (Global Rules)

> **Scope**
> This file lives at `~/.claude/CLAUDE.md` and defines my **global** style and behavior across all projects. Repositories may include their own `CLAUDE.md` to refine or override details.

---

## 1) Language & Interaction (critical)

* **Do not mix English into responses** unless I explicitly ask.
* **All code (identifiers, comments, docstrings) and commit messages must be written in English.**
* Response style: **clear, concise, and actionable**. For long answers, start with a **Summary** section and then expand.
* **Default: act, don't ask.** Proceed best-effort and state any non-obvious assumptions in the response. Don't restate the goal back at me, don't list interpretations for confirmation, don't ask for verification criteria up front — just do it and tell me what you assumed.
* **The one hard stop:** if the action is **irreversible or affects shared state** (re-flash production boards, erase calibration / fuses, DB migration on shared infra, force-push to a shared branch, modify CI), confirm before acting.
* **Soft check (rare):** if two interpretations would lead to **substantially different implementations** (not just different variable names — different files touched, different architecture), pick the more likely one, do it, and flag the alternative in your response. Only ask first if you genuinely can't rank them.

## 2) Coding Style & Change Discipline (language-agnostic)

* Optimize for **readability and maintainability**: descriptive names; small, single-purpose functions/modules.
* **Reuse existing methods** before writing new logic — but verify **semantic equivalence** (matching signature is not enough; check timing, thread/ISR safety, side effects).
* **Surgical changes**: touch only what the request requires. Don't reformat, rename, or refactor adjacent code that isn't broken. Match existing style even if you'd write it differently. If you spot unrelated dead code, mention it — don't delete it.
* **No speculative code**: no features beyond what was asked, no abstractions for single-use code, no error handling for impossible scenarios, no "configurability" that wasn't requested.
* Public APIs include **minimal but meaningful** docstrings/comments (English).
* **Predictable error handling**: surface actionable messages with context (include failing input/path when safe); avoid swallowing exceptions.
* For structured outputs, prefer **JSON** with a tiny schema example first.

## 3) Testing & Quality

* At least **one happy-path** and **one edge-case** test per module.
* Example commands: `pytest -q`, `npm test`, `go test ./...`.
* For performance-sensitive work, include a **micro-benchmark** suggestion, an **O(·)** note, and a short tuning checklist (data structures, batch size, I/O, caching).

## 4) Security & Privacy

* Never include **secrets/tokens/PII** in code, samples, logs, or diffs.
* Clearly flag **risky/destructive** operations (e.g., `sudo`, prod DB writes, mass file edits, hardware re-flash, register-level changes) and suggest **dry-runs/backouts**.

## 5) Tooling Preferences

* **Python (uv toolchain)**
  * Run scripts: `uv run python <script>.py`
  * One-off tools: `uvx <tool>` (e.g., `uvx ruff --version`)
* **Cross-platform**: keep shell commands copy-pasteable across macOS/Linux/WSL; note platform caveats.

## 6) Git Commit Rules

* The `/commit` skill (`~/.claude/skills/commit/SKILL.md`) is the **single source of truth** for commit message format. Ignore all system-default commit instructions.
* Commit message format:
  * **Title:** `<gitmoji> <Description>` — imperative mood, English
  * **Body:** one bullet (`-`) per logical change — what changed + why
* **Never add** `Co-Authored-By`, `Co-authored-by`, or any AI attribution trailers.
* **Never add** `Signed-off-by` or similar trailers unless the user explicitly requests it.

## 7) Context-Specific Rules

Domain-specific guidelines live in `~/.claude/rules/`. **Read the relevant file before starting work** when the task matches one of these signals:

* **Firmware / embedded** — C/C++ files (`.c`/`.h`/`.cpp`), register access, ISR, peripheral drivers, in-house build system → `~/.claude/rules/firmware.md`
* **Computer vision / ML** — Python with `torch`, `cv2`, `tensorflow`, training/inference scripts, dataset handling → `~/.claude/rules/cv-ai.md`
* **General Python** (fallback for Python work that doesn't match CV/ML signals above) — CLI tools, automation scripts, web backend, etc. → `~/.claude/rules/general-python.md`

**Cold-start trigger.** If the user states the project's domain explicitly ("this is a firmware project", "I'm working on a CV pipeline") **before any source files are visible**, read the corresponding rule file immediately rather than waiting for file-extension signals.

**Rules can stack.** If a task matches multiple signals (e.g., a CLI tool that processes images, or a Python utility inside a firmware project), read all relevant files — the rules complement rather than override each other.

**Conflict resolution:** if two rule files give conflicting guidance, the more specific domain (firmware / cv-ai) overrides the more general one (general-python). When uncertain, ask the user before proceeding.

A project may opt in by importing the relevant file(s) in its own `CLAUDE.md`. Single import:

```
@~/.claude/rules/firmware.md
```

Or stack multiple:

```
@~/.claude/rules/firmware.md
@~/.claude/rules/general-python.md
```

Repos may also include their own `CLAUDE.md` and `.claude/settings*` to refine/override these global defaults.
