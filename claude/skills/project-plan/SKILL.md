---
name: project-plan
invocation: user
description: "Generate structured multi-chapter project plans with layered documentation into ./docs/"
---

# Project Plan Skill

Generate structured, multi-chapter project plans written into `./docs/`.
Each chapter is written and confirmed incrementally to manage context window
limits. The layered documentation pattern (navigation guide, execution plans,
reference files) ensures plans stay navigable as they grow.

## Trigger

User invokes `/project-plan` or asks to write a project plan / planning
document.

---

## Step 1: Analyze Project Context

Before proposing any chapters, gather context:

- Read `CLAUDE.md` and `README.md` using the **Read** tool
- Scan the directory structure using the **Glob** tool (e.g., `**/*`)
- Check for existing files in `docs/` using the **Glob** tool

Identify:
- Technology stack and languages in use
- Project purpose and scope
- User's stated goal (from command arguments or conversation)
- Existing documentation that should not be overwritten

If project context is insufficient (no README, unclear tech stack, or vague
goal), **ask the user** to clarify before proceeding. Do not guess the project
type or scope.

---

## Step 2: Decide Chapters and File Layout

### File Naming Convention

- Two-digit prefix for sort order: `NN-<slug>.md`
- Master plan is always `00-master-plan.md` (written first)
- Navigation guide is always `NAVIGATION.md` (written last, only when >= 3 files)

### Default Chapter Catalog

Present this table to the user. Let them pick which chapters to include.

| Chapter Type         | Filename                   | When to Include                  |
|----------------------|----------------------------|----------------------------------|
| Master Plan          | `00-master-plan.md`        | Always (written first)           |
| Current-State Analysis | `01-analysis.md`         | Migration, refactor, porting     |
| Architecture Design  | `02-architecture.md`       | New build or system redesign     |
| Phased Execution     | `03-phase-N-<slug>.md`     | Sequential implementation phases |
| Challenges & Solutions | `04-challenges.md`       | Known technical risks            |
| Timeline & Milestones | `05-timeline.md`          | Time estimates needed            |
| Testing Strategy     | `06-testing.md`            | Non-trivial QA scope             |
| Risk Assessment      | `07-risks.md`              | Risk communication needed        |
| Appendix / Reference | `08-appendix.md`           | Lookup tables or references      |
| Navigation Guide     | `NAVIGATION.md`            | >= 3 files (written last)        |

### Project Type Quick-Pick

| Project Type           | Suggested Chapters                                    |
|------------------------|-------------------------------------------------------|
| New feature / project  | Architecture, Phased Execution, Timeline, Testing     |
| Migration / porting    | Analysis, Architecture, Challenges, Phases, Timeline, Risks |
| Refactor               | Analysis, Architecture, Phased Execution, Testing     |
| Bug investigation      | Analysis, Challenges, Testing                         |
| Infrastructure / DevOps | Architecture, Phased Execution, Risks, Appendix      |

After the user confirms chapter selection, create the `docs/` directory:

```bash
mkdir -p docs
```

---

## Step 3: Write Master Plan (`docs/00-master-plan.md`)

Use this template:

```markdown
# <Project Name> — Master Plan

## Project Overview
<!-- One paragraph: what this project is and why it exists -->

## Goals and Success Criteria
<!-- Bulleted list of measurable outcomes -->

## Chapter Overview

| #  | Title            | File                                      | Purpose          | Status  |
|----|------------------|-------------------------------------------|------------------|---------|
| 00 | Master Plan      | [00-master-plan.md](./00-master-plan.md)  | ...              | Draft   |
| 01 | ...              | [01-analysis.md](./01-analysis.md)        | ...              | Pending |

## Key Decisions and Constraints
<!-- Numbered list of architectural / scope decisions -->

## Quick Lookup

| I need to...                  | Go to                                      |
|-------------------------------|--------------------------------------------|
| Understand the current state  | [01-analysis.md](./01-analysis.md)         |
| See the architecture          | [02-architecture.md](./02-architecture.md) |

## Conventions and Terminology
<!-- Define project-specific terms and abbreviations -->
```

After writing, ask the user:
1. Show a short summary (3-5 bullets)
2. Report file path and approximate line count
3. Ask: **Continue to next chapter? / Revise this chapter? / Stop here?**

---

## Step 4: Write Each Chapter

Every chapter follows this unified template:

```markdown
# <Chapter Title>

## Navigation
### Prerequisites (must-read files)
- [00-master-plan.md](./00-master-plan.md) — project overview

### Related Files (source code references with line numbers)
- `src/example.ts:42` — relevant function

## Objectives
- **Estimated effort:** <time estimate>
- **Priority:** <High / Medium / Low>
- <Objective bullets>

## <Main Content Sections>
<!-- Chapter-specific content goes here -->

## Completion Checklist

- [ ] <Task 1> — verify with `<command>`
- [ ] <Task 2> — verify with `<command>`

## Related Links
- [Master Plan](./00-master-plan.md)
- [Previous: NN-prev.md](./NN-prev.md)
- [Next: NN-next.md](./NN-next.md)
```

### Key Requirements

1. **Navigation at the top** — prerequisites, related source files, next steps
2. **Source references use actual file paths + line numbers** — verify paths
   exist before referencing them
3. **Completion checklist includes concrete verification commands**
4. **Related links use relative paths** between docs

---

## Step 5: Confirm Between Chapters

After writing each chapter:

1. Display a short summary (3-5 bullet points)
2. Report the file path and approximate line count
3. Ask the user:
   - **Continue to next chapter?**
   - **Revise this chapter?**
   - **Stop here?**

Do NOT proceed to the next chapter without user confirmation.

---

## Step 6: Build Navigation Guide (Last)

Once all chapters are complete and the plan has >= 3 files, create
`docs/NAVIGATION.md`:

```markdown
# Navigation Guide

## Quick Start Scenarios

| I want to...                | Start here                                 |
|-----------------------------|--------------------------------------------|
| Get the big picture         | [00-master-plan.md](./00-master-plan.md)   |
| Understand current state    | [01-analysis.md](./01-analysis.md)         |

## Lookup: Need → File

| Need                        | File                                       |
|-----------------------------|--------------------------------------------|
| ...                         | ...                                        |

## Complete File List

| File                        | Purpose             | Lines |
|-----------------------------|---------------------|-------|
| `00-master-plan.md`         | ...                 | ~NNN  |

## FAQ
<!-- Common questions about this plan -->
```

After creating the navigation guide, update `00-master-plan.md`:
- Set all chapter statuses to **Complete**
- Add a link to `NAVIGATION.md` in the Quick Lookup table

---

## Important Rules

1. **Document language follows the project's CLAUDE.md language setting**
2. **Code, paths, and commands are always in English**
3. **Never overwrite existing files in `./docs/`** — ask the user first
4. **Create `./docs/` with `mkdir -p docs` when needed**
5. **Use relative links between documents**
6. **Verify file paths exist before referencing them in documents**
7. **Keep each chapter under ~300 lines**
