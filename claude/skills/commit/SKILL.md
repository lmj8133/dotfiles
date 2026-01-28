---
name: commit
invocation: user
description: Create a comprehensive git commit with full diff analysis
---

# Git Commit Skill

Analyze ALL changes between current state and last commit, then create
a commit message that helps "future me" quickly recall what changed.

## Trigger

User invokes `/commit`

## Workflow

### Step 1: Gather Complete Diff

Run these commands to understand ALL changes (not just current task):

```bash
git status
git diff              # unstaged changes
git diff --cached     # staged changes
git log -3 --oneline  # recent commit style
```

### Step 2: Analyze Changes

For each modified file:
- What was the **previous state**?
- What is the **current state** after changes?
- **Why** was this change made? (reasoning/logic)

### Step 3: Draft Commit Message

**Title format:** `<gitmoji> <Description>`
- Imperative mood, headline capitalization, English
- Summarize the main purpose

**Body format:** One bullet per logical change
- Focus on **what changed** and **why this approach**
- Write for "future me" to quickly recall
- Group related changes; separate unrelated ones
- Wrap at ~72 chars

### Step 4: Execute Commit

```bash
git add <relevant-files>
git commit -m "$(cat <<'EOF'
<title>

- <bullet 1>
- <bullet 2>
EOF
)"
git status  # verify
```

## Gitmoji Reference

| Code | Usage |
|------|-------|
| `:sparkles:` | New feature |
| `:bug:` | Bug fix |
| `:recycle:` | Refactor |
| `:art:` | Structure/format |
| `:memo:` | Documentation |
| `:white_check_mark:` | Tests |
| `:fire:` | Remove code/files |
| `:arrow_up:` | Upgrade deps |
| `:arrow_down:` | Downgrade deps |
| `:wrench:` | Configuration |
| `:zap:` | Performance |
| `:construction:` | WIP |
| `:rocket:` | Deploy |
| `:lipstick:` | UI/styling |
| `:heavy_plus_sign:` | Add deps |
| `:heavy_minus_sign:` | Remove deps |
| `:lock:` | Security |
| `:ambulance:` | Critical hotfix |
| `:construction_worker:` | CI/build |
| `:green_heart:` | Fix CI |

## Example Output

```
:sparkles: Add JSON LSP support and improve completion UX

- Enable jsonls in nvim-lspconfig for JSON schema validation;
  provides autocomplete for package.json, tsconfig, etc.
- Change completion trigger from <C-Space> to <C-j> to avoid
  conflict with IME toggle on macOS/Windows
```

## Important

- **Analyze ALL diff**, not just files mentioned in current conversation
- **Never skip** `git diff` step
- **Commit message is for "future me"**: include enough context to recall
  what this version changed without re-reading the code
- **Never add** `Co-Authored-By`, `Co-authored-by`, or similar AI attribution
  trailers to commit messages
