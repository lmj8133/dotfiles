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
1. Read Markdown file           → map headers to slides
2. Detect language               → choose compiler (pdflatex / xelatex)
3. Choose theme                  → visual style only
4. Convert to LaTeX              → 1:1 mapping
5. Compile (×2)                  → generate PDF
6. Report                        → list output files
```

All files stay in current directory.

---

## Step 1: Analyze Structure

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

**Language detection:**
```bash
if grep -qP '[\p{Han}]' ./file.md; then
    echo "Chinese detected → use xelatex"
else
    echo "English → use pdflatex"
fi
```

**Content density:** If a `###` section has >30 lines or >8 bullets → plan to split.

---

## Step 2: Choose Theme

| Style | Theme | Color |
|-------|-------|-------|
| Academic | `Madrid` | `beaver` |
| Modern | `metropolis` | default |
| Professional | `CambridgeUS` | `dolphin` |
| Minimal | `default` | `seagull` |

Use user-requested theme if specified; otherwise choose based on formality.

---

## Step 3: Convert to LaTeX

### Template

```latex
\documentclass[aspectratio=169,11pt]{beamer}
\usetheme{Madrid}
\usecolortheme{beaver}

% Chinese support (uncomment if detected)
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

\title{[from \# heading]}
\author{Author}
\date{\today}

\begin{document}
\frame{\titlepage}

% ## → \section{}
% ### → \begin{frame}{exact title}...\end{frame}

\end{document}
```

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

### Visual Enhancement (optional)

Only add if the original Markdown **clearly marked** something as special
(e.g., bold definitions, explicit pros/cons, "important"/"warning" labels):

```latex
\begin{block}{Term}         % author used bold or "definition"
\begin{alertblock}{Warning}  % author used "important", "warning", "note"
\begin{columns}              % author listed pros/cons, before/after
```

Do NOT use blocks to highlight what you think is important.

---

## Step 4: Handle Content Overflow

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
Preserve original order — just distribute across slides.

---

## Step 5: Compile

```bash
# English
pdflatex presentation.tex && pdflatex presentation.tex

# Chinese
xelatex presentation.tex && xelatex presentation.tex
```

**Common fixes:**

| Error | Fix |
|-------|-----|
| Missing `\begin{document}` | Check template structure |
| Undefined control sequence | Add `\usepackage{}` |
| Code not showing | Add `[fragile]` to frame |
| Overfull hbox | Add `\small` or line breaks |
| Chinese not rendering | Check font, use xelatex |

---

## Step 6: Report

```
Converted Markdown to Beamer presentation.

Files in current directory:
- presentation.tex (LaTeX source)
- presentation.pdf (X slides)

Used [theme] theme. Preserved all original sections and content.
```

---

## Quick Example

**Input:** `### Three Types` with a bullet list →
**Output:**
```latex
\begin{frame}{Three Types}
\begin{itemize}
\item Supervised learning
\item Unsupervised learning
\item Reinforcement learning
\end{itemize}
\end{frame}
```

Key: exact title, original order, no added/removed content.

---

## Pre-Delivery Checklist

- [ ] Every `###` has a corresponding `\begin{frame}{exact title}`
- [ ] Slide order matches Markdown order
- [ ] No sections merged or rearranged; all content included
- [ ] Titles use exact original text
- [ ] Bold/italic/list patterns preserved
- [ ] Code frames use `[fragile]`
- [ ] PDF compiles without errors
- [ ] Text fits on slides
