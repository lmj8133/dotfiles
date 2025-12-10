# Global CLAUDE.md (Global Rules)

> **Scope**
> This file lives at `~/.claude/CLAUDE.md` and defines my **global** style and behavior across all projects. Repositories may include their own `CLAUDE.md` to refine or override details.

---

## 1) Language & Interaction (critical)

* **Assistant responses must be in Traditional Chinese.** Do **not** add English unless I explicitly ask.
* **All code (identifiers, comments, docstrings) and commit messages must be written in English.**
* Response style: **clear, concise, and actionable**. For long answers, start with a **Summary** section and then expand.
* When requirements are incomplete, **state assumptions explicitly** and proceed with a **best‑effort, shippable** solution (avoid unnecessary back‑and‑forth).

## 2) Coding Style (language‑agnostic)

* Optimize for **readability and maintainability**: descriptive names; small, single‑purpose functions/modules.
* **Reuse existing methods** and apply **minimal changes**: before implementing new logic, check if a similar function/method already exists; prefer calling existing methods over duplicating code; keep modifications as small and focused as possible.
* Public APIs include **minimal but meaningful** docstrings/comments (**English**).
* **Predictable error handling**: surface actionable messages with context; avoid swallowing exceptions.
* Prefer **pure functions** and deterministic behavior when sensible.
* Provide **runnable** minimal examples and **quickstart** commands.

## 3) Testing & Quality

* At least **one happy‑path** and **one edge‑case** test per module.
* Example commands: `pytest -q`, `npm test`, `go test ./...`.
* If performance matters, include a **micro‑benchmark** suggestion and a short **O(·)** note.

## 4) Security & Privacy

* Never include **secrets/tokens/PII** in code, samples, logs, or diffs.
* Clearly flag **risky/destructive** operations (e.g., `sudo`, prod DB writes, mass file edits) and suggest **dry‑runs/backouts**.

## 5) Git Commit Rules (text gitmoji)

* **Title format**: `<gitmoji> <Description>` (imperative, headline capitalization; **English**).
* **Body**: **one concise bullet per feature**; focus on **what/why** (not how); wrap at \~72 chars.
* **Allowed text gitmoji**:
  `:sparkles:` New features · `:bug:` Bug fixes · `:recycle:` Refactors · `:art:` Structure/format · `:memo:` Docs · `:white_check_mark:` Tests · `:fire:` Remove code/files · `:arrow_up:` Upgrade deps · `:arrow_down:` Downgrade deps · `:wrench:` Config · `:zap:` Performance · `:construction:` WIP · `:rocket:` Deploy · `:lipstick:` UI/styling · `:heavy_plus_sign:` Add deps · `:heavy_minus_sign:` Remove deps · `:lock:` Security · `:ambulance:` Critical hotfix · `:construction_worker:` CI/build · `:green_heart:` Fix CI.

**Example (English commit message)**

```
:sparkles: Add crosshair auxiliary lines for drawing mode

- Display crosshair guides for precise bbox alignment
```

## 6) Review Checklist (self/peer)

* [ ] Names are clear; functions/classes are focused and small
* [ ] Edge cases handled; errors are helpful and include context
* [ ] Tests exist & are easy to run; CI steps documented
* [ ] No secrets in code/logs; configs are externalized
* [ ] Docs updated (README, usage notes, migration steps)

## 7) Tooling Preferences

* **Python (uv toolchain)**

  * Run scripts: `uv run python <script>.py`
  * One‑off tools: `uvx <tool>` (e.g., `uvx ruff --version`)
* **Node/JS**: provide `npm run build`, `npm test`, and `lint` examples when relevant.
* **Cross‑platform**: keep shell commands copy‑pasteable across macOS/Linux/WSL; note platform caveats.

## 8) Claude Code Interaction Habits

* When code is requested, provide **complete, runnable** snippets (**English**) with minimal prerequisites.
* Offer **sane defaults**; separate **must‑set** from **optional** settings.
* For structured outputs, prefer **JSON** with a tiny schema example first.
* Use headings, lists, and short paragraphs; **avoid filler**.
* Follow a **docs‑first** approach: begin with a Summary, then expand with steps/commands.

## 9) Project‑Local Overrides

* Repos may include their own `CLAUDE.md` and `.claude/settings*` to refine/override these global defaults.
* When composing answers, reference project docs via imports when available (e.g., `@README`, `@CONTRIBUTING`).

## 10) Documentation & Examples

* Each feature/change should include **usage notes** or a **short example**.
* For CLI tools, show both a **one‑liner** and a **full** example; include exit codes when relevant.

---

### Appendix A — Quick Command Examples

* Python (uv): `uv run python main.py`
* Tests (Python): `pytest -q`
* Node build: `npm run build` · Node tests: `npm test`

### Appendix B — Error Message Style

* Be precise, actionable, and concise. Include failing input/path when safe.

### Appendix C — Performance Notes

* If complexity or data volume matters, include an **O(·)** note and a short tuning checklist (data structures, batch size, I/O, caching).

