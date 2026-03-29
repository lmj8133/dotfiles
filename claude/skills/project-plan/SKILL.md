---
name: project-plan
invocation: user
description: "Generate structured implementation plans that Claude Code can execute step-by-step into ./docs/"
---

# Project Plan Skill

Generate structured, executable implementation plans written into `./docs/`.
Each phase file is a self-contained instruction set — Claude Code reads one
phase at a time and implements it without needing the full plan in context.

## Trigger

User invokes `/project-plan` or asks to write a project plan / implementation
plan.

---

## Step 0: Precondition Check

1. **Check `./docs/` state**:
   - Contains `.md` files → read and present a **short summary** to the user.
     Ask: **Modify existing plan** or **Backup and rewrite** (move to
     `docs.bak-YYYYMMDD/`). If backing up, add `Do not read docs.bak-*/`
     to the Master Plan's Key Constraints so this rule persists into
     implementation
   - Empty or missing → proceed

2. **Note context file availability** (`CLAUDE.md`, `README.md`) for Step 1.
   Warn if neither exists.

---

## Step 1: Understand the Project and Requirements

### 1a. Read project context

- Read `CLAUDE.md` and `README.md` if they exist
- Scan directory structure with **Glob** (e.g., `**/*`)
- Identify: technology stack, existing code patterns, key modules

### 1b. Ask focused questions

Identify **information gaps** that cannot be inferred from the codebase and
ask the user **only about those gaps**. Do NOT ask what is already in the code.

### 1c. Gate check

**Do NOT proceed** until you understand what the user wants to build and which
areas of the codebase will be affected.

---

## Step 2: Research, Propose, and Decide

### 2a. Determine scope

- **User already specified approach** → confirm understanding, record, skip
  to Step 3
- **Refactor / bug fix with clear strategy** → skip research, propose based
  on codebase knowledge
- **New technology / unfamiliar domain / library choice** → full research

### 2b. Search for prior art (when needed)

Use **WebSearch** to find existing projects, libraries, patterns, pitfalls,
and best practices.

### 2c. Propose approaches

- If user specified approach → present understanding for confirmation
- Otherwise → 2-3 approaches, each with: name, how it works (2-3 sentences),
  pros/cons, references (if any)

### 2d. Discuss and record decision

Discuss until the user confirms. Then output the decision and carry it into
the Master Plan's **Technical Decisions** table in Step 4:

```
Decision: <chosen approach>
Rationale: <why this over alternatives>
Trade-offs accepted: <what we gave up>
```

---

## Step 3: Plan Phases

### 3a. Identify impact scope

Determine which files will be **created / modified / deleted**, which existing
functions/modules are affected, and what dependencies change.

### 3b. Divide into phases

Each phase = a **logical unit of work** that can be implemented and verified
independently. Keep each phase under ~10 files. Each phase includes its own
regression tests; only create a dedicated "Testing" phase when test
infrastructure itself must be set up (framework install, CI config, shared
fixtures).

### 3c. Confirm with user

Present proposed phase list (names, order, dependencies). After confirmation:
`mkdir -p docs`

**File naming:** `00-master-plan.md` (always first), then `01-<slug>.md`,
`02-<slug>.md`, etc.

---

## Step 4: Write Master Plan and Phases

**Output limit awareness:** 3 phases or fewer → write all at once, ask once.
More than 3 phases → write in batches of 2-3, confirm per batch.

After writing, present summary with file names, line counts, step counts, and
regression test counts. Include the full regression command.

### Master Plan Template (`docs/00-master-plan.md`)

````markdown
# <Project Name> — Implementation Plan

## Scope
<!-- 2-3 sentences: what is being built/changed and why -->

## Prerequisites
<!-- Existing files, tools, dependencies, environment state required -->

## File Impact

| Action | File | Purpose |
|--------|------|---------|
| CREATE | src/auth/handler.ts | New auth middleware |
| MODIFY | src/app.ts | Register auth routes |

## Phase Order

1. [01-setup.md](./01-setup.md) — scaffolding and deps
2. [02-core-logic.md](./02-core-logic.md) — business logic (depends on 01)
3. [03-integration.md](./03-integration.md) — wire up and test (depends on 02)

## Technical Decisions

| Decision | Chosen Approach | Rationale | Alternatives Considered |
|----------|----------------|-----------|------------------------|
| Auth library | jsonwebtoken | Lightweight, maintained | passport.js, custom impl |

## Key Constraints
<!-- Numbered list, kept brief -->

## Full Regression Command
`npm test`

## How to Implement
1. Read this master plan for overall scope and constraints
2. Implement phases in order — read one phase file at a time
3. Before each phase: run Pre-flight command (skipped for first phase)
4. After each phase: run Phase Verification, then Regression Tests
5. After all phases: run Full Regression Command above
````

### Phase Template (`docs/NN-<slug>.md`)

**Step detail guidance** — when writing each step:
- **NEW files:** describe key exports, function signatures, core logic, error
  handling
- **MODIFIED files:** specify which function to change, what to add/remove,
  how it connects to existing code
- Reference existing functions by name, not line numbers

````markdown
# Phase NN: <Title>

> Depends on: none (first phase)
> Produces: src/auth/handler.ts (new), src/auth/types.ts (new)

## Pre-flight
Run all prior regression tests before starting:
`npm test`
If any test fails, fix before proceeding.

## Steps

### 1. Install dependencies
**File:** `package.json` (MODIFY)

Add `jsonwebtoken` and `@types/jsonwebtoken` to dependencies.
Run: `npm install jsonwebtoken @types/jsonwebtoken`

### 2. Create auth types
**File:** `src/auth/types.ts` (CREATE)

Define `TokenPayload` interface with fields: `userId: string`, `role: Role`,
`exp: number`. Export `Role` enum: `ADMIN`, `USER`, `READONLY`.

### 3. Create auth handler
**File:** `src/auth/handler.ts` (CREATE)

Export `validateToken(token: string): TokenPayload` — decode JWT, validate
expiry, return payload. Throw `AuthError` with descriptive message on failure.

Export `requireRole(...roles: Role[]): Middleware` — middleware factory that
checks `req.user.role` against allowed roles.

## Phase Verification
- [ ] `npx tsc --noEmit` — no type errors
- [ ] New files exist: `src/auth/handler.ts`, `src/auth/types.ts`

## Regression Tests
**File:** `tests/auth/handler.test.ts` (CREATE)

```typescript
describe('validateToken', () => {
  it('returns payload for valid token', () => {
    const token = createTestToken({ userId: '1', role: Role.USER });
    expect(validateToken(token).userId).toBe('1');
  });

  it('throws AuthError for expired token', () => {
    const token = createTestToken({ userId: '1', exp: pastTimestamp() });
    expect(() => validateToken(token)).toThrow(AuthError);
  });
});
```

**Run this phase:** `npm test -- --grep "auth"`
**Run all:** `npm test`
````

---

## Rules

1. **Document language** follows the project's CLAUDE.md language setting;
   code, file paths, and commands are always in English
2. **Never overwrite** existing files in `./docs/` — ask user first (Step 0)
3. **Use relative links** between documents within `./docs/`
4. **Verify file paths exist** before referencing them as existing source code
5. **Keep each phase under ~300 lines** and ~10 files — split if larger
6. **Every step must be concrete** — file path + what to do; no vague
   instructions like "implement the feature"
7. **Every phase must include regression tests** — concrete test cases with
   file path and test code that remain passing after all subsequent phases;
   skip only for phases with no testable logic (e.g., pure scaffolding)
8. **Run prior regression tests** before starting each phase — never build on
   a broken base
9. **Each phase must be self-contained** — do not assume Claude Code remembers
   context from other phases
10. **No line number references** — they go stale; use function/class names
11. **No narrative filler** — only include background/rationale if it directly
    informs a step
