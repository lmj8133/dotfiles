---
name: review
invocation: user
description: Systematic code review checklist before committing or PR
---

# Code Review Skill

Perform a systematic review of recent changes before commit or PR.

## Trigger

User invokes `/review`

## Workflow

### Step 1: Identify Changed Files

```bash
git diff --name-only          # unstaged
git diff --cached --name-only # staged
```

### Step 2: Run Automated Checks

Based on project type, run appropriate tools:

**Python:**
```bash
uvx ruff check .
uvx mypy .
pytest -q
```

**Node/JS:**
```bash
npm run lint
npm run typecheck  # if available
npm test
```

### Step 3: Manual Checklist

For each changed file, verify:

- [ ] **Naming**: Clear names; focused functions/classes
- [ ] **Error handling**: Edge cases handled; helpful error messages
- [ ] **Tests**: Tests exist and easy to run
- [ ] **Security**: No secrets in code/logs; configs externalized
- [ ] **Docs**: README/usage notes updated if needed

### Step 4: Report

Output a summary:
- Files reviewed
- Automated check results
- Manual checklist findings
- Suggestions for improvement

## Example Output

```
## Review Summary

### Files Changed (3)
- src/utils/parser.py (modified)
- src/utils/validator.py (new)
- tests/test_parser.py (modified)

### Automated Checks
- ruff: PASS (0 issues)
- mypy: PASS (0 errors)
- pytest: PASS (12 tests)

### Manual Checklist
- [x] Naming: Clear and descriptive
- [x] Error handling: ValidationError with context
- [x] Tests: Added 3 new test cases
- [ ] Docs: README needs update for new validator API

### Suggestions
1. Consider adding docstring to `validate_input()` function
2. README.md should document the new validator module
```

## Important

- **Review ALL changed files**, not just those mentioned in conversation
- **Run automated tools first** to catch obvious issues
- **Be constructive**: focus on improvements, not criticism
- **Skip steps** if not applicable (e.g., no tests for doc-only changes)
