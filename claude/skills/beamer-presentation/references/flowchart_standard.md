# Flowchart Standard (ISO 5807)

Reference for creating flowchart diagrams in TikZ standalone files.

**Template:** Always start from `references/flowchart_template.tex`. Copy the
template into the figure directory and only modify the CONTENT section. Do NOT
change styles or preamble. Layout constants may be adjusted if the default
spacing is too tight or loose.

---

## Standard Shapes and Colors

All styles are pre-defined in `flowchart_template.tex`. The table below is for
reference only — use the style names, not raw TikZ options.

| Element | Style name | Shape | Fill Color | Usage |
|---------|-----------|-------|------------|-------|
| Start/End | `startstop` | `stadium` | `blue!15` | Entry and exit points |
| Process | `process` | `rectangle` | `orange!12` | Computation, assignment |
| Decision | `decision` | `diamond` | `green!12` | Conditional branch (label all exits) |
| Input/Output | `io` | `trapezium` | `yellow!15` | Data I/O |
| Predefined Process | `predef` | `rectangle, double` | `violet!10` | Subroutine / function call |

Do not invent custom shapes, colors, or style overrides.

---

## Layout Rules

- **Flow direction:** top→bottom as primary, left→right as secondary.
- **Single entry, clear exits:** one Start node; every path must reach an End/Return node.
- **Decision labels:** every exit path from a diamond must be labeled (Yes/No, True/False).
- **No crossing arrows:** reroute with bends. Use on-page connectors (small circles) only if unavoidable.
- **Use template styles only:** never add per-node style overrides. All sizing, colors, and fonts come from `flowchart_template.tex`.

---

## Preventing Overlap (Critical)

### Layout Strategy: Define Columns First

Before placing nodes, plan the diagram on a grid with explicit columns:

```
Column L2 | Column L1 | Column C | Column R1 | Column R2
(far left)| (left)    | (center) | (right)   | (far right)
          |           | Start    |           |
          |           | Process  |           |
          | Return -1 | Decision |           |
          |           | Process  |           |
          |           | Decision | Return mid|
          |           | Decision |           |
          | high=...  |          | low=...   |
(loop-L)  |           |          |           | (loop-R)
```

The outermost columns (L2, R2) are reserved for feedback loop arrows.
**No nodes may be placed in these columns.**

### Feedback Loop Routing — Two-Part Algorithm

Feedback arrows have two problems to solve:
1. **Safe X:** the vertical segment must clear every side node on that side.
2. **Safe entry:** the horizontal re-entry must not visually merge with
   side-exit arrows or the main-spine arrow.

#### Part 1: Compute safe L2/R2 x

After placing ALL nodes, compute the x for each outer column from the
**outermost edge of every side node on that side**:

```latex
% Right: max .east among ALL right-side nodes + clearance
\path let
  \p{a} = (retmid.east),
  \p{b} = (lowupd.east),
  \n{rx} = {max(\x{a}, \x{b}) + \loopClearance}
in coordinate (R2) at (\n{rx}, 0);

% Left: min .west among ALL left-side nodes - clearance
\path let
  \p{a} = (retnotfound.west),
  \p{b} = (highupd.west),
  \n{lx} = {min(\x{a}, \x{b}) - \loopClearance}
in coordinate (L2) at (\n{lx}, 0);
```

#### Part 2: Enter the target decision via degree anchors

Side-exit arrows use `.east`/`.west` (0°/180°). The main-spine arrow uses
`.north`/`.south` (90°/270°). To avoid visual merging, feedback arrows
must enter the target decision through **different anchors**.

Use `.30` (upper-right) for right-side feedback and `.150` (upper-left)
for left-side feedback:

```latex
% Right feedback: side node → R2 column → cond.30
\draw [arrow]
  (lowupd.east) -- (R2 |- lowupd.east)    % horizontal to R2
                -- (R2 |- cond.30)         % vertical to .30 y-level
                -- (cond.30)               % horizontal into .30 anchor
;

% Left feedback: side node → L2 column → cond.150
\draw [arrow]
  (highupd.west) -- (L2 |- highupd.west)  % horizontal to L2
                 -- (L2 |- cond.150)       % vertical to .150 y-level
                 -- (cond.150)             % horizontal into .150 anchor
;
```

**Why this works:**
- `.30` y-level is above `.east` (0°) → the feedback horizontal segment
  runs **above** the side-exit arrow, visually separated.
- `.150` y-level is above `.west` (180°) → same separation on the left.
- Neither `.30` nor `.150` conflicts with `.north` (90°) which is used
  by the main-spine arrow from above.
- `(R2 |- cond.30)` automatically projects R2's x with `.30`'s y —
  no manual coordinate math needed.

**Key points:**
1. `max()`/`min()` ensures the vertical segment clears the widest node
   on each side, regardless of which row it sits on.
2. Define `(R2)` and `(L2)` **once** after all nodes, reuse everywhere.
3. Degree anchors (`.30`, `.150`) avoid visual merging with side-exit
   and main-spine arrows — this is the critical insight.
4. If the diagram has no side node at the same y as the target decision,
   `.east`/`.west` entry is acceptable, but `.30`/`.150` is always safer.

#### Choosing the entry anchor — general principle

The entry anchor must differ from every other anchor already used on the
target node. Pick based on which anchors are occupied:

| Target node | Main-spine uses | Side-exits use | Feedback enters via |
|-------------|----------------|----------------|---------------------|
| Diamond (top→bottom flow) | `.north`, `.south` | `.east`, `.west` | `.30` (right), `.150` (left) |
| Diamond (bottom→up flow) | `.south`, `.north` | `.east`, `.west` | `.330` (right), `.210` (left) |
| Diamond (single side-exit) | `.north`, `.south` | one of `.east`/`.west` | free side: `.east`/`.west`; occupied side: `.30`/`.150` |
| Rectangle | `.north`, `.south` | `.east`, `.west` | use `[xshift=±8pt]node.north` or `[yshift=4pt]node.east` to offset from occupied anchors |

**Rule of thumb:** on a diamond, every 30° is a distinct anchor with a
different (x, y) pair. Pick the one closest to, but not equal to, any
occupied anchor. On a rectangle, use `xshift`/`yshift` offsets to
separate from occupied anchors since rectangle anchors at similar angles
share the same y (top edge) or x (side edge).

### Node Spacing (from template constants)

The template defines these constants — use them instead of hardcoded values:

| Constant | Value | Usage |
|----------|-------|-------|
| `\vgapSmall` | 1.5cm | Process → Process, Process → Decision |
| `\vgapLarge` | 2.2cm | Decision → next node (diamond needs room) |
| `\sideGap` | 3.5cm | Center to side nodes (L1/R1 columns) |
| `\loopClearance` | 2.0cm | Feedback arrow beyond outermost node edge |

```latex
% Use constants, not hardcoded distances:
\node (proc1) [process, below=\vgapSmall of start]  {Process};
\node (dec1)  [decision, below=\vgapLarge of proc1]  {Condition?};
\node (retA)  [startstop, left=\sideGap of dec1]     {Return A};
```

---

## Verification Checklist

After compiling each figure, read the PDF and check:

1. Do any arrows pass through or touch a node they shouldn't?
2. Do any nodes overlap or sit too close to each other?
3. Do feedback/return arrows have enough clearance from all elements?
4. Are all decision exits labeled?
5. Do shapes match their standard meaning (diamond=decision, rectangle=process, etc.)?

If any issue is found, adjust positioning or routing offsets and recompile.
