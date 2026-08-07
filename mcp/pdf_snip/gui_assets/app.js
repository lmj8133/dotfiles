/* cut_figure review GUI
 * Connects to the HTTP backend (gui.py), polls for jobs, drives a
 * Cropper.js bbox plus an eraser overlay, and POSTs the result back.
 *
 * Coordinate systems:
 *   - PDF "pt": what the backend wants. 1 pt = 1/72 inch.
 *   - Image "px": pixels of the rendered page image at job.render_dpi.
 *   - CSS "px": display pixels in the DOM. Cropper handles this.
 *
 * The page image dimensions in pt vs px give us the scale factor.
 * Erasers store their position in image pixels (matches the page-image
 * element coordinate system) so they overlay correctly while you scroll
 * the cropper. We translate to pt only when submitting.
 */

(() => {
  const statusText = document.getElementById('status-text');
  const app = document.getElementById('app');
  const pdfNameEl = document.getElementById('pdf-name');
  const figureIdEl = document.getElementById('figure-id');
  const pageInput = document.getElementById('page-input');
  const totalPagesEl = document.getElementById('total-pages');
  const prevBtn = document.getElementById('prev-page');
  const nextBtn = document.getElementById('next-page');
  const gotoBtn = document.getElementById('goto-page');
  const addEraserBtn = document.getElementById('add-eraser');
  const toggleDragBtn = document.getElementById('toggle-drag-mode');
  const eraserColor = document.getElementById('eraser-color');
  const pageImage = document.getElementById('page-image');
  const eraserLayer = document.getElementById('eraser-layer');
  const previewEl = document.getElementById('preview');
  const resetBtn = document.getElementById('reset-bbox');
  const confirmBtn = document.getElementById('confirm');
  const cancelBtn = document.getElementById('cancel');
  const canvasContainer = document.getElementById('canvas-container');

  let cropper = null;
  let job = null;          // current job from /poll
  let currentPage = 0;     // 0-based
  let imgWPx = 0;
  let imgHPx = 0;
  let pageWPt = 0;
  let pageHPt = 0;
  let lastPolledJobId = 0;
  let serverEpoch = null;  // identifies the server process; see pollLoop
  let erasers = [];        // {id, x, y, w, h, color}  -- coords in image px
  let nextEraserId = 1;

  function findEraserIndex(id) {
    return erasers.findIndex(er => er.id === id);
  }

  // ---------- polling ----------

  async function pollLoop() {
    while (true) {
      try {
        const r = await fetch(
          `/poll?since=${lastPolledJobId}&timeout=25&epoch=${serverEpoch || ''}`);
        if (!r.ok) {
          await sleep(2000);
          continue;
        }
        const data = await r.json();
        if (data.epoch && data.epoch !== serverEpoch) {
          // New server process (MCP session restarted): job ids were
          // reset, so our watermark is stale. The server already treats
          // the mismatched epoch as since=0; resync to match.
          serverEpoch = data.epoch;
          lastPolledJobId = 0;
        }
        if (data.job) {
          loadJob(data.job);
          lastPolledJobId = data.job.job_id;
        }
      } catch (e) {
        console.warn('poll error', e);
        await sleep(2000);
      }
    }
  }

  function sleep(ms) {
    return new Promise(r => setTimeout(r, ms));
  }

  // ---------- load job ----------

  function loadJob(j) {
    job = j;
    erasers = [];
    currentPage = j.page_index;
    statusText.textContent =
      `Reviewing job #${j.job_id} — confirm to return result to MCP`;
    pdfNameEl.textContent = j.pdf_name;
    figureIdEl.textContent = j.figure_id;
    totalPagesEl.textContent = j.total_pages;
    pageInput.value = currentPage + 1;
    pageInput.max = j.total_pages;
    app.hidden = false;
    renderPage(currentPage, /*useSuggested=*/true);
  }

  async function renderPage(pageIndex, useSuggested) {
    if (!job) return;
    currentPage = pageIndex;
    pageInput.value = pageIndex + 1;
    const url =
      `/render?job=${job.job_id}&page=${pageIndex}&dpi=${job.render_dpi}` +
      `&epoch=${serverEpoch}`;
    const resp = await fetch(url);
    if (!resp.ok) {
      alert(`render failed: ${resp.status}`);
      return;
    }
    pageWPt = parseFloat(resp.headers.get('X-Page-Width-Pt'));
    pageHPt = parseFloat(resp.headers.get('X-Page-Height-Pt'));
    imgWPx = parseInt(resp.headers.get('X-Image-Width-Px'), 10);
    imgHPx = parseInt(resp.headers.get('X-Image-Height-Px'), 10);
    const blob = await resp.blob();
    const objUrl = URL.createObjectURL(blob);

    // Reset cropper before swapping image source.
    if (cropper) { cropper.destroy(); cropper = null; }
    erasers = [];
    redrawErasers();

    pageImage.onload = () => {
      const suggested = useSuggested && pageIndex === job.page_index
        ? suggestedBboxImagePx() : null;
      initCropper(suggested || defaultCenteredBoxPx());
    };
    pageImage.src = objUrl;
  }

  function suggestedBboxImagePx() {
    if (!job.suggested_bbox_pt) return null;
    const [x0, y0, x1, y1] = job.suggested_bbox_pt;
    const sx = imgWPx / pageWPt;
    const sy = imgHPx / pageHPt;
    return {
      left: x0 * sx,
      top: y0 * sy,
      width: (x1 - x0) * sx,
      height: (y1 - y0) * sy,
    };
  }

  function defaultCenteredBoxPx() {
    const w = imgWPx * 0.6;
    const h = imgHPx * 0.6;
    return {
      left: (imgWPx - w) / 2,
      top: (imgHPx - h) / 2,
      width: w,
      height: h,
    };
  }

  function initCropper(initialBoxPx) {
    cropper = new Cropper(pageImage, {
      viewMode: 1,
      autoCrop: true,
      autoCropArea: 1,
      background: false,
      movable: true,
      zoomable: true,
      zoomOnWheel: true,
      wheelZoomRatio: 0.1,
      toggleDragModeOnDblclick: false,
      dragMode: 'crop',
      ready() {
        if (initialBoxPx) {
          this.cropper.setData({
            x: initialBoxPx.left,
            y: initialBoxPx.top,
            width: initialBoxPx.width,
            height: initialBoxPx.height,
          });
        }
        toggleDragBtn.dataset.mode = 'crop';
        toggleDragBtn.textContent = 'Draw';
        // Update preview whenever the crop box changes.
        renderPreview();
      },
      crop() {
        renderPreview();
      },
    });
  }

  function getCropImagePx() {
    if (!cropper) return null;
    const d = cropper.getData(/*rounded=*/false);
    return { x: d.x, y: d.y, width: d.width, height: d.height };
  }

  // ---------- erasers ----------

  function addEraser() {
    if (!cropper) return;
    const c = getCropImagePx();
    if (!c) return;
    // Place a default eraser inside the crop box, centered, ~20% of crop size.
    const w = Math.max(40, c.width * 0.2);
    const h = Math.max(20, c.height * 0.1);
    const x = c.x + (c.width - w) / 2;
    const y = c.y + (c.height - h) / 2;
    erasers.push({ id: nextEraserId++, x, y, w, h, color: eraserColor.value });
    redrawErasers();
    renderPreview();
  }

  function redrawErasers() {
    eraserLayer.innerHTML = '';
    if (!cropper) return;
    erasers.forEach((er) => {
      const el = document.createElement('div');
      el.className = 'eraser';
      el.dataset.eraserId = String(er.id);
      el.style.background = er.color;
      eraserLayer.appendChild(el);
      attachEraserHandlers(el, er.id);
      positionEraser(el, er);
    });
  }

  function positionEraser(el, er) {
    // Convert image px to CSS px relative to canvas-container.
    const cssBox = imagePxToCssBox(er.x, er.y, er.w, er.h);
    if (!cssBox) {
      el.style.display = 'none';
      return;
    }
    el.style.display = 'block';
    el.style.left = cssBox.left + 'px';
    el.style.top = cssBox.top + 'px';
    el.style.width = cssBox.width + 'px';
    el.style.height = cssBox.height + 'px';
  }

  function imagePxToCssBox(x, y, w, h) {
    if (!cropper) return null;
    const cb = cropper.getCanvasData(); // image position+size in CSS px relative to container
    if (!cb || cb.naturalWidth === 0) return null;
    const sx = cb.width / cb.naturalWidth;
    const sy = cb.height / cb.naturalHeight;
    return {
      left: cb.left + x * sx,
      top: cb.top + y * sy,
      width: w * sx,
      height: h * sy,
    };
  }

  function cssDeltaToImagePx(dxCss, dyCss) {
    const cb = cropper.getCanvasData();
    if (!cb || cb.naturalWidth === 0) return [0, 0];
    return [
      dxCss * (cb.naturalWidth / cb.width),
      dyCss * (cb.naturalHeight / cb.height),
    ];
  }

  function attachEraserHandlers(el, eraserId) {
    const handles = ['tl', 'tr', 'bl', 'br'];
    handles.forEach(h => {
      const handle = document.createElement('div');
      handle.className = `resize-handle ${h}`;
      handle.dataset.handle = h;
      el.appendChild(handle);
    });
    const del = document.createElement('div');
    del.className = 'delete-btn';
    del.textContent = '×';
    el.appendChild(del);
    del.addEventListener('mousedown', (e) => e.stopPropagation());
    del.addEventListener('click', (e) => {
      e.stopPropagation();
      const idx = findEraserIndex(eraserId);
      if (idx < 0) return;
      erasers.splice(idx, 1);
      redrawErasers();
      renderPreview();
    });

    let dragMode = null; // 'move' | 'tl' | ...
    let startX = 0, startY = 0;
    let startEraser = null;

    el.addEventListener('mousedown', (e) => {
      e.stopPropagation();
      const idx = findEraserIndex(eraserId);
      if (idx < 0) return;
      const handle = e.target.dataset.handle;
      dragMode = handle || 'move';
      startX = e.clientX;
      startY = e.clientY;
      startEraser = { ...erasers[idx] };
      const onMove = (ev) => onDrag(ev);
      const onUp = () => {
        document.removeEventListener('mousemove', onMove);
        document.removeEventListener('mouseup', onUp);
        dragMode = null;
      };
      document.addEventListener('mousemove', onMove);
      document.addEventListener('mouseup', onUp);
    });

    function onDrag(ev) {
      if (!dragMode) return;
      const idx = findEraserIndex(eraserId);
      if (idx < 0) return;
      const dxCss = ev.clientX - startX;
      const dyCss = ev.clientY - startY;
      const [dx, dy] = cssDeltaToImagePx(dxCss, dyCss);
      const e = erasers[idx];
      if (dragMode === 'move') {
        e.x = startEraser.x + dx;
        e.y = startEraser.y + dy;
      } else if (dragMode === 'tl') {
        e.x = startEraser.x + dx;
        e.y = startEraser.y + dy;
        e.w = startEraser.w - dx;
        e.h = startEraser.h - dy;
      } else if (dragMode === 'tr') {
        e.y = startEraser.y + dy;
        e.w = startEraser.w + dx;
        e.h = startEraser.h - dy;
      } else if (dragMode === 'bl') {
        e.x = startEraser.x + dx;
        e.w = startEraser.w - dx;
        e.h = startEraser.h + dy;
      } else if (dragMode === 'br') {
        e.w = startEraser.w + dx;
        e.h = startEraser.h + dy;
      }
      // Clamp.
      if (e.w < 4) e.w = 4;
      if (e.h < 4) e.h = 4;
      positionEraser(el, e);
      renderPreview();
    }
  }

  // Reposition all erasers on cropper canvas changes (zoom/pan).
  function refreshEraserPositions() {
    Array.from(eraserLayer.children).forEach((el) => {
      const id = parseInt(el.dataset.eraserId, 10);
      const idx = findEraserIndex(id);
      if (idx >= 0) positionEraser(el, erasers[idx]);
    });
  }

  // ---------- preview ----------

  function renderPreview() {
    if (!cropper) return;
    refreshEraserPositions();
    const c = getCropImagePx();
    if (!c) return;
    // Draw the crop area onto a canvas, then paint erasers on top.
    // Cropper.js gives us a canvas via getCroppedCanvas, but eraser
    // coordinates are in image-px relative to the full image, so we
    // composite manually using getCroppedCanvas + drawImage.
    const canvas = cropper.getCroppedCanvas({ imageSmoothingQuality: 'medium' });
    if (!canvas) return;
    const ctx = canvas.getContext('2d');
    erasers.forEach(er => {
      // er.x/y/w/h are in full-image px; the crop canvas origin maps to (c.x, c.y).
      const ex = er.x - c.x;
      const ey = er.y - c.y;
      ctx.fillStyle = er.color;
      ctx.fillRect(ex, ey, er.w, er.h);
    });
    // Render into preview as a scaled image.
    previewEl.innerHTML = '';
    const img = document.createElement('img');
    img.src = canvas.toDataURL('image/png');
    img.style.maxWidth = '100%';
    img.style.maxHeight = '100%';
    img.style.objectFit = 'contain';
    previewEl.appendChild(img);
  }

  // ---------- actions ----------

  async function confirm() {
    if (!job || !cropper) return;
    const c = getCropImagePx();
    if (!c) return;
    const sx = pageWPt / imgWPx;
    const sy = pageHPt / imgHPx;
    const bboxPt = [
      c.x * sx,
      c.y * sy,
      (c.x + c.width) * sx,
      (c.y + c.height) * sy,
    ];
    const erasersPt = erasers.map(er => ({
      x0: er.x * sx,
      y0: er.y * sy,
      x1: (er.x + er.w) * sx,
      y1: (er.y + er.h) * sy,
      color: er.color,
    }));
    const r = await fetch(`/submit?job=${job.job_id}&epoch=${serverEpoch}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        bbox_pt: bboxPt,
        erasers_pt: erasersPt,
        page_index: currentPage,
      }),
    });
    if (!r.ok) {
      alert(`submit failed: ${r.status}`);
      return;
    }
    statusText.textContent = `Saved job #${job.job_id}. Waiting for next request…`;
    job = null;
    app.hidden = true;
  }

  async function cancel() {
    if (!job) return;
    if (!confirm_('Cancel this cut request? The MCP call will fail.')) return;
    await fetch(`/cancel?job=${job.job_id}&epoch=${serverEpoch}`, {
      method: 'POST',
    });
    statusText.textContent = `Cancelled job #${job.job_id}. Waiting for next request…`;
    job = null;
    app.hidden = true;
  }

  // window.confirm collides with our handler name, alias it.
  function confirm_(msg) { return window.confirm(msg); }

  // ---------- bindings ----------

  prevBtn.addEventListener('click', () => {
    if (currentPage > 0) renderPage(currentPage - 1, false);
  });
  nextBtn.addEventListener('click', () => {
    if (job && currentPage < job.total_pages - 1) renderPage(currentPage + 1, false);
  });
  gotoBtn.addEventListener('click', () => {
    if (!job) return;
    const v = parseInt(pageInput.value, 10);
    if (Number.isFinite(v) && v >= 1 && v <= job.total_pages) {
      renderPage(v - 1, false);
    }
  });
  pageInput.addEventListener('keydown', (e) => {
    if (e.key === 'Enter') gotoBtn.click();
  });
  addEraserBtn.addEventListener('click', addEraser);
  toggleDragBtn.addEventListener('click', () => {
    if (!cropper) return;
    const next = toggleDragBtn.dataset.mode === 'crop' ? 'move' : 'crop';
    cropper.setDragMode(next);
    toggleDragBtn.dataset.mode = next;
    toggleDragBtn.textContent = next === 'crop' ? 'Draw' : 'Pan';
  });
  resetBtn.addEventListener('click', () => {
    if (!job || !cropper) return;
    const sb = currentPage === job.page_index ? suggestedBboxImagePx() : null;
    const target = sb || defaultCenteredBoxPx();
    cropper.setData({
      x: target.left, y: target.top,
      width: target.width, height: target.height,
    });
  });
  confirmBtn.addEventListener('click', confirm);
  cancelBtn.addEventListener('click', cancel);

  // Refresh eraser layer on canvas-container resize / zoom.
  const ro = new ResizeObserver(() => refreshEraserPositions());
  ro.observe(canvasContainer);
  // Cropper emits 'cropmove' / 'zoom' on the image element; we already
  // refresh in the crop callback. But zooming when no crop change fires
  // separately, so listen on the image.
  pageImage.addEventListener('cropmove', refreshEraserPositions);
  pageImage.addEventListener('zoom', () => {
    refreshEraserPositions();
    renderPreview();
  });

  pollLoop();
})();
