"""Pure logic for locating figure / table captions in a PDF and computing
their clip rectangles. No file I/O — operates on `fitz.Document` / `fitz.Page`.
"""

from __future__ import annotations

import re
from collections import Counter
from typing import Literal

import fitz

Kind = Literal["figure", "table"]

_QUERY_RE = re.compile(
    r"""
    ^\s*
    (?P<head>figure|fig\.?|table|圖|表)
    [\s\.　]*
    (?P<num>\d+(?:[.\-]\d+)?)
    \s*$
    """,
    re.IGNORECASE | re.VERBOSE,
)


def normalize_query(figure_id: str) -> tuple[Kind, str, re.Pattern[str]] | None:
    """Parse a user-supplied identifier like 'Figure 3' / '圖 2-1' / 'Table 1'.

    Returns (kind, number, compiled_pattern) or None if unparseable.
    The pattern matches the same identifier inside PDF text, tolerating
    spaces and 'Fig.' / 'Fig' variants.
    """
    m = _QUERY_RE.match(figure_id)
    if not m:
        return None
    head = m.group("head").lower()
    num = m.group("num")
    if head in ("figure", "fig", "fig.", "圖"):
        kind: Kind = "figure"
    else:
        kind = "table"

    # Build a pattern that matches the caption inside PDF text.
    # Number must be followed by a non-digit boundary (avoid matching "31" when
    # looking for "3"). Allow optional zero-padding like "03".
    num_escaped = re.escape(num)
    if kind == "figure":
        head_alt = r"(?:Figure|Fig\.?|圖)"
    else:
        head_alt = r"(?:Table|表)"
    pdf_pattern = re.compile(
        rf"{head_alt}[\s\.　]*0*{num_escaped}(?!\d)",
        re.IGNORECASE,
    )
    return kind, num, pdf_pattern


def _line_text_and_bbox(line: dict) -> tuple[str, fitz.Rect]:
    """Concatenate spans within a line and merge their bboxes."""
    text = "".join(span["text"] for span in line["spans"])
    rect = fitz.Rect()
    for span in line["spans"]:
        rect |= fitz.Rect(span["bbox"])
    return text, rect


def find_caption_bboxes(page: fitz.Page, pattern: re.Pattern[str]) -> list[fitz.Rect]:
    """Return bboxes of text lines that *start* with a caption matching
    `pattern`, ordered with the most caption-like candidate first.

    Lines where the identifier appears mid-sentence are rejected. When
    several lines on the page satisfy the start-of-line rule (e.g. body
    prose that wrapped to begin "Fig. 2.2."), we score by how isolated the
    caption block is: a real caption usually sits in its own short block,
    while a prose line is part of a tall multi-line paragraph.
    """
    candidates: list[tuple[float, fitz.Rect]] = []
    for block in page.get_text("dict")["blocks"]:
        if block.get("type", 0) != 0:
            continue
        block_lines = block.get("lines", [])
        block_rect = fitz.Rect(block["bbox"])
        block_text_len = sum(len(s["text"]) for ln in block_lines for s in ln["spans"])
        for line in block_lines:
            text, bbox = _line_text_and_bbox(line)
            if not pattern.match(text.lstrip()):
                continue
            # Lower score = more caption-like. Penalize lines buried inside
            # tall, text-heavy paragraphs.
            score = block_rect.height + block_text_len * 0.05
            candidates.append((score, bbox))
    candidates.sort(key=lambda c: c[0])
    return [bbox for _, bbox in candidates]


def find_image_bboxes(page: fitz.Page, min_side: float = 30.0) -> list[fitz.Rect]:
    """Return bboxes of meaningful raster images on the page.

    Tiny images (icons, header decorations) below `min_side` are skipped.
    """
    boxes: list[fitz.Rect] = []
    for img in page.get_images(full=True):
        try:
            bbox = page.get_image_bbox(img)
        except ValueError:
            continue
        if bbox.is_empty or bbox.is_infinite:
            continue
        if bbox.width < min_side or bbox.height < min_side:
            continue
        boxes.append(bbox)
    return boxes


def _x_overlap_ratio(a: fitz.Rect, b: fitz.Rect) -> float:
    """Width of the x-axis intersection divided by the narrower box's width."""
    inter = max(0.0, min(a.x1, b.x1) - max(a.x0, b.x0))
    narrower = min(a.width, b.width)
    if narrower <= 0:
        return 0.0
    return inter / narrower


def match_figure(
    caption: fitz.Rect,
    images: list[fitz.Rect],
    page_rect: fitz.Rect,
    x_overlap_min: float = 0.3,
) -> fitz.Rect | None:
    """Find the image associated with a figure caption.

    Strategy: caption is usually below its figure, so first try images directly
    above; fall back to images below. Images that fully contain the caption
    (e.g. a page-spanning raster) are ignored — they indicate scanned pages
    where geometric matching is not meaningful.
    """
    candidates = [img for img in images if not img.contains(caption)]
    above = [
        img
        for img in candidates
        if img.y1 <= caption.y0 and _x_overlap_ratio(img, caption) >= x_overlap_min
    ]
    below = [
        img
        for img in candidates
        if img.y0 >= caption.y1 and _x_overlap_ratio(img, caption) >= x_overlap_min
    ]
    chosen: fitz.Rect | None = None
    if above:
        chosen = min(above, key=lambda r: caption.y0 - r.y1)
    elif below:
        chosen = min(below, key=lambda r: r.y0 - caption.y1)
    if chosen is None:
        return None
    padded = fitz.Rect(chosen) + (-4, -4, 4, 4)
    return padded & page_rect


_FIGURE_CAPTION_RE = re.compile(
    r"(?:Figure|Fig\.?|圖)[\s\.　]*\d+(?:[.\-]\d+)?",
    re.IGNORECASE,
)


def _sibling_caption_bboxes(page: fitz.Page, target: fitz.Rect) -> list[fitz.Rect]:
    """Other figure captions on the same horizontal band as `target`.

    Used to bound the x-range of a vector figure when several figures share
    one row (e.g. Fig 1.31 / 1.32 / 1.33 across the top of a page).
    """
    siblings: list[fitz.Rect] = []
    for block in page.get_text("dict")["blocks"]:
        if block.get("type", 0) != 0:
            continue
        for line in block.get("lines", []):
            text, bbox = _line_text_and_bbox(line)
            if not _FIGURE_CAPTION_RE.search(text):
                continue
            if bbox == target:
                continue
            # Same row: vertical overlap with target.
            if bbox.y1 <= target.y0 or bbox.y0 >= target.y1:
                continue
            siblings.append(bbox)
    return siblings


def _detect_columns(
    text_blocks: list[fitz.Rect],
    caption: fitz.Rect | None = None,
    min_gap: float = 8.0,
) -> list[tuple[float, float]] | None:
    """Detect column boundaries from text-block x positions.

    Returns a list of (x0, x1) ranges sorted left-to-right, or None if the
    page does not look like a clean multi-column layout.

    Strategy: identify the *majority column* by voting on x0/x1 of body
    blocks (paragraphs that wrap fill a column edge repeatedly). Then
    decide whether a second column exists based on whether content lies
    outside the majority column — including the caption itself, since
    side-caption layouts often leave only the caption description in the
    other column, too sparse to vote on its own.
    """
    if len(text_blocks) < 3:
        return None

    bin_size = 2.0
    x0_votes: Counter = Counter()
    x1_votes: Counter = Counter()
    for b in text_blocks:
        x0_votes[round(b.x0 / bin_size) * bin_size] += 1
        x1_votes[round(b.x1 / bin_size) * bin_size] += 1

    strong_min = max(2, len(text_blocks) // 4)
    # Pick the pair (left edge, right edge) with the most votes such that
    # the implied column is wide enough. Trying every viable pair guards
    # against ties where the highest-voted x0/x1 individually don't form
    # a valid column (e.g. left-column right edge ties with right-column
    # left edge in a balanced page).
    left_cands = sorted(
        ((x, n) for x, n in x0_votes.items() if n >= strong_min),
        key=lambda kv: -kv[1],
    )
    right_cands = sorted(
        ((x, n) for x, n in x1_votes.items() if n >= strong_min),
        key=lambda kv: -kv[1],
    )
    # The widest *column-resident* block sets an upper bound on a single
    # column's width. To find that, ignore the widest block (likely a
    # cross-column header / page-spanning rule) when establishing the cap.
    sorted_widths = sorted((b.width for b in text_blocks), reverse=True)
    if len(sorted_widths) >= 2:
        column_width_cap = sorted_widths[1] * 1.1
    else:
        column_width_cap = sorted_widths[0] * 0.95

    majority: tuple[float, float] | None = None
    best_score = -1
    for lx, ln in left_cands:
        for rx, rn in right_cands:
            width = rx - lx
            if width < 40.0 or width > column_width_cap:
                continue
            score = ln + rn
            if score > best_score:
                best_score = score
                majority = (lx, rx)
    if majority is None:
        return None

    # Look for content outside the majority column to decide whether a
    # second column exists. Both body blocks and (optionally) the caption
    # rect contribute.
    candidates = list(text_blocks)
    if caption is not None:
        candidates = candidates + [caption]

    left_outside = [b for b in candidates if b.x1 <= majority[0] - min_gap]
    right_outside = [b for b in candidates if b.x0 >= majority[1] + min_gap]

    columns: list[tuple[float, float]] = [majority]
    if left_outside:
        lx = min(b.x0 for b in left_outside)
        rx = max(b.x1 for b in left_outside)
        if rx - lx >= 30.0:
            columns.append((lx, rx))
    if right_outside:
        lx = min(b.x0 for b in right_outside)
        rx = max(b.x1 for b in right_outside)
        if rx - lx >= 30.0:
            columns.append((lx, rx))

    if len(columns) < 2:
        return None
    columns.sort()
    return columns


def _column_of(point_x: float, columns: list[tuple[float, float]]) -> int | None:
    """Return the index of the column whose x-range contains `point_x`,
    or None if it falls in a gutter."""
    for i, (x0, x1) in enumerate(columns):
        if x0 - 2 <= point_x <= x1 + 2:
            return i
    return None


def _body_blocks(page: fitz.Page, caption: fitz.Rect) -> list[fitz.Rect]:
    """Text blocks that look like prose paragraphs (used for column / band
    detection).

    Excludes:
    - The caption itself.
    - Tiny standalone spans (axis labels, point markers).
    - Blocks surrounded by figure drawings (likely figure-internal text
      such as 'Flux = va', 'E = σ/ϵ₀', or sub-panel labels), which would
      otherwise stop the layout band partway through a figure.
    """
    drawings = [
        d["rect"]
        for d in page.get_drawings()
        if d["rect"].width >= 5 and d["rect"].height >= 5
    ]

    def _is_figure_label(b: fitz.Rect, text: str) -> bool:
        return _is_figure_label_block(b, text, drawings)

    out: list[fitz.Rect] = []
    for b in page.get_text("dict")["blocks"]:
        if b.get("type", 0) != 0:
            continue
        bbox = fitz.Rect(b["bbox"])
        if bbox == caption:
            continue
        text = "".join(
            s["text"] for line in b.get("lines", []) for s in line.get("spans", [])
        ).strip()
        if bbox.width < 80 or len(text) < 10:
            continue
        if _is_figure_label(bbox, text):
            continue
        out.append(bbox)
    return out


def _rects_close(a: fitz.Rect, b: fitz.Rect, tol: float = 4.0) -> bool:
    """True if `b` is the same line/region as `a` to within `tol` pt
    (used to recognise a caption line as part of its enclosing block)."""
    return (
        abs(a.x0 - b.x0) < tol
        and abs(a.y0 - b.y0) < tol
        and abs(a.x1 - b.x1) < tol
        and a.y1 + tol >= b.y1
    )


def _is_figure_label_block(
    b: fitz.Rect,
    text: str,
    drawings: list[fitz.Rect],
) -> bool:
    """Heuristic: a text block sandwiched between drawings, or a short
    single-line block hugged by drawings on one side, or a narrow
    multi-line block embedded in a drawing region — is part of a figure
    rather than body prose. Real body paragraphs are taller and span the
    full column width."""
    if not drawings:
        return False
    # Sandwiched (drawings both above and below): use a generous
    # neighbourhood since multi-panel figures can have wide gaps.
    sandwich_nbhd = 80.0
    has_above_far = any(
        d.y1 <= b.y0 + 2 and b.y0 - d.y1 < sandwich_nbhd and d.x1 > b.x0 and d.x0 < b.x1
        for d in drawings
    )
    has_below_far = any(
        d.y0 >= b.y1 - 2 and d.y0 - b.y1 < sandwich_nbhd and d.x1 > b.x0 and d.x0 < b.x1
        for d in drawings
    )
    if has_above_far and has_below_far:
        return True
    # Short single-line block directly adjacent to a drawing — axis
    # label, sub-panel name, in-figure equation.
    is_short = b.height < 14 and len(text) < 50
    if is_short:
        close_nbhd = 30.0
        has_close = any(
            (
                (d.y1 <= b.y0 + 2 and b.y0 - d.y1 < close_nbhd)
                or (d.y0 >= b.y1 - 2 and d.y0 - b.y1 < close_nbhd)
            )
            and d.x1 > b.x0
            and d.x0 < b.x1
            for d in drawings
        )
        if has_close:
            return True
    # Narrow block fully embedded in a drawing region — multi-line
    # in-figure equation (e.g. Purcell 1.2's q1·q2/r² stack).
    if b.width < 180:
        ds_above = any(
            d.y1 <= b.y0 + 2 and d.x1 > b.x0 and d.x0 < b.x1 for d in drawings
        )
        ds_below = any(
            d.y0 >= b.y1 - 2 and d.x1 > b.x0 and d.x0 < b.x1 for d in drawings
        )
        if ds_above and ds_below:
            return True
        # Final catch: a narrow block whose y range falls inside the
        # overall drawing extent of the page is almost certainly part of
        # a figure (e.g. a label at the bottom of a multi-panel diagram
        # that has no drawing below it on the page).
        all_drawings_y0 = min(d.y0 for d in drawings)
        all_drawings_y1 = max(d.y1 for d in drawings)
        if b.y0 >= all_drawings_y0 - 4 and b.y1 <= all_drawings_y1 + 8 and ds_above:
            return True
    return False


def _empty_band(
    column: tuple[float, float],
    pivot_y: float,
    blockers: list[fitz.Rect],
    page_rect: fitz.Rect,
) -> tuple[float, float] | None:
    """Largest empty vertical band in `column` containing y=pivot_y, bounded
    by any blocker rect that lives within the column's x range. Returns
    None if `pivot_y` falls inside a blocker (no empty band exists there).
    """
    col_x0, col_x1 = column
    in_col = [b for b in blockers if b.x1 > col_x0 + 2 and b.x0 < col_x1 - 2]
    # Pivot must not be covered by any blocker in this column.
    for b in in_col:
        if b.y0 < pivot_y < b.y1:
            return None
    top = page_rect.y0
    bottom = page_rect.y1
    for b in in_col:
        if b.y1 <= pivot_y and b.y1 > top:
            top = b.y1
        if b.y0 >= pivot_y and b.y0 < bottom:
            bottom = b.y0
    return (top, bottom) if bottom > top else None


def match_figure_side_caption(
    caption: fitz.Rect,
    page: fitz.Page,
    page_rect: fitz.Rect,
    min_height: float = 30.0,
) -> fitz.Rect | None:
    """Locate a figure that lives in a different column than its caption.

    Many physics textbooks (Purcell, Tufte-style layouts) place captions in
    a narrow side column and the figure itself in the main column at the
    same vertical band. This pattern is invisible to the above/below
    heuristic in `match_figure_by_layout`.

    Strategy:
      1. Detect column boundaries from body-text x positions.
      2. Find the column the caption sits in.
      3. Among other columns, pick the one whose y-range opposite the
         caption is empty of body text.
      4. Other figure captions in the candidate column (or the caption
         column above/below this caption) act as additional blockers so
         multi-figure pages split cleanly.

    Returns None if the page is not multi-column, no figure column has
    enough empty space, or the empty band lies entirely above/below the
    caption (in which case `match_figure_by_layout` is a better fit).
    """
    body_blocks = _body_blocks(page, caption)
    columns = _detect_columns(body_blocks, caption=caption)
    if columns is None or len(columns) < 2:
        return None

    cap_col_idx = _column_of((caption.x0 + caption.x1) / 2, columns)
    if cap_col_idx is None:
        return None

    cap_y_mid = (caption.y0 + caption.y1) / 2
    other_captions = [c for c in _all_figure_captions(page) if c != caption]
    page_spanning = [
        d["rect"]
        for d in page.get_drawings()
        if d["rect"].width >= page_rect.width * 0.6
    ]
    page_spanning += [b for b in body_blocks if b.width >= page_rect.width * 0.5]
    blockers = body_blocks + other_captions + page_spanning

    candidates: list[tuple[int, tuple[float, float]]] = []
    for i, col in enumerate(columns):
        if i == cap_col_idx:
            continue
        band = _empty_band(col, cap_y_mid, blockers, page_rect)
        if band is None or band[1] - band[0] < min_height:
            continue
        # The band must vertically straddle the caption (otherwise the
        # figure is more naturally found by the above/below heuristic).
        if band[1] < caption.y0 or band[0] > caption.y1:
            continue
        candidates.append((i, band))

    if not candidates:
        return None

    def _area(item: tuple[int, tuple[float, float]]) -> float:
        i, (t, b) = item
        col_x0, col_x1 = columns[i]
        return (col_x1 - col_x0) * (b - t)

    fig_col_idx, (top, bottom) = max(candidates, key=_area)
    fig_x0, fig_x1 = columns[fig_col_idx]

    # Include the caption column horizontally so the caption text is
    # captured alongside the figure.
    cap_x0, cap_x1 = columns[cap_col_idx]
    left = min(fig_x0, cap_x0)
    right = max(fig_x1, cap_x1)
    top = min(top, caption.y0)
    bottom = max(bottom, caption.y1)

    rect = fitz.Rect(left, top + 2, right, bottom - 2) + (-4, 0, 4, 0)
    return rect & page_rect


def _all_figure_captions(page: fitz.Page) -> list[fitz.Rect]:
    """Every line on the page that starts with a figure-caption pattern."""
    out: list[fitz.Rect] = []
    for block in page.get_text("dict")["blocks"]:
        if block.get("type", 0) != 0:
            continue
        for line in block.get("lines", []):
            text, bbox = _line_text_and_bbox(line)
            if _FIGURE_CAPTION_RE.match(text.lstrip()):
                out.append(bbox)
    return out


def _caption_block_bbox(page: fitz.Page, caption_line: fitz.Rect) -> fitz.Rect:
    """Bbox of the caption title plus its description lines.

    A caption block in PDFs is usually a single text block containing both
    the title (e.g. "Figure 1.31.") and the description ("The flow…"). We
    take the title's enclosing block and trim it to the contiguous lines
    that follow the title — sibling captions accidentally merged into the
    same block (e.g. "FIGURE 1.31\nFIGURE 1.32" rendered side-by-side) are
    excluded by stopping at any other caption-pattern line.
    """
    for block in page.get_text("dict")["blocks"]:
        if block.get("type", 0) != 0:
            continue
        block_bbox = fitz.Rect(block["bbox"])
        if not block_bbox.contains(caption_line):
            continue
        rect = fitz.Rect(caption_line)
        seen_target = False
        for line in block.get("lines", []):
            text, line_bbox = _line_text_and_bbox(line)
            if line_bbox == caption_line:
                seen_target = True
                rect |= line_bbox
                continue
            if not seen_target:
                continue
            # Stop if a different caption line begins.
            if _FIGURE_CAPTION_RE.match(text.lstrip()):
                break
            rect |= line_bbox
        return rect
    return fitz.Rect(caption_line)


def match_figure_by_layout(
    caption: fitz.Rect,
    page: fitz.Page,
    page_rect: fitz.Rect,
    min_height: float = 30.0,
) -> fitz.Rect | None:
    """Approximate a figure's bbox from text layout when no image object fits.

    Used when the figure is vector-only or embedded inside a page-spanning
    raster. The figure region is the empty band between the caption and the
    nearest body text block above (preferred) or below — running headers and
    footers are ignored. Horizontally the bbox is confined to the caption's
    column (when the page is multi-column); otherwise sibling captions on
    the same row are used to split a wide figure row. The caption itself
    is included in the returned clip.
    """
    text_blocks = _body_blocks(page, caption)
    siblings = _sibling_caption_bboxes(page, caption)

    # If the page has multiple columns, confine the figure to the caption's
    # column — otherwise the bbox bleeds into the prose column.
    columns = _detect_columns(text_blocks, caption=caption)
    cap_col_idx = (
        _column_of((caption.x0 + caption.x1) / 2, columns) if columns else None
    )
    if columns and cap_col_idx is not None:
        left, right = columns[cap_col_idx]
    else:
        # Single-column or column detection failed: use sibling-aware
        # midpoints with body-text margin as the outer bound.
        caption_cx = (caption.x0 + caption.x1) / 2
        left_sibs = [s for s in siblings if (s.x0 + s.x1) / 2 < caption_cx]
        right_sibs = [s for s in siblings if (s.x0 + s.x1) / 2 > caption_cx]

        sibling_block_set = {tuple(s) for s in siblings}
        body_blocks = [
            b
            for b in text_blocks
            if tuple(b) not in sibling_block_set
            and not any(b.contains(s) for s in siblings)
        ]
        body_left = min((b.x0 for b in body_blocks), default=page_rect.x0)
        body_right = max((b.x1 for b in body_blocks), default=page_rect.x1)

        if left_sibs:
            nearest = max(left_sibs, key=lambda s: s.x1)
            left = (nearest.x1 + caption.x0) / 2
        else:
            left = body_left
        if right_sibs:
            nearest = min(right_sibs, key=lambda s: s.x0)
            right = (caption.x1 + nearest.x0) / 2
        else:
            right = body_right
    # Caption itself must stay inside the horizontal window.
    left = min(left, caption.x0)
    right = max(right, caption.x1)

    def _band(top: float, bottom: float) -> fitz.Rect | None:
        if bottom - top < min_height:
            return None
        # Inset top/bottom slightly to avoid catching the bounding rule
        # right against the band edge; pad sides for breathing room.
        rect = fitz.Rect(left, top + 2, right, bottom - 2) + (-4, 0, 4, 0)
        return rect & page_rect

    # Other figure captions on the page also block the band — otherwise a
    # second figure's region above this caption would be swallowed.
    other_captions = [c for c in _all_figure_captions(page) if c != caption]

    # Page-spanning elements (header rule, footer rule, running header
    # text, decorative divider) cut across columns. They block any band
    # that crosses them regardless of horizontal window.
    page_spanning: list[fitz.Rect] = [
        d["rect"]
        for d in page.get_drawings()
        if d["rect"].width >= page_rect.width * 0.6
    ]
    page_spanning += [b for b in text_blocks if b.width >= page_rect.width * 0.5]
    blockers = text_blocks + other_captions + page_spanning

    # A blocker only counts if it lives strictly inside our horizontal
    # window. A block that straddles two columns (cross-column equation,
    # full-width header) doesn't belong to either side and must not stop
    # the figure band — otherwise sub-panels in the same column get cut.
    # Page-spanning rules and other-figure captions remain blockers
    # because they were added separately above.
    def _in_window(b: fitz.Rect) -> bool:
        if b in page_spanning:
            return True  # already filtered at intent: blocks the band fully
        if b.x0 >= left - 2 and b.x1 <= right + 2:
            return True
        return False

    # Above the caption: walk up to the nearest blocker that lives within
    # our horizontal window. Caption itself is included in the clip, so
    # the band extends down to caption.y1.
    top_above = page_rect.y0
    above_blocker_is_other_caption = False
    for block in blockers:
        if block.y1 > caption.y0:
            continue
        if not _in_window(block):
            continue
        if block.y1 > top_above:
            top_above = block.y1
            # Is this blocker the description block of a different figure
            # caption? If so, the band above is owned by *that* figure,
            # not ours.
            above_blocker_is_other_caption = any(
                block.contains(c) or _rects_close(block, c) for c in other_captions
            )
    above = _band(top_above, caption.y1)

    # Below the caption: walk down to the nearest blocker. The caption is
    # the top of this band.
    bottom_below = page_rect.y1
    for block in blockers:
        if block.y0 < caption.y1:
            continue
        if not _in_window(block):
            continue
        if block.y0 < bottom_below:
            bottom_below = block.y0
    below = _band(caption.y0, bottom_below)

    # Figures conventionally sit above their caption. Prefer `above`,
    # unless `above` is butting right up against another figure's caption
    # block — that signals the caption is at the top of its column with
    # the figure stacked beneath it (Purcell 2.29). A loose neighbour-
    # caption (e.g. Purcell 1.11, where Fig 1.10's caption sits far up
    # the column) leaves plenty of room for our figure in between.
    def _height(r: fitz.Rect | None) -> float:
        return 0.0 if r is None else r.height

    crowded_above = above_blocker_is_other_caption and _height(above) < 100.0
    if crowded_above and below:
        return below
    if above and _height(above) >= min_height * 1.5:
        return above
    if below:
        return below
    return above


def match_table(
    caption: fitz.Rect,
    page: fitz.Page,
    page_rect: fitz.Rect,
    gap_threshold: float = 12.0,
) -> fitz.Rect:
    """Build a clip rect for a table caption.

    PDF tables are typically vector graphics (lines + text), not image objects.
    We approximate the table region by walking text blocks above the caption
    until a noticeable vertical gap separates the table from preceding text.
    """
    blocks = [
        fitz.Rect(b["bbox"])
        for b in page.get_text("dict")["blocks"]
        if b.get("type", 0) == 0 and fitz.Rect(b["bbox"]).y1 <= caption.y0
    ]
    blocks.sort(key=lambda r: r.y1, reverse=True)

    top = caption.y0
    prev_y0 = caption.y0
    for block in blocks:
        if prev_y0 - block.y1 > gap_threshold:
            break
        top = block.y0
        prev_y0 = block.y0

    left = min((b.x0 for b in blocks if b.y0 >= top), default=caption.x0)
    right = max((b.x1 for b in blocks if b.y0 >= top), default=caption.x1)
    left = min(left, caption.x0)
    right = max(right, caption.x1)

    rect = fitz.Rect(left, top, right, caption.y1) + (-6, -6, 6, 6)
    return rect & page_rect


def find_mask_rects(
    page: fitz.Page,
    caption: fitz.Rect,
    clip: fitz.Rect,
) -> list[fitz.Rect]:
    """Rectangles inside `clip` that should be painted white before saving
    the figure as a PNG.

    These are text blocks that fell inside the clip but don't belong to
    the figure: other figure captions, body prose paragraphs that bled in
    horizontally or vertically, and column body text outside the caption's
    own column. The caption block itself and short figure-internal labels
    (axis labels, sub-panel names, in-figure equations) are preserved.
    """
    cap_block = _caption_block_bbox(page, caption)
    other_caption_lines = [c for c in _all_figure_captions(page) if c != caption]
    other_caption_blocks = [_caption_block_bbox(page, c) for c in other_caption_lines]

    drawings = [
        d["rect"]
        for d in page.get_drawings()
        if d["rect"].width >= 5 and d["rect"].height >= 5
    ]

    def _is_figure_label(b: fitz.Rect, text: str) -> bool:
        return _is_figure_label_block(b, text, drawings)

    masks: list[fitz.Rect] = []
    for blk in page.get_text("dict")["blocks"]:
        if blk.get("type", 0) != 0:
            continue
        bbox = fitz.Rect(blk["bbox"])
        # Must intersect the clip to matter.
        intersect = bbox & clip
        if intersect.is_empty:
            continue
        # Keep our caption (title + description) intact.
        if (
            cap_block.contains(bbox)
            or bbox.contains(cap_block)
            or _rects_close(bbox, cap_block)
        ):
            continue

        # Whole-block decisions: another figure's caption block — mask.
        is_other_caption = any(
            ocb.contains(bbox) or bbox.contains(ocb) or _rects_close(bbox, ocb)
            for ocb in other_caption_blocks
        )
        text = "".join(
            s["text"] for line in blk.get("lines", []) for s in line.get("spans", [])
        ).strip()

        if is_other_caption:
            masks.append(bbox)
            continue
        # Figure-internal label — keep visible.
        if _is_figure_label(bbox, text):
            continue
        # Tiny standalone span (single word axis label) — keep.
        if bbox.width < 80 and len(text) < 10:
            continue
        # Anything else (body paragraph, cross-column equation): mask the
        # whole block. Returning the full bbox (not just the part inside
        # the clip) lets the caller paint past the clip edge so descenders
        # of partly-clipped lines don't leave a ghost.
        masks.append(bbox)
    return masks


def find_clip_for_caption(
    page: fitz.Page,
    kind: Kind,
    pattern: re.Pattern[str],
) -> fitz.Rect | None:
    """Locate a matching caption on `page` and return the clip rect for its
    associated figure/table region. Returns None if no caption matches or
    no candidate yields a clip.

    Multiple caption-like lines may match (e.g. when body prose starts with
    "Fig. 2.2." after a line break). We try each candidate in document order
    and return the first one that produces a non-empty clip.
    """
    captions = find_caption_bboxes(page, pattern)
    if not captions:
        return None
    page_rect = page.rect
    images = find_image_bboxes(page) if kind == "figure" else []
    for caption in captions:
        if kind == "figure":
            # Try column-aware paths first. They use caption position
            # within the page's text layout, so they reject images that
            # belong to a different figure on the same page (which the
            # nearest-image heuristic in `match_figure` would otherwise
            # latch onto).
            clip = match_figure_side_caption(caption, page, page_rect)
            if clip is None:
                clip = match_figure_by_layout(caption, page, page_rect)
            if clip is None:
                clip = match_figure(caption, images, page_rect)
        else:
            clip = match_table(caption, page, page_rect)
        if clip is not None and not clip.is_empty:
            # Make sure the caption's title + description ends up inside
            # the clip — figure-detection logic anchors on the caption's
            # first line bbox, but readers expect the description too.
            cap_block = _caption_block_bbox(page, caption)
            clip = clip | cap_block
            # Expand horizontally if the figure's drawing paths extend
            # beyond the column we picked. Common for left-column figures
            # whose artwork sticks into the gutter.
            if kind == "figure":
                clip = _expand_clip_to_drawings(clip, page, caption)
            clip = clip & page_rect
            return clip
    return None


def _expand_clip_to_drawings(
    clip: fitz.Rect,
    page: fitz.Page,
    caption: fitz.Rect,
) -> fitz.Rect:
    """Adjust `clip` to fit the figure's drawing paths:

    - Grow horizontally to cover paths that poke outside the column.
    - Trim the top so the clip starts at the first drawing (a tall band
      between header and figure becomes a tight band around the figure).

    Stops short of any other caption or body text on the page so the
    clip doesn't bleed into a neighbouring figure or paragraph.
    """
    # The figure occupies the part of the clip that isn't the caption.
    # When the caption sits at the top of the clip, the figure is below
    # it; when it sits at the bottom, the figure is above. Pick whichever
    # side has more vertical room.
    cap_block = _caption_block_bbox(page, caption)
    above_cap = max(0.0, cap_block.y0 - clip.y0)
    below_cap = max(0.0, clip.y1 - cap_block.y1)
    if below_cap > above_cap:
        figure_y_top = cap_block.y1
        figure_y_bottom = clip.y1
    else:
        figure_y_top = clip.y0
        figure_y_bottom = cap_block.y0

    # Forbidden x neighbours: other captions and body blocks whose y range
    # overlaps the figure band. `_body_blocks` already filters out figure
    # labels (in-figure equations, sub-panel headers, axis labels).
    body = _body_blocks(page, caption)
    other_captions = [c for c in _all_figure_captions(page) if c != caption]
    # Also collect `_body_blocks` for the *expansion* limits — when
    # deciding "how far down can we go", anything classified as a figure
    # label by `_body_blocks` is part of the figure and must NOT block
    # expansion. Items already excluded from `body` are exactly those.

    def _overlaps_y(r: fitz.Rect) -> bool:
        return r.y1 > figure_y_top and r.y0 < figure_y_bottom

    forbidden = [r for r in body + other_captions if _overlaps_y(r)]

    left_limit = page.rect.x0
    right_limit = page.rect.x1
    for r in forbidden:
        # Horizontal neighbours (don't overlap our clip in x): bound the
        # expansion before they begin.
        if r.x1 <= clip.x0 + 1 and r.x1 > left_limit:
            left_limit = r.x1
        if r.x0 >= clip.x1 - 1 and r.x0 < right_limit:
            right_limit = r.x0

    # Drawings inside the figure's y band that contribute to its bbox.
    # First pass uses the original clip x range to find drawings whose
    # x falls roughly inside it.
    in_band_drawings = [
        d["rect"]
        for d in page.get_drawings()
        if (d["rect"].width >= 5 and d["rect"].height >= 5 and _overlaps_y(d["rect"]))
    ]
    if not in_band_drawings:
        return clip

    new_left = clip.x0
    new_right = clip.x1
    for r in in_band_drawings:
        if r.x0 < new_left and r.x0 >= left_limit:
            new_left = r.x0
        if r.x1 > new_right and r.x1 <= right_limit:
            new_right = r.x1

    drawings_in_clip = [
        r for r in in_band_drawings if r.x1 > new_left and r.x0 < new_right
    ]
    new_top = clip.y0
    new_bottom = clip.y1
    figure_above_caption = figure_y_top == clip.y0

    if drawings_in_clip:
        if figure_above_caption:
            # Trim the top: if all the figure drawings sit well below the
            # band's top, the empty space above is just margin and should
            # be cut.
            first_y = min(r.y0 for r in drawings_in_clip)
            if first_y - clip.y0 > 40.0:
                new_top = first_y - 8.0
        else:
            # Figure is below the caption: expand bottom to the last
            # drawing so cross-column composite figures aren't truncated.
            last_y = max(r.y1 for r in drawings_in_clip)
            if last_y > clip.y1:
                # Don't run past the next forbidden block below the clip.
                blockers_below = [
                    r for r in body + other_captions if r.y0 >= clip.y1 - 1
                ]
                cap_y_below = (
                    min(b.y0 for b in blockers_below)
                    if blockers_below
                    else page.rect.y1
                )
                new_bottom = min(last_y + 8.0, cap_y_below)

    # Pass two: figure labels (sub-panel names like "(a)", in-figure
    # equations, axis labels) often sit just outside the drawing bbox
    # and aren't body text. Pull the clip out further to include any
    # text block that's wholly inside the [new_top, new_bottom] band and
    # not part of body prose / another caption.
    figure_label_blocks: list[fitz.Rect] = []
    cap_block = _caption_block_bbox(page, caption)
    band_top = new_top
    band_bottom = new_bottom
    for blk in page.get_text("dict")["blocks"]:
        if blk.get("type", 0) != 0:
            continue
        bbox = fitz.Rect(blk["bbox"])
        if bbox.y0 < band_top - 1 or bbox.y1 > band_bottom + 1:
            continue
        # Skip our own caption and any other figure captions / their
        # description blocks.
        if cap_block.contains(bbox) or _rects_close(bbox, cap_block):
            continue
        if any(_rects_close(bbox, c) or c.contains(bbox) for c in other_captions):
            continue
        text = "".join(
            s["text"] for line in blk.get("lines", []) for s in line.get("spans", [])
        ).strip()
        # Body prose paragraphs are wide and packed with text — skip.
        if bbox.width >= 250 and len(text) >= 80:
            continue
        # Anything else that's wholly inside the band counts as a
        # potential figure label. (Includes sub-panel names, equations,
        # axis labels.) We don't even need the figure-label heuristic
        # here because body prose was already excluded.
        figure_label_blocks.append(bbox)

    for r in figure_label_blocks:
        if r.x0 < new_left and r.x0 >= left_limit:
            new_left = r.x0
        if r.x1 > new_right and r.x1 <= right_limit:
            new_right = r.x1
        if not figure_above_caption and r.y1 > new_bottom:
            new_bottom = min(r.y1 + 4.0, page.rect.y1)
        if figure_above_caption and r.y0 < new_top:
            new_top = max(r.y0 - 4.0, page.rect.y0)

    return fitz.Rect(new_left, new_top, new_right, new_bottom)
