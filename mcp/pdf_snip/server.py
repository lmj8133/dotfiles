"""MCP server exposing a single tool that snips a region of a PDF page
to a PNG file.

The tool is human-in-the-loop. Given a PDF and a caption hint (e.g.
"Figure 2.29", "Table 1", or even just a phrase that appears near the
desired region), a heuristic in `core.py` proposes a candidate page and
bounding box. A browser GUI then lets the user adjust the crop, mask
out unwanted content with erasers, and confirm. The resulting PNG is
written to the requested output path.

Despite the original framing of the heuristic around "figures" (it
parses caption identifiers like "Figure 3"), the GUI lets the user
draw any rectangle on any page, so this works for tables, equations,
flowcharts, or any region the user can see in the PDF.
"""

from __future__ import annotations

import sys
from pathlib import Path

import fitz
from mcp.server.fastmcp import FastMCP

from core import find_caption_bboxes, find_clip_for_caption, normalize_query
from gui import ensure_server_running, get_queue

mcp = FastMCP("pdf-snip")


def _heuristic_suggestion(
    doc: fitz.Document,
    pattern,
    kind: str,
) -> tuple[int, fitz.Rect | None]:
    """Run the heuristic to locate the page and a candidate clip rect.

    Returns (page_index, clip_or_None). If the heuristic finds nothing
    on any page, returns (0, None) so the GUI starts on page 1 with a
    blank box for the user to draw manually.
    """
    for page_index in range(doc.page_count):
        page = doc[page_index]
        clip = find_clip_for_caption(page, kind, pattern)
        if clip is not None and not clip.is_empty:
            return page_index, clip
        # If the caption is on this page but no bbox could be inferred,
        # at least anchor the GUI to this page.
        captions = find_caption_bboxes(page, pattern) if kind == "figure" else []
        if captions:
            return page_index, None
    return 0, None


# Note: this module deliberately keeps the internal `figure_id` /
# `find_caption_bboxes` naming inherited from the heuristic — the
# heuristic genuinely is about caption text. The user-facing name of
# the parameter, however, is `caption_hint`, since the GUI lets the
# user pick any region (not necessarily a captioned figure).


@mcp.tool()
def pdf_snip(
    pdf_path: str,
    caption_hint: str,
    output_path: str,
    review_dpi: int = 150,
    output_dpi: int = 200,
    timeout_s: float = 1800.0,
) -> str:
    """Snip a rectangular region of a PDF page and save it as a PNG.

    HUMAN-IN-THE-LOOP — each call sends the page to a browser GUI
    and BLOCKS until the user manually adjusts the crop box and
    clicks Confirm (typical wall time: 30-90 seconds). Do not call
    this tool in bulk loops, retries, or speculative attempts. Treat
    each call as interrupting the user.

    USE THIS WHEN:
      - The user has asked for a figure/table/diagram from a PDF and
        you need an image file to embed in their notes or feed back
        to them.
      - The user references a specific PDF region by caption (e.g.
        "Figure 2.29 from purcell-morin", "the table on page 5").

    DO NOT USE WHEN:
      - You only need the *text* near a figure (use a PDF text tool).
      - You're guessing whether a figure exists — confirm with the
        user first.
      - You haven't been given an output_path yet — ask the user
        where they want the PNG saved.

    HOW IT WORKS:
      1. A heuristic tries to locate the page from `caption_hint`
         (e.g. "Figure 2.29") and proposes a bounding box.
      2. The browser GUI shows that page with a suggested box.
      3. The user can navigate to a different page, drag the box,
         add eraser rectangles to mask unrelated content, then click
         Confirm.
      4. The cropped PNG is written to `output_path`.

    The GUI runs on localhost — http://127.0.0.1:7860/ by default
    (port configurable via the PDF_SNIP_PORT env var). A browser tab
    is opened automatically ONLY when no GUI tab is currently
    connected; an already-open tab — including one left over from a
    previous session — is reused. When you call this tool, tell the
    user the GUI URL in your message so they can switch to the tab
    (or open the URL themselves if nothing pops up). If the default
    port was taken (e.g. a second concurrent session), the server
    falls back to a nearby port and opens a tab there automatically;
    the actual URL is always written to /tmp/pdf_snip_url.txt.
    Setting PDF_SNIP_AUTO_OPEN=0 disables automatic opening entirely.

    Args:
        pdf_path: Absolute path to the source PDF. Must already
            exist; this tool does not download or fetch PDFs.
        caption_hint: A caption-style identifier such as "Figure 3",
            "Fig. 2-1", "圖 3", or "Table 1". Used by the heuristic
            to pick a starting page. If you don't know the exact
            caption, pass the closest guess — the user can navigate
            from the GUI.
        output_path: Absolute path where the cropped PNG will be
            written. Parent directories are created. Existing files
            are overwritten.
        review_dpi: DPI for the review render shown in the GUI.
            Default 150. Raise for very small figures.
        output_dpi: DPI for the final saved PNG. Default 200
            (screen). Use 300 for print-quality.
        timeout_s: Seconds to wait for the user to confirm before
            raising. Default 1800 (30 min).

    Returns:
        Absolute path of the saved PNG file as a string.

    Raises:
        ValueError: pdf_path doesn't exist, isn't a PDF, or the
            caption_hint is unparseable.
        TimeoutError: User didn't confirm within timeout_s.
        RuntimeError: User cancelled in the GUI.

    Example:
        >>> pdf_snip(
        ...     pdf_path="/path/to/textbook.pdf",
        ...     caption_hint="Figure 2.29",
        ...     output_path="/notes/figures/fig_2_29.png",
        ... )
        '/notes/figures/fig_2_29.png'
    """
    pdf = Path(pdf_path).expanduser().resolve()
    if not pdf.is_file():
        raise ValueError(f"PDF not found: {pdf}")
    if pdf.suffix.lower() != ".pdf":
        raise ValueError(f"Not a PDF file: {pdf}")

    parsed = normalize_query(caption_hint)
    if parsed is None:
        raise ValueError(
            f"Cannot parse caption hint '{caption_hint}'. "
            "Expected forms like 'Figure 3', 'Fig. 2-1', '圖 3', 'Table 1'."
        )
    kind, _number, pattern = parsed

    doc = fitz.open(pdf)
    try:
        if doc.needs_pass:
            raise ValueError(f"PDF is password-protected: {pdf}")
        page_index, clip = _heuristic_suggestion(doc, pattern, kind)
        suggested = (clip.x0, clip.y0, clip.x1, clip.y1) if clip else None
    finally:
        doc.close()

    url = ensure_server_running()
    print(
        f"[pdf_snip] open {url} to review {caption_hint}", file=sys.stderr, flush=True
    )

    queue = get_queue()
    try:
        job = queue.submit_job(
            pdf_path=str(pdf),
            figure_id=caption_hint,
            page_index=page_index,
            suggested_bbox_pt=suggested,
            render_dpi=review_dpi,
            timeout_s=timeout_s,
        )
    except TimeoutError as exc:
        # Most likely the user never saw the GUI; make the URL part of
        # the error so the next attempt can point them at it.
        raise TimeoutError(f"{exc} — GUI URL: {url}") from exc

    # Render the final PNG using the user's confirmed bbox + erasers.
    out_path = Path(output_path).expanduser().resolve()
    out_path.parent.mkdir(parents=True, exist_ok=True)

    doc = fitz.open(pdf)
    try:
        # The user may have navigated to a different page in the GUI;
        # fall back to the heuristic's page only if they didn't override.
        # `0 or x` is `x`, so `result_page_index or page_index` would
        # silently swap page 1 for the heuristic — use an explicit None
        # check.
        final_page_index = (
            job.result_page_index if job.result_page_index is not None else page_index
        )
        page = doc[final_page_index]
        # Apply erasers as filled rectangles on the page before rendering.
        for er in job.result_erasers_pt:
            rect = fitz.Rect(er["x0"], er["y0"], er["x1"], er["y1"])
            color = _hex_to_rgb01(er.get("color", "#ffffff"))
            page.draw_rect(rect, color=None, fill=color, width=0, overlay=True)
        bbox = job.result_bbox_pt
        if bbox is None:
            raise RuntimeError("user confirmed without a bbox")
        clip = fitz.Rect(*bbox) & page.rect
        if clip.is_empty:
            raise RuntimeError("confirmed bbox is empty")
        pix = page.get_pixmap(clip=clip, dpi=output_dpi)
        pix.save(out_path)
    finally:
        doc.close()
    return str(out_path)


def _hex_to_rgb01(hex_str: str) -> tuple[float, float, float]:
    s = hex_str.lstrip("#")
    if len(s) == 3:
        s = "".join(c * 2 for c in s)
    r = int(s[0:2], 16) / 255.0
    g = int(s[2:4], 16) / 255.0
    b = int(s[4:6], 16) / 255.0
    return (r, g, b)


if __name__ == "__main__":
    mcp.run()
