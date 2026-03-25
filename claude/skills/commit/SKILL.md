---
name: commit
invocation: user
description: Suggest a commit message based on full diff analysis
---

# Git Commit Skill

Analyze ALL changes between current state and last commit, then **suggest**
a commit message. Do NOT commit — wait for the user's next instruction.

## Trigger

User invokes `/commit`

## Workflow

### Step 0: Precondition Check

Before anything, verify the repo state:

1. Run `git status` to check for changes.
   - **Clean working tree** → inform user "No changes to commit" and **stop**.
   - **Unmerged paths / rebase in progress** → warn user about the current state
     (e.g., "You are in the middle of a rebase — resolve conflicts first") and **stop**.
2. Scan changed files for **sensitive patterns**:
   - `.env`, `.env.*`, `credentials.*`, `*secret*`, `*.pem`, `*.key`, `id_rsa*`
   - If any match → emit a ⚠️ warning listing the files and ask user to confirm
     before proceeding.
3. If diff is very large (>500 added/removed lines across all files):
   - Suggest splitting into smaller, focused commits.
   - Still proceed with analysis if the user wants a single commit.

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

### Step 4: Present Suggestion

Output the suggested commit message in a fenced code block:

```
<gitmoji> <Title>

- <bullet 1>
- <bullet 2>
```

Then list the files that would be included (from `git status`).
Do **not** run `git add`, `git commit`, or any other write command.
Stop and wait for the user's next instruction.

## Anti-patterns

Avoid these common mistakes:

- ❌ Do NOT combine unrelated changes into one commit — suggest splitting
- ❌ Do NOT use generic messages like "update", "fix", "changes"
- ❌ Do NOT include generated files (`*.pyc`, `node_modules/`, `dist/`, `.DS_Store`)
- ❌ Do NOT write a body that just restates the title
- ❌ Do NOT reference issue numbers unless they appear in the diff or conversation

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

- **Do NOT auto-commit**: only output the suggested message and wait
- **Analyze ALL diff**, not just files mentioned in current conversation
- **Never skip** `git diff` step
- **Commit message is for "future me"**: include enough context to recall
  what this version changed without re-reading the code
- **Never add** `Co-Authored-By`, `Co-authored-by`, or similar AI attribution
  trailers to commit messages
