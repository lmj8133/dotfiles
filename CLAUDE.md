# Dotfiles Project - Local Instructions

> **Project Context**
> This repository contains **backup copies** of dotfiles and configuration files. When the user asks questions or requests changes, they are referring to the backup files **in this repository**, NOT the system's actual dotfiles.

## Important Notes

* **DO NOT modify system dotfiles directly** (e.g., `~/.bashrc`, `~/.zshrc`, etc.)
* **DO NOT read or modify files in `./claude/`** — this directory contains backup copies of Claude Code settings for bootstrap.sh; treat them as read-only snapshots
* All operations should target the backup files within this repository
* When the user asks about configurations, they mean the files stored here for version control and backup purposes
* If the user wants to apply changes to their actual system dotfiles, they will explicitly state that

## Python Toolchain Sentinel Convention

`bootstrap.sh` supports two Python modes (`uv` / `syspython`). Any content in `./claude/` that is **uv-specific** must be wrapped in sentinel comments so bootstrap can strip or preserve it correctly:

```
<!-- UV_ONLY_START -->
...content that only applies when uv is available...
<!-- UV_ONLY_END -->
```

If the same section needs a **syspython alternative** (e.g., different tool invocations), add a second block immediately after:

```
<!-- UV_FREE_START -->
...equivalent content for system Python...
<!-- UV_FREE_END -->
```

`bootstrap.sh` behaviour:
- **uv mode** — strips sentinel lines, keeps `UV_ONLY` content, removes `UV_FREE` blocks entirely
- **syspython mode** — removes `UV_ONLY` blocks entirely, strips sentinel lines from `UV_FREE` blocks

Files currently using sentinels: `claude/CLAUDE.md`, `claude/rules/general-python.md`, `claude/rules/cv-ai.md`, `claude/skills/review/SKILL.md`, `claude/skills/review/references/checklists.md`.

---

For general coding style, commit conventions, and interaction rules, refer to the global `~/.claude/CLAUDE.md`.
