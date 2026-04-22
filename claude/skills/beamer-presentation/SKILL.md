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
6. Convert to LaTeX          → fill template with content, reference figure PDFs
7. Compile main (×2)         → generate presentation PDF
8. Verify                    → read PDF to check all pages
9. Report                    → list output files
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

## Step 6: Convert Markdown to LaTeX

Write `build/<name>.tex` by filling the template with converted content.

### Conversion Rules

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

---

## Step 7: Compile Main Presentation

Compile from within the `build/` directory:

```bash
# English
cd build && pdflatex <name>.tex && pdflatex <name>.tex

# Chinese
cd build && xelatex <name>.tex && xelatex <name>.tex
```

**Common fixes:**

| Error | Fix |
|-------|-----|
| Missing `\begin{document}` | Check template structure |
| Undefined control sequence | Add `\usepackage{}` |
| Code not showing | Add `[fragile]` to frame |
| Overfull hbox | Add `\small` or line breaks |
| Chinese not rendering | Check font, use xelatex |
| Figure not found | Check `figures/` path and filename |

---

## Step 8: Verify

After successful compilation, **must** visually verify the final PDF:

1. Use the Read tool to open `build/<name>.pdf` — it renders each page as an image
2. Check every page: text fits on slides, diagrams display correctly, no overflow, no missing content
3. If issues are found, fix the `.tex` (or figure `.tex`) and recompile

---

## Step 9: Report

```
Converted Markdown to Beamer presentation.

Files:
- build/<name>.tex              (LaTeX source)
- build/<name>.pdf              (final output, X slides)
- figures/fig_*/fig_*.tex       (diagram sources, if any)
- figures/fig_*/fig_*.pdf       (compiled figures, if any)

Used [theme] theme. Preserved all original sections and content.
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
- [ ] Text fits on slides
- [ ] Outline and The End slides are present

**Diagrams (if any):**
- [ ] All figures compile independently without errors
- [ ] No overlapping nodes, labels, or arrows
- [ ] Feedback/return arrows have sufficient clearance
- [ ] Flowchart shapes follow ISO 5807 (see `references/flowchart_standard.md`)
- [ ] All decision exits labeled (Yes/No)
