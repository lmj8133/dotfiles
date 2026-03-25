---
name: merge
description: Safe merge workflow using --no-commit --no-ff. Resolves conflicts before
  committing.
invocation: user
---

# Git Merge Skill

Safely merge a source branch into a target branch with automatic conflict resolution,
review, and guided commit workflow.

## Trigger

User invokes `/merge [source-branch] [target-branch]`

- `source-branch`: required (the branch to merge in)
- `target-branch`: optional, defaults to the repo's main branch (auto-detected)

### Examples
- `/merge feature/nosudo-bootstrap` — merges into the main branch (master or main)
- `/merge feature/nosudo-bootstrap develop` — merges into develop

## Workflow

### Step 0: Preconditions

Before starting, verify the repo is in a safe state:

1. Run `git status` to check for changes
   - **Dirty working tree** → ask user to commit/stash changes first and **stop**
   - **Unmerged paths / rebase in progress** → warn user about the state and **stop**

2. Verify source and target branches exist:
   - `git branch --list <source-branch>`
   - `git branch --list <target-branch>` (or verify master/main exists)
   - If either is missing → inform user and **stop**

### Step 1: Parse Arguments

Extract `source` and `target` from user's invocation:

1. `source` = first argument, or ask user if missing
2. `target` = second argument, or auto-detect the repo's main branch:
   ```bash
   git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@'
   ```
   If that fails, check which of `master` / `main` exists locally.

```
/merge feature/nosudo-bootstrap       → source=feature/nosudo-bootstrap, target=(auto-detected)
/merge feature/nosudo-bootstrap develop  → source=feature/nosudo-bootstrap, target=develop
```

### Step 2: Switch to Target Branch

```bash
git checkout <target>
```

Verify checkout succeeded. If target branch doesn't exist locally, consider creating it
if it exists on origin, or ask user to confirm.

### Step 3: Merge with --no-commit --no-ff

```bash
git merge --no-commit --no-ff <source>
```

This stages the merge without creating a commit, allowing review and conflict resolution
before committing.

Then run:
```bash
git status
```

Examine output:
- **No conflicts** → proceed to Step 5 (review)
- **Conflicts exist** → proceed to Step 4 (conflict resolution)

### Step 4: Conflict Resolution (if needed)

If conflicts were detected in Step 3:

1. List all conflicting files from `git status` output
2. For each conflicting file:
   - Use the **Read** tool to view the file
   - Identify conflict markers (`<<<<<<<`, `=======`, `>>>>>>>`)
   - Use the **Edit** tool to resolve (pick side, merge manually, delete markers)
   - Verify no conflict markers remain
3. Stage resolved files:
   ```bash
   git add <file1> <file2> ...
   ```
4. Repeat `git status` until no conflicts remain

If conflicts cannot be resolved, run:
```bash
git merge --abort
```
Then inform user and **stop**.

### Step 5: Review Staged Changes

Display what will be committed:

```bash
git diff --cached --stat
```

Output a brief summary showing:
- Number of files changed
- Total additions/deletions
- Key changes being merged

Example:
```
3 files changed, 45 insertions(+), 12 deletions(-)
- bootstrap.sh: Enhanced package installation with no-sudo fallback
- install.sh: Updated path handling
```

### Step 6: Ask User Confirmation

Before committing, present the merge commit message for approval:

**Message format:**
```
:twisted_rightwards_arrows: Merge <source> into <target>

- <bullet summary of key changes from the diff>
- <additional bullets if multiple logical groups>
```

**Example:**
```
:twisted_rightwards_arrows: Merge feature/nosudo-bootstrap into master

- Add no-sudo fallback for package installation in bootstrap workflow
- Enhance error handling for installation failures
```

Output this message and ask:
> **Ready to commit this merge?** Review the changes above (git diff --cached --stat).
> Confirm to proceed, or abort to review further.

Wait for user confirmation before proceeding.

### Step 7: Commit

Once user confirms:

```bash
git commit -m "$(cat <<'EOF'
:twisted_rightwards_arrows: Merge <source> into <target>

- <bullet 1>
- <bullet 2>
EOF
)"
```

Then display the result:
```bash
git log --oneline -3
```

Confirm merge is complete and show the new commit.

## Important Rules

- **NEVER skip Step 6** — always ask user before committing merge
- **NEVER use `git merge` without `--no-commit --no-ff`** — this ensures staged review
- **NEVER force** (`-f` flag) unless explicitly requested by user
- **If anything fails** (branch doesn't exist, conflicts unresolvable), **abort and report**
  the issue clearly
- **Never add** `Co-Authored-By`, `Co-authored-by`, or similar AI attribution trailers
  to merge commit messages

## Anti-patterns

- ❌ Do NOT merge directly without user confirmation
- ❌ Do NOT skip conflict resolution and commit with unresolved conflicts
- ❌ Do NOT use generic merge messages — include key changes in bullets
- ❌ Do NOT hardcode master/main — always auto-detect the repo's default branch

## Gitmoji for Merges

| Emoji | Code | When to use |
|-------|------|------------|
| 🔀 | `:twisted_rightwards_arrows:` | Feature branch merges |
| 🔁 | `:repeat:` | Sync or rebase operations |

Use `:twisted_rightwards_arrows:` for standard merges.

## Example Execution

```
User: /merge feature/nosudo-bootstrap

Step 0: ✓ Preconditions — working tree clean, branches exist
Step 1: ✓ Parse — source=feature/nosudo-bootstrap, target=master (auto-detected)
Step 2: ✓ Switch — git checkout master
Step 3: ✓ Merge — git merge --no-commit --no-ff feature/nosudo-bootstrap
         → 1 conflict in bootstrap.sh (auto-merge failed)
Step 4: ✓ Resolve — Edit bootstrap.sh, resolve conflict, git add
Step 5: ✓ Review — 2 files changed, 30 insertions(+), 5 deletions(-)
Step 6:   Ask — "Ready to commit?" with proposed merge message
          User confirms
Step 7: ✓ Commit — :twisted_rightwards_arrows: Merge feature/nosudo-bootstrap into master
        ✓ Log — [new commit hash] shown via git log --oneline -3
```
