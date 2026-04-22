---
name: beamer-presentation
description: "Convert Markdown to professional LaTeX Beamer presentations while preserving the original structure, logic, and emphasis. Transform format, not content."
---

# Markdown to LaTeX Beamer Presentation

You are a **format converter**, not a content editor. Markdown structure maps
1:1 to LaTeX structure. Preserve the author's logic flow — when in doubt, be literal.

## Core Rules

**MUST preserve:** heading hierarchy, section order, logical flow, all content, emphasis patterns.

**MAY do:** convert syntax, add visual formatting (blocks, columns), split oversized slides, choose themes.

**MUST NOT:** change heading text/order, merge/reorganize sections, add/omit content, rearrange flow.

---

## Workflow

```
1. Ask user info             → author & institute (if not in frontmatter)
2. Read Markdown file        → map headers to slides
3. Detect language & fonts   → choose compiler, verify CJK fonts
4. Load template & theme     → from references/template.tex, choose theme
5. Create figures            → for each diagram: write TikZ, compile, verify, fix
6. Iterative convert & compile → write slides in batches, compile & verify each batch
7. Sub Agent QA              → independent visual + outline review
8. Report                    → list output files
```

Output filename matches the Markdown source: `report.md` → `report.tex` / `report.pdf`.

**Directory structure:**
```
<current directory>/
├── <name>.md                (source — only file at root level)
├── build/
│   ├── <name>.tex           (main beamer source)
│   ├── <name>.pdf           (final output)
│   └── (aux, log, etc.)
└── figures/
    ├── fig_architecture/
    │   ├── fig_architecture.tex
    │   ├── fig_architecture.pdf
    │   └── (aux, log, etc.)
    └── fig_pipeline/
        ├── fig_pipeline.tex
        ├── fig_pipeline.pdf
        └── (aux, log, etc.)
```

The root directory contains **only the `.md` source file**. All LaTeX sources,
compiled PDFs, and build artifacts go into `build/` and `figures/`.

---

## Step 1: Ask User Info

Check the Markdown file for YAML frontmatter:

```yaml
---
author: Name
institute: Organization
---
```

- If frontmatter has `author` and `institute` → use them, skip asking.
- If missing → ask the user before proceeding.

---

## Step 2: Analyze Structure

Read the Markdown and create a **slide map** in your thinking block:

```
# Main Title          → Title slide (\title{})
## Section 1          → \section{} (optional divider)
### Slide 1           → \begin{frame}{Slide 1}
### Slide 2           → \begin{frame}{Slide 2}
Total: X slides from X level-3 headers
```

**Mapping rules:**
- `#` (h1) → `\title{}`  (title slide)
- `##` (h2) → `\section{}` (optional divider)
- `###` (h3) → `\begin{frame}{exact title}...\end{frame}`

**Content density:** If a `###` section has >30 lines or >8 bullets → plan to split.

---

## Step 3: Detect Language and Find Fonts

```bash
if grep -qP '[\p{Han}]' ./file.md; then
    echo "Chinese detected → use xelatex"
else
    echo "English → use pdflatex"
fi
```

If Chinese is detected, **must** search for available CJK fonts before proceeding:

```bash
fc-list :lang=zh family | sort -u
```

Pick a font that actually exists on the system. Common results:
- macOS: `PingFang TC`, `Heiti TC`, `Songti TC`
- Linux: `Noto Sans CJK TC`, `WenQuanYi Micro Hei`

**MUST NOT** hardcode a font name without verifying it exists via `fc-list`.
If no CJK font is found, stop and inform the user to install one.

---

## Step 4: Load Template and Choose Theme

Read the template from `references/template.tex` in this skill's directory.

### Theme Selection

Choose a theme based on the content's tone and formality:

| Style | Theme | Color | Best for |
|-------|-------|-------|----------|
| Academic | `Madrid` | `beaver` | Research, lectures |
| Modern | `metropolis` | default | Tech, startups |
| Professional | `CambridgeUS` | `dolphin` | Business, reports |
| Minimal | `default` | `seagull` | General purpose |

If the user specifies a theme, use it. Otherwise, choose based on content.
When using a color theme, add `\usecolortheme{color}` after `\usetheme{}`.

### Replace Placeholders

- `YOUR_THEME_HERE` → chosen theme name
- `YOUR_TITLE_HERE` → title from `#` heading
- `YOUR_AUTHOR_HERE` → author from frontmatter or user input
- `YOUR_INSTITUTE_HERE` → institute from frontmatter or user input
- `CONTENT_SECTIONS_HERE` → converted LaTeX content

If Chinese is detected, add before `\begin{document}`:
```latex
\usepackage{xeCJK}
\setCJKmainfont{<font found in Step 3>}
```
Use the actual font name confirmed by `fc-list` in Step 3. Never guess.

---

## Step 5: Create Figures

If the Markdown describes diagrams, flowcharts, or relationships that can
be drawn, create each figure as an independent standalone TikZ file before
writing the main Beamer `.tex`.

For each figure, follow this **compile → inspect → fix** loop:

```
1. Create figures/fig_<name>/ directory
2. Copy template (flowchart_template.tex for flowcharts) as starting point
3. Write nodes and arrows — only modify the CONTENT section
4. Compile: pdflatex fig_<name>.tex
5. Read the compiled PDF with the Read tool (renders as image)
6. Visually inspect for:
   - Arrow paths passing through or touching unrelated nodes
   - Nodes overlapping or sitting too close
   - Feedback/return arrows lacking clearance from other elements
   - Labels colliding with arrows or nodes
   - Text truncated or unreadable
7. If ANY issue → fix the .tex and go back to step 4
8. Repeat until the PDF is clean
```

**This loop is mandatory.** Do not skip the visual inspection. TikZ layout
depends on actual node content width and height, which cannot be predicted
from source code alone — you must see the compiled result to judge correctness.

**Naming convention:** `figures/fig_<name>/fig_<name>.tex`

**When to use TikZ standalone:** flowcharts, block diagrams, pipelines, state machines, trees.
**When to use includegraphics directly:** photos, screenshots, existing image files referenced in Markdown.

### Flowchart Diagrams

Follow ISO 5807 standard. See `references/flowchart_standard.md` for shapes,
layout rules, and verification checklist. Start from `references/flowchart_template.tex`.

**Common overlap causes and fixes:**

| Symptom | Cause | Fix |
|---------|-------|-----|
| Feedback arrow passes through a side node | Vertical segment x too close to side node edge | Use `max()`/`min()` Safe X algorithm across ALL side nodes; increase `\loopClearance` |
| Feedback arrow visually merges with side-exit arrow | Both arrows enter diamond at same anchor (`.east`/`.west`) | Enter via degree anchors: `.30` (right), `.150` (left) — see `flowchart_standard.md` |
| Diamond too wide, overlapping side node | Long text in decision node inflates width | Shorten text, increase `\sideGap`, or use line break (`\\`) inside node |
| Side nodes too close to center | Default `\sideGap` insufficient for wide nodes | Use explicit `left=Xcm of` with a larger value |

### General Diagram Rules (all types)

- **No overlapping:** nodes, labels, and arrows must not overlap or touch each other.
- **Readable text:** use `\small` or `\footnotesize` only when necessary, never `\tiny` or `\scriptsize`.
- **White space:** leave adequate spacing. Cramped diagrams are harder to read than slightly larger ones split across two slides.
- **Fit the slide:** adjust `width` in `\includegraphics` so the diagram fits within the frame without overflow.

**All figures must be complete before Step 6.**

If there are no diagrams to create, skip this step.

---

## Step 6: Iterative Convert & Compile

This step combines conversion, compilation, and visual verification into a
single iterative loop. **Do not write the entire .tex and compile once at the
end** — work in batches so layout problems are caught and fixed early.

### 6a. Conversion Rules

| Markdown | LaTeX | Notes |
|----------|-------|-------|
| `# Title` | `\title{Title}` | Title slide |
| `## Section` | `\section{Section}` | Optional divider |
| `### Slide` | `\begin{frame}{Slide}...\end{frame}` | **Use exact title** |
| `**bold**` | `\textbf{bold}` | |
| `*italic*` | `\emph{italic}` | |
| `` `code` `` | `\texttt{code}` | |
| `- item` | `\begin{itemize}\item ...\end{itemize}` | |
| `1. item` | `\begin{enumerate}\item ...\end{enumerate}` | |
| Code block | `\begin{lstlisting}...\end{lstlisting}` | Frame needs `[fragile]` |
| `$formula$` | `$formula$` | Inline math |
| `$$formula$$` | `\[ formula \]` | Display math |
| `![](img.png)` | `\includegraphics[width=0.7\textwidth]{img.png}` | In `figure` env |

### Including Figures

Reference figures from `build/` using relative path:
```latex
\begin{frame}{System Architecture}
    \begin{center}
        \includegraphics[width=0.8\textwidth]{../figures/fig_architecture/fig_architecture.pdf}
    \end{center}
\end{frame}
```

### Code Listings

The template includes `listings` with line numbers, syntax highlighting, and
a frame border pre-configured. Use `lstlisting` for all code blocks.

```latex
\begin{frame}[fragile]{Code Example}
\begin{lstlisting}[language=Python]
def hello():
    print("Hello, World!")
\end{lstlisting}
\end{frame}
```

**Code layout rules:**
- **Always specify language:** `[language=Python]`, `[language=C]`, etc. for proper syntax highlighting.
- **Line numbers:** enabled by default in the template. Helps readers reference specific lines during discussion.
- **Font size:** `\small` is the default. For long code (>15 lines), use `\footnotesize` via `basicstyle=\ttfamily\footnotesize`. Never use `\tiny`.
- **Fit the slide:** if code exceeds one slide, split across multiple frames with `(1/2)` suffix. Do not shrink font to force-fit.
- **No horizontal scroll:** set `breaklines=true` (already in template). If a line is still too long, manually wrap it.
- **Highlight key lines:** use `escapeinside={(*@}{@*)}` to annotate important lines with LaTeX markup when needed.

### Tables

```latex
\begin{table}
    \centering
    \begin{tabular}{ll}
        \toprule
        \textbf{Column 1} & \textbf{Column 2} \\
        \midrule
        Data 1 & Data 2 \\
        \bottomrule
    \end{tabular}
\end{table}
```

### Visual Enhancement (optional)

Only add if the original Markdown **clearly marked** something as special
(e.g., bold definitions, explicit pros/cons, "important"/"warning" labels):

```latex
\begin{block}{Term}         % author used bold or "definition"
\begin{alertblock}{Warning}  % author used "important", "warning", "note"
\begin{columns}              % author listed pros/cons, before/after
```

Do NOT use blocks to highlight what you think is important.

### Content Overflow

If a single `###` section overflows one slide:

```latex
\begin{frame}{Long Section (1/2)}
  First half of content
\end{frame}
\begin{frame}{Long Section (2/2)}
  Second half of content
\end{frame}
```

**Split criteria:** >30 lines of text, >8 bullet points, or code + explanation >20 lines.

### 6b. Batch Loop

Work in batches of **5–10 slides** (one section boundary is a natural cut point).
For each batch:

```
1. Write the complete .tex file (preamble + all frames written so far + new batch
   + \end{document}). Each batch iteration overwrites the file with the full content.
2. Compile (×2 passes for TOC/references):
     # English
     cd build && pdflatex <name>.tex && pdflatex <name>.tex
     # Chinese
     cd build && xelatex <name>.tex && xelatex <name>.tex
3. Convert new pages to PNG for precise inspection:
     pdftoppm -r 150 -png -f <first_new> -l <last_new> <name>.pdf slide
   If pdftoppm is not available, fall back to reading the PDF directly:
     Read tool → build/<name>.pdf (pages: "<first_new>-<last_new>")
4. Inspect each new page with the Read tool (PNG or PDF)
5. Check for:
   - Text overflow / overfull hboxes
   - Slides too empty (< 30% used) or too crowded
   - Figures cut off or missing
   - Code blocks exceeding frame width
   - Orphan titles (title on one slide, content on next)
6. If ANY issue → fix the .tex → recompile → re-inspect that batch
7. Move to the next batch
```

**This loop is mandatory.** Do not skip visual inspection for any batch.

### 6c. Final Full Verification

After all batches are done, do one final full compile and verify it is **error-free**:

```
1. Compile the complete .tex (×2 passes)
2. Check the log for errors and warnings (overfull hbox, missing refs, etc.)
3. Fix any remaining compile issues → recompile
```

Visual inspection of every page is delegated to Step 7 (Sub Agent QA).

**Common compile fixes:**

| Error | Fix |
|-------|-----|
| Missing `\begin{document}` | Check template structure |
| Undefined control sequence | Add `\usepackage{}` |
| Code not showing | Add `[fragile]` to frame |
| Overfull hbox | Add `\small` or line breaks |
| Chinese not rendering | Check font, use xelatex |
| Figure not found | Check `figures/` path and filename |

---

## Step 7: Sub Agent QA

**Rationale:** The agent who wrote the slides should not be the only one who
verifies them — self-review tends to skip issues you've already "seen past."
Dispatch an **independent sub agent** for a final quality sweep.

### 7a. Visual QA (mandatory)

Use the Task tool with `subagent_type: "Explore"` to dispatch an Explore agent.
Provide this prompt (fill in `<name>` with the presentation base name):

```
Visual QA for Beamer presentation.

Files to inspect:
- build/<name>.pdf (Read tool — inspect every page)
- If PNG files exist in build/slide*.png, inspect those instead (one per page)

Check EVERY page for these issues:
1. Text overflow: any text running off the slide edge or into margins
2. Orphan titles: a frame title appearing alone with content on the next slide
3. Empty slides: slides with < 30% content area used
4. Crowded slides: slides where content is visually cramped or text is too small
5. Figure issues: images cut off, missing, or not properly centered
6. Code overflow: code blocks exceeding the frame width or running off-slide
7. Table overflow: tables wider than the slide or with truncated columns
8. Consistent styling: font sizes, bullet styles, and spacing uniform across slides

Report format — return ONLY one of:
  PASS — no issues found
  FAIL — list each issue as: "Page X: <description of problem>"
```

### 7b. Outline QA (mandatory)

Use the Task tool with `subagent_type: "Explore"` to dispatch a second Explore agent.
Provide this prompt (fill in `<name>` and `<md_file>` with absolute paths):

```
Outline QA for Beamer presentation.

Files to inspect (use absolute paths):
- <md_file> (the original Markdown source, at the working directory root)
- build/<name>.tex (the generated LaTeX, inside the build/ subdirectory)

Check for these structural issues:
1. Missing content: any ### heading in the Markdown without a corresponding \begin{frame}
2. Title mismatch: frame titles that differ from the original ### heading text
3. Order mismatch: frames appearing in a different order than the Markdown headings
4. Section numbering style: are \section{} titles consistent in style (all numbered, or all unnumbered)?
5. Title length balance: are frame titles roughly similar in length, or are some extremely long/short?
6. Orphan topics: topics introduced in the Markdown (mentioned in intro or overview) but never expanded
7. Section boundaries: is it clear where one section ends and the next begins?
8. Merged/split content: was any content merged across headings or split in a way that breaks logical flow?

Report format — return ONLY one of:
  PASS — no issues found
  FAIL — list each issue as: "<issue type>: <description>"
```

### 7c. Act on Results

- If **both** QA agents return PASS → proceed to Step 8.
- If **either** returns FAIL → fix every reported issue in the `.tex`, recompile,
  re-verify the fixed pages visually, then re-run the failing QA agent(s).
- Repeat until both pass. Do not skip or ignore sub agent findings.

---

## Step 8: Report

```
Converted Markdown to Beamer presentation.

Files:
- build/<name>.tex              (LaTeX source)
- build/<name>.pdf              (final output, X slides)
- build/slide*.png              (per-page previews, if pdftoppm available)
- figures/fig_*/fig_*.tex       (diagram sources, if any)
- figures/fig_*/fig_*.pdf       (compiled figures, if any)

Used [theme] theme. Preserved all original sections and content.
Sub Agent QA: Visual ✓  Outline ✓
```

---

## Pre-Delivery Checklist

**Content:**
- [ ] Every `###` has a corresponding `\begin{frame}{exact title}`
- [ ] Slide order matches Markdown order
- [ ] No sections merged or rearranged; all content included
- [ ] Titles use exact original text
- [ ] Bold/italic/list patterns preserved

**Build:**
- [ ] Code frames use `[fragile]`
- [ ] PDF compiles without errors
- [ ] Text fits on slides (verified via batch inspection)
- [ ] Outline and The End slides are present

**Outline QA:**
- [ ] Section numbering style is consistent (all numbered or all unnumbered)
- [ ] Frame titles are balanced in length (no extreme outliers)
- [ ] Section boundaries are clear and logical
- [ ] No orphan topics (introduced but never expanded)
- [ ] Story flow is coherent — each section builds on the previous

**Diagrams (if any):**
- [ ] All figures compile independently without errors
- [ ] No overlapping nodes, labels, or arrows
- [ ] Feedback/return arrows have sufficient clearance
- [ ] Flowchart shapes follow ISO 5807 (see `references/flowchart_standard.md`)
- [ ] All decision exits labeled (Yes/No)

**Sub Agent QA:**
- [ ] Visual QA agent returned PASS
- [ ] Outline QA agent returned PASS
