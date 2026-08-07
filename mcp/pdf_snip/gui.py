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
import os
import socket
import sys
import threading
import time
import uuid
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

# Identifies this server process. Sent in every /poll response and echoed
# back by the client, so a tab left over from a previous server process
# (whose job ids restarted at 1) can detect the restart and resync its
# `since` watermark instead of silently never matching a job again.
_EPOCH = uuid.uuid4().hex[:12]

# time.monotonic() of the most recent /poll request. Used to decide
# whether a GUI tab is currently connected (idle tabs long-poll every
# ~25 s, so anything within CLIENT_ALIVE_S counts as alive).
_last_poll_at: float | None = None
CLIENT_ALIVE_S = 30.0

# time.monotonic() of the last browser launch we triggered, so two
# near-simultaneous tool calls don't each open a tab while the first
# one is still loading.
_last_browser_open_at: float | None = None

# time.monotonic() of server start; bounds the reconnect grace wait.
_server_started_at: float | None = None

# Serialises the "is a tab connected? if not, open one" decision so
# concurrent tool calls can't both conclude "no tab" and open twice.
_open_lock = threading.Lock()


def get_queue() -> JobQueue:
    return _queue


def _preferred_port() -> int:
    """Port to try first: PDF_SNIP_PORT env var, default 7860.

    A stable port is what lets a browser tab from a previous session
    reconnect to the next session's server.
    """
    raw = os.environ.get("PDF_SNIP_PORT", "").strip()
    if not raw:
        return 7860
    try:
        port = int(raw)
    except ValueError:
        port = -1
    if not 1024 <= port <= 65535:
        print(
            f"[pdf_snip] ignoring invalid PDF_SNIP_PORT={raw!r}, using 7860",
            file=sys.stderr,
            flush=True,
        )
        return 7860
    return port


def _find_free_port(start: int = 7860, end: int | None = None) -> int:
    if end is None:
        end = min(start + 100, 65536)
    for port in range(start, end):
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
            # Match HTTPServer.allow_reuse_address, or TIME_WAIT leftovers
            # from a previous session's server (killed while a tab was
            # connected) would push us off the stable port that the tab
            # is trying to reconnect to. On Linux/macOS a port with a
            # live listener still fails the probe (SO_REUSEADDR is not
            # SO_REUSEPORT). Skip it on Windows, where WinSock's
            # SO_REUSEADDR WOULD bind over a live listener; Windows
            # allows rebinding through TIME_WAIT without it anyway.
            if sys.platform != "win32":
                s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            try:
                s.bind(("127.0.0.1", port))
                return port
            except OSError:
                continue
    raise RuntimeError(f"No free port in [{start}, {end})")


URL_HINT_FILE = Path("/tmp/pdf_snip_url.txt")


def ensure_server_running() -> str:
    """Start the HTTP server if needed and return the URL.

    The browser is only opened when no GUI tab is connected: a tab left
    over from a previous server process reconnects on its own (see the
    epoch resync in /poll), so in the common case the same tab is
    reused across sessions and no new window is opened. With
    PDF_SNIP_AUTO_OPEN=0 the browser is never opened. Either way the
    actual URL (which may differ from the preferred port if it was
    taken) is written to /tmp/pdf_snip_url.txt on startup.
    """
    global _server, _server_thread, _server_port, _server_started_at
    first_start = False
    with _server_lock:
        if _server is None:
            httpd = ThreadingHTTPServer(
                ("127.0.0.1", _find_free_port(_preferred_port())), _Handler
            )
            httpd.daemon_threads = True
            thread = threading.Thread(target=httpd.serve_forever, daemon=True)
            thread.start()
            _server = httpd
            _server_thread = thread
            _server_port = httpd.server_address[1]
            _server_started_at = time.monotonic()
            first_start = True
        url = f"http://127.0.0.1:{_server_port}/"
    if first_start:
        _write_url_hint(url)
    if not _auto_open_enabled():
        return url
    with _open_lock:
        _wait_for_first_poll()
        if _should_open_browser():
            _note_browser_open()
            _try_open_browser(url)
    return url


def _auto_open_enabled() -> bool:
    """Whether we may launch the user's browser (PDF_SNIP_AUTO_OPEN).

    Enabled unless set to 0 / false / no (case-insensitive).
    """
    value = os.environ.get("PDF_SNIP_AUTO_OPEN", "1").strip().lower()
    return value not in ("0", "false", "no")


def _note_client_poll() -> None:
    global _last_poll_at
    _last_poll_at = time.monotonic()


def _client_recently_polled() -> bool:
    return (
        _last_poll_at is not None and time.monotonic() - _last_poll_at < CLIENT_ALIVE_S
    )


def _wait_for_first_poll(grace_s: float = 2.5) -> None:
    """Shortly after server start, give a tab from a previous session a
    moment to reconnect (it retries /poll every 2 s) before deciding
    that no tab exists and a browser launch is needed. The wait is
    bounded by server age, so across all callers it is paid at most
    once per process — the first-launch latency when no tab exists."""
    if _server_started_at is None:
        return
    deadline = _server_started_at + grace_s
    while _last_poll_at is None and time.monotonic() < deadline:
        time.sleep(0.15)


def _should_open_browser() -> bool:
    if _client_recently_polled():
        return False
    # A tab we just launched may still be loading and not polling yet;
    # don't stack a second one on top of it.
    if (
        _last_browser_open_at is not None
        and time.monotonic() - _last_browser_open_at < 10.0
    ):
        return False
    return True


def _note_browser_open() -> None:
    global _last_browser_open_at
    _last_browser_open_at = time.monotonic()


def _write_url_hint(url: str) -> None:
    try:
        URL_HINT_FILE.write_text(url + "\n", encoding="utf-8")
    except OSError:
        pass


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
            client_epoch = params.get("epoch", [None])[0]
            if client_epoch is not None and client_epoch != _EPOCH:
                # Tab from a previous server process: its job-id
                # watermark is meaningless here (ids restarted at 1),
                # so treat it as having seen nothing yet. Clients that
                # never send an epoch (pre-epoch app.js) keep their
                # since untouched — forcing 0 would hand them the
                # active job on every poll in a tight re-render loop.
                since = 0
            _note_client_poll()
            job = _queue.wait_for_job(since, timeout_s=timeout)
            _note_client_poll()  # still connected after the long-poll hold
            if job is None:
                self._send_json(200, {"job": None, "epoch": _EPOCH})
                return
            self._send_json(200, {"job": job.to_client(), "epoch": _EPOCH})
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

    def _check_epoch(self, params: dict[str, list[str]]) -> bool:
        """Reject job-scoped requests from a stale tab. Job ids restart
        at 1 per process, so after a restart on the same port a stale
        tab's ids collide with the new process's — acting on them would
        render/confirm/cancel the wrong session's job."""
        if params.get("epoch", [None])[0] != _EPOCH:
            self._send_error_json(409, "stale client epoch — reload the GUI page")
            return False
        return True

    def _handle_render(self, params: dict[str, list[str]]) -> None:
        if not self._check_epoch(params):
            return
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
        if not self._check_epoch(params):
            return
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
        if not self._check_epoch(params):
            return
        job_id = int(params.get("job", ["0"])[0])
        job = _queue.get_active_by_id(job_id)
        if job is None:
            self._send_error_json(404, f"Job {job_id} not active")
            return
        job.cancelled = True
        job.result_event.set()
        self._send_json(200, {"ok": True})
