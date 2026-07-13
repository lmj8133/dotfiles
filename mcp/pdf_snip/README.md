# pdf-snip

An MCP server for extracting a region of a PDF page to a PNG, with a
human-in-the-loop browser GUI for the user to confirm the bounding box.

## Why

LLMs that help with note-taking often need a figure, table, or other
region from a PDF. A fully automatic crop is rarely accurate enough
across diverse textbook layouts. `pdf-snip` runs a heuristic to find a
plausible starting page and bounding box, then asks the user to refine
and confirm in a browser GUI.

## Tool: `pdf_snip`

```
pdf_snip(pdf_path, caption_hint, output_path,
         review_dpi=150, output_dpi=200, timeout_s=1800.0) -> str
```

Calling this tool **blocks** until the user confirms in the browser.
It returns the absolute path of the saved PNG.

The `caption_hint` parameter accepts forms like `Figure 3`,
`Fig. 2-1`, `圖 3`, or `Table 1`. The heuristic uses it to land on a
likely page, but the GUI lets the user navigate freely if it landed
on the wrong one.

## GUI capabilities

- Drag and resize the crop box (Cropper.js)
- Scroll-zoom the page, space + drag to pan
- Add eraser rectangles (movable, resizable, recolourable, deletable)
  to mask out unrelated content (other figures' captions, body prose
  bleed, etc.)
- Live cropped preview with eraser preview applied
- Page navigation (prev / next / jump-to-page) for when the heuristic
  lands on the wrong page
- Single persistent browser tab — reused across calls, and (thanks to
  the fixed default port plus an epoch-based resync in `/poll`) across
  MCP sessions too. A new tab is only opened when no tab is connected.

## Configuration

Environment variables (set them in the `env` block of the MCP server
entry in `~/.claude.json`):

- `PDF_SNIP_PORT` — preferred GUI port, default `7860`. If taken
  (e.g. a second concurrent session), the server falls back to the
  next free port within +100. A stable port is what lets a tab from a
  previous session reconnect instead of piling up dead tabs.
- `PDF_SNIP_AUTO_OPEN` — default on. The browser is launched only
  when no GUI tab has polled the server recently (~30 s), so an
  existing tab is never duplicated. Set to `0` to never launch a
  browser. In every mode the server writes its actual URL to
  `/tmp/pdf_snip_url.txt` at startup, and the tool description asks
  the assistant to show the URL to you.

## Install

`pdf-snip` is wired up by the parent dotfiles `bootstrap.sh`. To set
it up manually:

```bash
cd <dotfiles>/mcp/pdf_snip
uv sync
```

Then add the tool to `~/.claude.json` (the dotfiles bootstrap can do
this automatically if `jq` is installed).

## Files

- `server.py`   MCP entry point
- `core.py`     heuristic caption detection + bbox suggestion
- `gui.py`      embedded HTTP server + job queue
- `gui_assets/` HTML / CSS / JS for the review GUI
- `tests/`      unit tests for the heuristic

## License

MIT (with the rest of dotfiles).
