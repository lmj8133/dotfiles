---
name: review
invocation: user
description: Systematic code review checklist before committing or PR
---

# Code Review Skill

Perform a systematic review of recent changes before commit or PR.

## Trigger

User invokes `/review`

## Severity Levels

Use these levels to categorize every finding:

| Level | Label | Meaning |
|-------|-------|---------|
| 🔴 | **BLOCKER** | Security issues, data loss risks, broken tests, crashes |
| 🟡 | **WARNING** | Missing error handling, unclear naming, poor patterns |
| 🟢 | **SUGGESTION** | Style improvements, docs, minor refactoring opportunities |

## Workflow

### Step 0: Detect Project Type

Check for marker files to determine the project language(s):

| Marker File | Language | Automated Tools |
|-------------|----------|-----------------|
| `pyproject.toml`, `setup.py`, `requirements.txt` | Python | `uvx ruff check .`, `uvx ruff format --check .`, `uvx mypy .`, `pytest -q` |
| `package.json` | Node/JS/TS | `npm run lint`, `npm test` |
| `go.mod` | Go | `go vet ./...`, `go test ./...` |
| `Cargo.toml` | Rust | `cargo clippy`, `cargo test` |
| `*.sh` (in changed files) | Shell | `shellcheck` |

If multiple markers exist, run checks for **all** detected languages.
For language-specific manual checklists, read `references/checklists.md`.

### Step 1: Identify Changed Files

```bash
git diff --name-only          # unstaged
git diff --cached --name-only # staged
```

### Step 2: Run Automated Checks

Run the tools identified in Step 0. If a tool is not installed or the
corresponding npm script doesn't exist, note it and move on.

### Step 3: Manual Checklist

For each changed file, verify:

- [ ] **Naming**: Clear names; focused functions/classes
- [ ] **Error handling**: Edge cases handled; helpful error messages
- [ ] **Tests**: Tests exist and easy to run
- [ ] **Security**: No secrets in code/logs; configs externalized
- [ ] **Docs**: README/usage notes updated if needed

For deeper language-specific checks, consult `references/checklists.md`.

### Step 4: Report

Output a structured summary using severity levels:

```
## Review Summary

### Project Type
- Python (detected via pyproject.toml)

### Files Changed (N)
- src/utils/parser.py (modified)
- src/utils/validator.py (new)
- tests/test_parser.py (modified)

### Automated Checks
- ruff: PASS (0 issues)
- pytest: PASS (12 tests)

### Findings

🔴 **BLOCKER**: API key hardcoded in config.py:23
   → Move to environment variable or .env (add to .gitignore)

🟡 **WARNING**: `validate_input()` missing error handling for empty string
   → Add guard clause or raise ValueError with context

🟢 **SUGGESTION**: Consider adding docstring to `parse_header()` function

### Checklist
- [x] Naming: Clear and descriptive
- [x] Error handling: ValidationError with context
- [x] Tests: Added 3 new test cases
- [ ] Docs: README needs update for new validator API
```

## Important

- **Review ALL changed files**, not just those mentioned in conversation
- **Run automated tools first** to catch obvious issues
- **Categorize every finding** with a severity level (🔴/🟡/🟢)
- **Be constructive**: focus on improvements, not criticism
- **Skip steps** if not applicable (e.g., no tests for doc-only changes)
