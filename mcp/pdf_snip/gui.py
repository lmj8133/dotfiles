"""HTTP-backed review GUI for pdf_snip.

The MCP `pdf_snip` tool runs in a long-lived process. This module
embeds an HTTP server inside that process so each snip request can:

  1. Push a "job" describing the PDF page and a suggested bbox.
  2. Print a URL the user opens in the browser.
  3. Block until the user clicks Confirm in the GUI.
  4. Receive the user's final bbox + eraser rectangles back.

The GUI is a single persistent tab. After the user confirms one job,
the tab waits for the next job via long-polling. Only one job is in
flight at any moment (serial review queue).
"""

from __future__ import annotations

import io
import json
import socket
import threading
import time
from dataclasses import dataclass, field
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any
from urllib.parse import parse_qs, urlparse

import fitz

ASSETS_DIR = Path(__file__).resolve().parent / "gui_assets"


@dataclass
class Job:
    """A single review job. Fields populated by the MCP side; result
    fields filled by the HTTP handler when the user confirms."""

    job_id: int
    pdf_path: str
    figure_id: str
    page_index: int  # 0-based
    suggested_bbox_pt: tuple[float, float, float, float] | None
    render_dpi: int = 150

    # Filled in by the user via GUI
    result_bbox_pt: tuple[float, float, float, float] | None = None
    result_erasers_pt: list[dict[str, Any]] = field(default_factory=list)
    result_page_index: int | None = None
    result_event: threading.Event = field(default_factory=threading.Event)
    cancelled: bool = False

    def to_client(self) -> dict[str, Any]:
        doc = fitz.open(self.pdf_path)
        try:
            total_pages = doc.page_count
            page = doc[self.page_index]
            page_rect = page.rect
        finally:
            doc.close()
        return {
            "job_id": self.job_id,
            "pdf_path": self.pdf_path,
            "pdf_name": Path(self.pdf_path).name,
            "figure_id": self.figure_id,
            "page_index": self.page_index,  # 0-based
            "page_number": self.page_index + 1,  # 1-based for display
            "total_pages": total_pages,
            "page_width_pt": page_rect.width,
            "page_height_pt": page_rect.height,
            "render_dpi": self.render_dpi,
            "suggested_bbox_pt": self.suggested_bbox_pt,
        }


class JobQueue:
    """Serial review queue: at most one job is being shown at a time.

    `submit_job` blocks the caller until the user confirms (or cancels)
    via the HTTP handler. Subsequent calls from MCP queue up behind the
    first.
    """

    def __init__(self) -> None:
        self._lock = threading.Lock()  # serialises submit_job calls
        self._cv = threading.Condition()  # signals new active job to GUI
        self._active: Job | None = None
        self._next_id = 1

    def submit_job(
        self,
        pdf_path: str,
        figure_id: str,
        page_index: int,
        suggested_bbox_pt: tuple[float, float, float, float] | None,
        render_dpi: int = 150,
        timeout_s: float | None = 1800.0,
    ) -> Job:
        """Push a job and block until the user confirms it. Returns the
        finished Job (with result_* fields populated). Raises
        TimeoutError if the user never confirms within timeout_s."""
        with self._lock:
            with self._cv:
                job = Job(
                    job_id=self._next_id,
                    pdf_path=pdf_path,
                    figure_id=figure_id,
                    page_index=page_index,
                    suggested_bbox_pt=suggested_bbox_pt,
                    render_dpi=render_dpi,
                )
                self._next_id += 1
                self._active = job
                self._cv.notify_all()
            ready = job.result_event.wait(timeout=timeout_s)
            with self._cv:
                self._active = None
                self._cv.notify_all()
            if not ready:
                raise TimeoutError(
                    f"User did not confirm job {job.job_id} within {timeout_s}s"
                )
            if job.cancelled:
                raise RuntimeError(f"Job {job.job_id} was cancelled by user")
            return job

    def wait_for_job(self, since_id: int, timeout_s: float = 25.0) -> Job | None:
        """Long-poll: return the active job when its id > since_id, or
        None on timeout. The GUI calls this repeatedly to discover new
        jobs without polling tightly."""
        deadline = time.monotonic() + timeout_s
        with self._cv:
            while True:
                if self._active is not None and self._active.job_id > since_id:
                    return self._active
                remaining = deadline - time.monotonic()
                if remaining <= 0:
                    return None
                self._cv.wait(timeout=remaining)

    def get_active(self) -> Job | None:
        with self._cv:
            return self._active

    def get_active_by_id(self, job_id: int) -> Job | None:
        with self._cv:
            if self._active and self._active.job_id == job_id:
                return self._active
            return None


_queue = JobQueue()
_server: ThreadingHTTPServer | None = None
_server_thread: threading.Thread | None = None
_server_port: int | None = None
_server_lock = threading.Lock()


def get_queue() -> JobQueue:
    return _queue


def _find_free_port(start: int = 7860, end: int = 7960) -> int:
    for port in range(start, end):
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
            try:
                s.bind(("127.0.0.1", port))
                return port
            except OSError:
                continue
    raise RuntimeError(f"No free port in [{start}, {end})")


URL_HINT_FILE = Path("/tmp/pdf_snip_url.txt")


def ensure_server_running() -> str:
    """Start the HTTP server if needed and return the URL.

    On first start, opens the URL in the user's default browser. If the
    automatic launch fails (headless server, no DISPLAY), writes the
    URL to /tmp/pdf_snip_url.txt so the user can retrieve it.
    """
    global _server, _server_thread, _server_port
    first_start = False
    with _server_lock:
        if _server is None:
            port = _find_free_port()
            httpd = ThreadingHTTPServer(("127.0.0.1", port), _Handler)
            httpd.daemon_threads = True
            thread = threading.Thread(target=httpd.serve_forever, daemon=True)
            thread.start()
            _server = httpd
            _server_thread = thread
            _server_port = port
            first_start = True
        url = f"http://127.0.0.1:{_server_port}/"
    if first_start:
        opened = _try_open_browser(url)
        if not opened:
            try:
                URL_HINT_FILE.write_text(url + "\n", encoding="utf-8")
            except OSError:
                pass
    return url


def _try_open_browser(url: str) -> bool:
    """Best-effort attempt to open `url` in the user's default browser.

    Resolution order:
      1. wslview (WSL with `wslu` package) — opens on Windows side
      2. cmd.exe /c start (plain WSL fallback)
      3. webbrowser.open (macOS `open`, Linux desktop `xdg-open`,
         native Windows python)

    Returns True if at least one method appeared to launch successfully.
    Headless servers (SSH, no DISPLAY) generally end up returning False;
    in that case the caller should surface the URL another way.
    """
    import shutil
    import subprocess

    # WSL: prefer wslview if installed.
    if shutil.which("wslview"):
        try:
            subprocess.Popen(
                ["wslview", url],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
            return True
        except OSError:
            pass

    # WSL: invoke Windows cmd.exe to launch the default browser.
    if shutil.which("cmd.exe"):
        try:
            subprocess.Popen(
                ["cmd.exe", "/c", "start", "", url],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
            return True
        except OSError:
            pass

    # Native macOS / Linux desktop / Windows-native python.
    try:
        import webbrowser

        return webbrowser.open(url, new=2, autoraise=True)
    except Exception:  # noqa: BLE001
        return False


# --------- HTTP handler ---------


class _Handler(BaseHTTPRequestHandler):
    def log_message(self, format: str, *args) -> None:  # noqa: A002
        # Silence default access log noise.
        return

    # --- helpers ---

    def _send_json(self, status: int, payload: Any) -> None:
        body = json.dumps(payload).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _send_bytes(self, status: int, content_type: str, body: bytes) -> None:
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _send_error_json(self, status: int, message: str) -> None:
        self._send_json(status, {"error": message})

    # --- routing ---

    def do_GET(self) -> None:  # noqa: N802
        url = urlparse(self.path)
        path = url.path
        params = parse_qs(url.query)

        if path in ("/", "/index.html"):
            self._serve_static("index.html", "text/html; charset=utf-8")
            return
        if path.startswith("/static/"):
            self._serve_static(path[len("/static/") :], None)
            return
        if path == "/poll":
            since = int(params.get("since", ["0"])[0])
            timeout = float(params.get("timeout", ["25"])[0])
            job = _queue.wait_for_job(since, timeout_s=timeout)
            if job is None:
                self._send_json(200, {"job": None})
                return
            self._send_json(200, {"job": job.to_client()})
            return
        if path == "/render":
            self._handle_render(params)
            return
        self._send_error_json(404, f"Not found: {path}")

    def do_POST(self) -> None:  # noqa: N802
        url = urlparse(self.path)
        path = url.path
        params = parse_qs(url.query)
        if path == "/submit":
            self._handle_submit(params)
            return
        if path == "/cancel":
            self._handle_cancel(params)
            return
        self._send_error_json(404, f"Not found: {path}")

    # --- handlers ---

    def _serve_static(self, name: str, content_type: str | None) -> None:
        path = (ASSETS_DIR / name).resolve()
        if not path.is_file() or ASSETS_DIR.resolve() not in path.parents:
            self._send_error_json(404, f"Asset not found: {name}")
            return
        if content_type is None:
            ext = path.suffix.lower()
            content_type = {
                ".html": "text/html; charset=utf-8",
                ".js": "application/javascript; charset=utf-8",
                ".css": "text/css; charset=utf-8",
                ".png": "image/png",
                ".svg": "image/svg+xml",
            }.get(ext, "application/octet-stream")
        body = path.read_bytes()
        self._send_bytes(200, content_type, body)

    def _handle_render(self, params: dict[str, list[str]]) -> None:
        job_id = int(params.get("job", ["0"])[0])
        page_arg = params.get("page", [None])[0]
        dpi_arg = params.get("dpi", [None])[0]
        job = _queue.get_active_by_id(job_id)
        if job is None:
            self._send_error_json(404, f"Job {job_id} not active")
            return
        page_index = int(page_arg) if page_arg is not None else job.page_index
        dpi = int(dpi_arg) if dpi_arg is not None else job.render_dpi
        try:
            doc = fitz.open(job.pdf_path)
            try:
                if page_index < 0 or page_index >= doc.page_count:
                    self._send_error_json(400, f"Page {page_index} out of range")
                    return
                page = doc[page_index]
                pix = page.get_pixmap(dpi=dpi)
                buf = io.BytesIO(pix.tobytes("png"))
                self.send_response(200)
                self.send_header("Content-Type", "image/png")
                self.send_header("Content-Length", str(buf.getbuffer().nbytes))
                self.send_header("X-Page-Width-Pt", f"{page.rect.width:.4f}")
                self.send_header("X-Page-Height-Pt", f"{page.rect.height:.4f}")
                self.send_header("X-Image-Width-Px", str(pix.width))
                self.send_header("X-Image-Height-Px", str(pix.height))
                self.end_headers()
                self.wfile.write(buf.getvalue())
            finally:
                doc.close()
        except Exception as exc:  # noqa: BLE001
            self._send_error_json(500, f"render failed: {exc}")

    def _handle_submit(self, params: dict[str, list[str]]) -> None:
        job_id = int(params.get("job", ["0"])[0])
        job = _queue.get_active_by_id(job_id)
        if job is None:
            self._send_error_json(404, f"Job {job_id} not active")
            return
        length = int(self.headers.get("Content-Length", "0"))
        body = self.rfile.read(length).decode("utf-8")
        try:
            data = json.loads(body)
        except json.JSONDecodeError as exc:
            self._send_error_json(400, f"bad json: {exc}")
            return
        try:
            bbox = data["bbox_pt"]
            erasers = data.get("erasers_pt", [])
            page_index = int(data.get("page_index", job.page_index))
        except (KeyError, ValueError) as exc:
            self._send_error_json(400, f"missing field: {exc}")
            return
        job.result_bbox_pt = tuple(bbox)  # type: ignore[assignment]
        job.result_erasers_pt = list(erasers)
        job.result_page_index = page_index
        job.result_event.set()
        self._send_json(200, {"ok": True})

    def _handle_cancel(self, params: dict[str, list[str]]) -> None:
        job_id = int(params.get("job", ["0"])[0])
        job = _queue.get_active_by_id(job_id)
        if job is None:
            self._send_error_json(404, f"Job {job_id} not active")
            return
        job.cancelled = True
        job.result_event.set()
        self._send_json(200, {"ok": True})
