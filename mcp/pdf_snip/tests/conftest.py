"""Synthetic PDF fixtures so tests don't need on-disk sample files."""

from __future__ import annotations

from pathlib import Path

import fitz
import pytest


def _png_bytes(
    width: int = 200, height: int = 150, color: tuple[int, int, int] = (180, 200, 230)
) -> bytes:
    """Build a tiny solid-color PNG using PyMuPDF itself (no Pillow dep)."""
    pix = fitz.Pixmap(fitz.csRGB, fitz.IRect(0, 0, width, height))
    pix.set_rect(pix.irect, color)
    return pix.tobytes("png")


@pytest.fixture
def synthetic_pdf(tmp_path: Path) -> Path:
    """A 2-page PDF: page 1 has Figure 1 with image; page 2 has a Table 1
    region built from text blocks (no image)."""
    doc = fitz.open()

    # Page 1: an embedded image with a caption directly below.
    page1 = doc.new_page(width=600, height=800)
    img_rect = fitz.Rect(100, 100, 400, 300)
    page1.insert_image(img_rect, stream=_png_bytes())
    page1.insert_text(
        (100, 320),
        "Figure 1: synthetic test image",
        fontsize=11,
    )

    # Page 2: a fake table built from a few text rows, with a caption below it.
    page2 = doc.new_page(width=600, height=800)
    page2.insert_text(
        (100, 100), "Some preceding paragraph that is not the table.", fontsize=10
    )
    # Gap, then table-like rows.
    for i, row in enumerate(["A | B | C", "1 | 2 | 3", "4 | 5 | 6"]):
        page2.insert_text((120, 200 + i * 18), row, fontsize=10)
    page2.insert_text((100, 280), "Table 1: synthetic table", fontsize=11)

    out = tmp_path / "synthetic.pdf"
    doc.save(out)
    doc.close()
    return out


@pytest.fixture
def vector_figure_pdf(tmp_path: Path) -> Path:
    """A PDF where two figures share one caption row but have no image
    objects (mimicking vector-only figures). Body text frames the empty
    region above the captions."""
    doc = fitz.open()
    page = doc.new_page(width=600, height=800)
    # Top-of-page header.
    page.insert_text((50, 40), "Chapter 1  Section header  page 35", fontsize=10)
    # Empty band y=50..280 — this is where the figures conceptually live.
    # Two captions side by side at y=290.
    page.insert_text((100, 290), "FIGURE 1.31", fontsize=11)
    page.insert_text((400, 290), "FIGURE 1.32", fontsize=11)
    # Body text below the captions.
    page.insert_text((50, 330), "Body paragraph that follows the figures.", fontsize=10)
    out = tmp_path / "vector_figure.pdf"
    doc.save(out)
    doc.close()
    return out


@pytest.fixture
def chinese_caption_pdf(tmp_path: Path) -> Path:
    """A PDF whose figure caption is in Chinese."""
    doc = fitz.open()
    page = doc.new_page(width=600, height=800)
    img_rect = fitz.Rect(100, 100, 400, 300)
    page.insert_image(img_rect, stream=_png_bytes())
    # Chinese text needs a CJK font; PyMuPDF ships 'china-s' built-in.
    page.insert_text((100, 320), "圖 2-1 中文標題範例", fontsize=12, fontname="china-s")
    out = tmp_path / "chinese.pdf"
    doc.save(out)
    doc.close()
    return out
