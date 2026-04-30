"""Unit tests for core.py — caption parsing and clip-rect computation."""

from __future__ import annotations

from pathlib import Path

import fitz

from core import (
    find_caption_bboxes,
    find_clip_for_caption,
    find_image_bboxes,
    normalize_query,
)


class TestNormalizeQuery:
    def test_english_figure(self):
        result = normalize_query("Figure 3")
        assert result is not None
        kind, num, pattern = result
        assert kind == "figure"
        assert num == "3"
        assert pattern.search("Figure 3: caption text")

    def test_fig_dot_variant(self):
        result = normalize_query("Fig. 2-1")
        assert result is not None
        kind, num, _ = result
        assert kind == "figure"
        assert num == "2-1"

    def test_lowercase(self):
        result = normalize_query("fig 5")
        assert result is not None
        assert result[0] == "figure"
        assert result[1] == "5"

    def test_chinese_figure(self):
        result = normalize_query("圖 3")
        assert result is not None
        kind, num, pattern = result
        assert kind == "figure"
        assert num == "3"
        assert pattern.search("圖 3 中文")

    def test_chinese_figure_no_space(self):
        result = normalize_query("圖3")
        assert result is not None
        assert result[0] == "figure"
        assert result[1] == "3"

    def test_table_english(self):
        result = normalize_query("Table 1")
        assert result is not None
        assert result[0] == "table"
        assert result[1] == "1"

    def test_table_chinese(self):
        result = normalize_query("表 2")
        assert result is not None
        assert result[0] == "table"
        assert result[1] == "2"

    def test_hierarchical_number(self):
        result = normalize_query("Figure 2-1")
        assert result is not None
        assert result[1] == "2-1"

    def test_pattern_does_not_match_longer_number(self):
        # When asking for "Figure 3", we must not match "Figure 31".
        result = normalize_query("Figure 3")
        assert result is not None
        _, _, pattern = result
        assert not pattern.search("Figure 31: foo")
        assert pattern.search("Figure 3: bar")

    def test_pattern_tolerates_zero_padding(self):
        result = normalize_query("Figure 3")
        assert result is not None
        _, _, pattern = result
        assert pattern.search("Figure 03: foo")

    def test_unparseable(self):
        assert normalize_query("hello world") is None
        assert normalize_query("") is None


class TestFindOnSyntheticPdf:
    def test_caption_found_on_page1(self, synthetic_pdf: Path):
        result = normalize_query("Figure 1")
        assert result is not None
        _, _, pattern = result
        doc = fitz.open(synthetic_pdf)
        page = doc[0]
        captions = find_caption_bboxes(page, pattern)
        assert len(captions) == 1
        # Caption should sit below the image we drew at y=100..300.
        assert captions[0].y0 > 300
        doc.close()

    def test_image_bbox_found(self, synthetic_pdf: Path):
        doc = fitz.open(synthetic_pdf)
        page = doc[0]
        images = find_image_bboxes(page)
        assert len(images) == 1
        # PyMuPDF preserves aspect ratio inside our target rect (100..400),
        # so the actual bbox is centered horizontally — just check it sits
        # inside the target with reasonable size.
        img = images[0]
        assert 100 <= img.x0 < 200
        assert 300 < img.x1 <= 400
        assert img.width > 200
        doc.close()

    def test_clip_for_figure_covers_image(self, synthetic_pdf: Path):
        result = normalize_query("Figure 1")
        assert result is not None
        kind, _, pattern = result
        doc = fitz.open(synthetic_pdf)
        page = doc[0]
        clip = find_clip_for_caption(page, kind, pattern)
        assert clip is not None
        # Clip must contain the actual image. PyMuPDF rescales to preserve
        # aspect ratio, so the image lives somewhere inside (100, 100, 400, 300).
        images = find_image_bboxes(page)
        img = images[0]
        assert clip.x0 <= img.x0 and clip.x1 >= img.x1
        assert clip.y0 <= img.y0 and clip.y1 >= img.y1
        doc.close()

    def test_clip_for_table_returns_rect(self, synthetic_pdf: Path):
        result = normalize_query("Table 1")
        assert result is not None
        kind, _, pattern = result
        doc = fitz.open(synthetic_pdf)
        page = doc[1]
        clip = find_clip_for_caption(page, kind, pattern)
        assert clip is not None
        # Table region should sit above the caption (y=280) and span the rows.
        assert clip.y0 < 280
        assert clip.y1 >= 280
        doc.close()

    def test_caption_not_found_returns_none(self, synthetic_pdf: Path):
        result = normalize_query("Figure 99")
        assert result is not None
        kind, _, pattern = result
        doc = fitz.open(synthetic_pdf)
        page = doc[0]
        clip = find_clip_for_caption(page, kind, pattern)
        assert clip is None
        doc.close()


class TestCaptionRejectsInlineMentions:
    def test_inline_mention_is_not_a_caption(self, tmp_path):
        doc = fitz.open()
        page = doc.new_page(width=600, height=800)
        page.insert_text((50, 100), "See Fig. 1.31 for the flow boundary.", fontsize=11)
        page.insert_text((50, 300), "FIGURE 1.31", fontsize=11)
        out = tmp_path / "inline.pdf"
        doc.save(out)
        doc.close()

        result = normalize_query("Figure 1.31")
        assert result is not None
        _, _, pattern = result
        d = fitz.open(out)
        captions = find_caption_bboxes(d[0], pattern)
        # Only the standalone caption line should match.
        assert len(captions) == 1
        assert captions[0].y0 > 250
        d.close()


class TestVectorFigureFallback:
    def test_fallback_clips_above_caption(self, vector_figure_pdf: Path):
        result = normalize_query("Figure 1.31")
        assert result is not None
        kind, _, pattern = result
        doc = fitz.open(vector_figure_pdf)
        page = doc[0]
        clip = find_clip_for_caption(page, kind, pattern)
        assert clip is not None
        # Figure region must sit below the header (y~40, with padding slack)
        # and include the caption itself (caption.y1 ~ 293).
        assert clip.y0 >= 35
        assert clip.y1 >= 290
        # Right edge must stop before the sibling "Figure 1.32" caption at x=400.
        assert clip.x1 <= 405
        # Left edge anchors to the page's body margin, well before x=400.
        assert clip.x0 < 200
        doc.close()

    def test_fallback_picks_correct_sibling(self, vector_figure_pdf: Path):
        # Asking for 1.32 should clip the right half: left edge stops just
        # past the Figure 1.31 caption (x1 ~ 166), right edge to body margin.
        result = normalize_query("Figure 1.32")
        assert result is not None
        kind, _, pattern = result
        doc = fitz.open(vector_figure_pdf)
        page = doc[0]
        clip = find_clip_for_caption(page, kind, pattern)
        assert clip is not None
        # Left edge sits past the sibling caption, not at the page edge.
        assert clip.x0 >= 150
        # Right edge anchors to body margin, well past the caption at x=400.
        assert clip.x1 > 400
        doc.close()


class TestChineseCaption:
    def test_chinese_figure_clip(self, chinese_caption_pdf: Path):
        result = normalize_query("圖 2-1")
        assert result is not None
        kind, _, pattern = result
        doc = fitz.open(chinese_caption_pdf)
        page = doc[0]
        clip = find_clip_for_caption(page, kind, pattern)
        assert clip is not None
        images = find_image_bboxes(page)
        img = images[0]
        assert clip.x0 <= img.x0 and clip.x1 >= img.x1
        doc.close()
