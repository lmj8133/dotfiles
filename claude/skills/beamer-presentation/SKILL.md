---
name: beamer-presentation
description: "Convert Markdown to professional LaTeX Beamer presentations while preserving the original structure, logic, and emphasis. Transform format, not content."
---

# Markdown to LaTeX Beamer Presentation

## ⚠️ CRITICAL RULE: PRESERVE ORIGINAL STRUCTURE

**Your job is FORMAT CONVERSION, not content reorganization.**

### What you MUST preserve:
- ✅ Original heading hierarchy (### → slide titles, exactly as written)
- ✅ Order of sections and ideas
- ✅ Author's logical flow
- ✅ All content (no omissions)
- ✅ Emphasis (bold/italic patterns)

### What you MAY do:
- ✅ Convert Markdown syntax to LaTeX syntax
- ✅ Add visual formatting (blocks, columns) to enhance readability
- ✅ Split oversized content across slides IF it breaks slide boundaries
- ✅ Choose appropriate themes and colors

### What you MUST NOT do:
- ❌ Change heading text or order
- ❌ Merge or reorganize sections
- ❌ Add content not in original
- ❌ Rearrange the logical flow
- ❌ Omit or summarize content

---

## Quick Workflow

User runs Claude Code from directory containing Markdown file.

```bash
1. ls && view ./file.md              # Read file
2. [Analyze structure]               # Map headers → slides
3. [Detect language]                 # Choose compiler
4. [Choose theme]                    # Visual style only
5. create_file presentation.tex      # Convert 1:1
6. pdflatex/xelatex (×2)            # Compile
7. ls -lh presentation.pdf           # Verify
```

**All files stay in current directory.**

---

## Step 1: Analyze Structure

Read the Markdown and create a **slide map**:

```bash
view ./file.md
```

**In thinking block, create mapping:**
```
Line 1: # Main Title          → Title slide
Line 5: ## Section 1          → Section slide (optional)
Line 8: ### Slide 1           → Frame 1: "Slide 1"
Line 15: ### Slide 2          → Frame 2: "Slide 2"
Line 22: ### Slide 3          → Frame 3: "Slide 3"
...

Total: X slides from X level-3 headers
```

**Rules for mapping:**
- `#` (h1) → Title slide
- `##` (h2) → Section divider (optional, use `\section{}`)
- `###` (h3) → Individual slide with exact title
- Each `###` = one `\begin{frame}{exact title}...\end{frame}`

**Language detection:**
```bash
if grep -qP '[\p{Han}]' ./file.md; then
    echo "Chinese detected → use xelatex"
else
    echo "English → use pdflatex"
fi
```

**Content density check:**
- If one `###` section has >30 lines → split into part 1, part 2
- Otherwise keep as single slide

---

## Step 2: Choose Theme

Pick theme based on **visual style preference** (NOT content):

| Style | Theme | Color |
|-------|-------|-------|
| Academic | `Madrid` | `beaver` |
| Modern | `metropolis` | default |
| Professional | `CambridgeUS` | `dolphin` |
| Minimal | `default` | `seagull` |

**If user requests specific theme, use that. Otherwise choose based on formality level.**

---

## Step 3: Convert to LaTeX

### Template

```latex
\documentclass[aspectratio=169,11pt]{beamer}
\usetheme{Madrid}
\usecolortheme{beaver}

% Chinese support (if detected)
% \usepackage{xeCJK}
% \setCJKmainfont{Noto Sans CJK TC}

\usepackage{graphicx,amsmath,listings,hyperref}

\lstset{
    basicstyle=\ttfamily\small,
    breaklines=true,
    frame=single,
    numbers=left,
    keywordstyle=\color{blue}\bfseries
}

\title{[从 # 提取]}
\author{Author}
\date{\today}

\begin{document}
\frame{\titlepage}

% Convert ## to \section{} (optional)
% Convert ### to \begin{frame}{exact title}

\end{document}
```

### Conversion Rules

**1:1 mapping - do NOT reorganize:**

| Markdown | LaTeX | Notes |
|----------|-------|-------|
| `# Title` | `\title{Title}` | Title slide |
| `## Section` | `\section{Section}` | Optional divider |
| `### Slide` | `\begin{frame}{Slide}...\end{frame}` | **Use exact title** |
| `**bold**` | `\textbf{bold}` | Preserve emphasis |
| `*italic*` | `\emph{italic}` | |
| `` `code` `` | `\texttt{code}` | |
| `- item` | `\begin{itemize}\item item\end{itemize}` | |
| `1. item` | `\begin{enumerate}\item item\end{enumerate}` | |

**Code blocks:**
```latex
\begin{frame}[fragile]{Slide Title}
\begin{lstlisting}[language=Python]
code here
\end{lstlisting}
\end{frame}
```

**Math:**
- Inline: `$formula$`
- Display: `\[ formula \]`

**Images:**
```latex
\begin{figure}
\centering
\includegraphics[width=0.7\textwidth]{image.png}
\caption{Caption}
\end{figure}
```

### Visual Enhancement (OPTIONAL)

Only add if it improves readability **without changing content**:

```latex
% Key definition (if author used bold or stated "definition")
\begin{block}{Term}
Definition text from original
\end{block}

% Comparison (if author listed pros/cons, before/after)
\begin{columns}
\column{0.48\textwidth}
Original left content
\column{0.48\textwidth}
Original right content
\end{columns}

% Warning (if author used "important", "warning", "note")
\begin{alertblock}{Warning}
Original warning text
\end{alertblock}
```

**DO NOT use blocks to "highlight what you think is important"** - only use them if the original Markdown clearly marked something as special.

---

## Step 4: Handle Content Overflow

**If single ### section has too much content for one slide:**

```latex
% Original: ### Long Section with 40 lines

% Split into:
\begin{frame}{Long Section (1/2)}
First half of content
\end{frame}

\begin{frame}{Long Section (2/2)}
Second half of content
\end{frame}
```

**Criteria for splitting:**
- >30 lines of text
- >8 bullet points
- Code + explanation >20 lines

**Preserve order** - just distribute across multiple slides.

---

## Step 5: Compile

```bash
# English
pdflatex presentation.tex
pdflatex presentation.tex

# Chinese
xelatex presentation.tex
xelatex presentation.tex
```

**Common errors:**

| Error | Fix |
|-------|-----|
| Missing `\begin{document}` | Check template structure |
| Undefined control sequence | Add `\usepackage{}` |
| Code not showing | Add `[fragile]` to frame |
| Overfull hbox | Add `\small` or line breaks |
| Chinese not rendering | Check font, use xelatex |

---

## Step 6: Report Completion

```bash
ls -lh presentation.pdf
```

**Report format:**
```
Converted Markdown to Beamer presentation.

Files in current directory:
- presentation.tex (LaTeX source)
- presentation.pdf (X slides)

Used [theme] theme. Preserved all original sections and content.
```

---

## Example: Faithful Conversion

**Input Markdown:**
```markdown
# Machine Learning Basics

## Introduction

### What is ML?
Machine learning is a subset of AI. It has three main types.

### Three Types
- Supervised learning
- Unsupervised learning
- Reinforcement learning

### Supervised Learning
Uses labeled data. Example: image classification.
```

**Output LaTeX (FAITHFUL):**
```latex
\documentclass[aspectratio=169]{beamer}
\usetheme{Madrid}
\usecolortheme{beaver}
\usepackage{graphicx,amsmath}

\title{Machine Learning Basics}
\author{Author}
\date{\today}

\begin{document}
\frame{\titlepage}

\section{Introduction}

\begin{frame}{What is ML?}
Machine learning is a subset of AI. It has three main types.
\end{frame}

\begin{frame}{Three Types}
\begin{itemize}
\item Supervised learning
\item Unsupervised learning
\item Reinforcement learning
\end{itemize}
\end{frame}

\begin{frame}{Supervised Learning}
Uses labeled data. Example: image classification.
\end{frame}

\end{document}
```

**Why this is correct:**
- ✅ Exact title text ("What is ML?" not "Introduction to ML")
- ✅ Original order maintained
- ✅ No content added or removed
- ✅ Simple list stays as list (no fancy blocks unless needed)
- ✅ Each ### becomes exactly one frame

---

## Conversion Checklist

Before reporting completion:

### Structure Fidelity
- [ ] Every `###` has corresponding `\begin{frame}{exact title}`
- [ ] Slide order matches Markdown order
- [ ] No sections merged or rearranged
- [ ] All content included (nothing omitted)

### Content Fidelity
- [ ] Titles use exact original text
- [ ] Bold/italic patterns preserved
- [ ] Lists maintain original items and order
- [ ] Code blocks included as-is
- [ ] No content invented or added

### Technical Quality
- [ ] PDF compiles without errors
- [ ] Code frames use `[fragile]`
- [ ] Math renders correctly
- [ ] Images load (if any)
- [ ] Text fits on slides

---

## Best Practices

**DO:**
- ✅ Preserve original structure exactly
- ✅ Use exact heading text as frame titles
- ✅ Keep original content order
- ✅ Split oversized slides only when necessary
- ✅ Use `[fragile]` for code

**DON'T:**
- ❌ Reorganize sections "to improve flow"
- ❌ Change heading text "to be clearer"
- ❌ Merge sections "because they're related"
- ❌ Add introductory/summary slides not in original
- ❌ Omit content "because it's not important"
- ❌ Rearrange bullets "for better logic"

---

## Notes for Claude Code

**Remember:**
- You are a **format converter**, not a content editor
- Markdown structure → LaTeX structure (1:1 mapping)
- Preserve logic flow - author knows best
- Only split content for slide overflow, never reorganize
- When in doubt, be literal

**Success = Original structure visible in slides + professional LaTeX formatting**
