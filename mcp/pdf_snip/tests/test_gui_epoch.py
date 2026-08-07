"""Tests for gui.py — /poll epoch resync, client liveness, and env config.

The epoch resync is what lets a browser tab left over from a previous
server process (whose job ids restarted at 1) receive jobs from a new
server on the same port instead of long-polling forever with a stale
`since` watermark.
"""

from __future__ import annotations

import json
import threading
import time
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any

import pytest

import gui


def _get_json(url: str) -> dict[str, Any]:
    with urllib.request.urlopen(url, timeout=10) as resp:
        return json.loads(resp.read())


def _post_json(url: str, payload: dict[str, Any]) -> dict[str, Any]:
    req = urllib.request.Request(
        url,
        data=json.dumps(payload).encode("utf-8"),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=10) as resp:
        return json.loads(resp.read())


def _submit_in_background(pdf_path: str) -> tuple[threading.Thread, list[Any]]:
    """Run submit_job in a thread (it blocks until the job is confirmed).
    Returns the thread and a one-element list that will hold the finished
    Job or the raised exception."""
    results: list[Any] = []

    def run() -> None:
        try:
            results.append(
                gui.get_queue().submit_job(
                    pdf_path=pdf_path,
                    figure_id="Figure 1",
                    page_index=0,
                    suggested_bbox_pt=None,
                    timeout_s=30.0,
                )
            )
        except Exception as exc:  # noqa: BLE001 — surfaced via assert in the test
            results.append(exc)

    thread = threading.Thread(target=run, daemon=True)
    thread.start()
    return thread, results


def _wait_active(timeout_s: float = 5.0) -> gui.Job:
    deadline = time.monotonic() + timeout_s
    while time.monotonic() < deadline:
        job = gui.get_queue().get_active()
        if job is not None:
            return job
        time.sleep(0.02)
    raise AssertionError("no active job appeared")


def _confirm(url_base: str, job_id: int) -> None:
    _post_json(
        f"{url_base}submit?job={job_id}&epoch={gui._EPOCH}",
        {"bbox_pt": [10.0, 10.0, 200.0, 150.0], "erasers_pt": [], "page_index": 0},
    )


@pytest.fixture
def gui_url(monkeypatch: pytest.MonkeyPatch) -> str:
    """Start (or reuse) the embedded HTTP server with browser launch off."""
    monkeypatch.setenv("PDF_SNIP_AUTO_OPEN", "0")
    return gui.ensure_server_running()


def test_stale_tab_resyncs_after_server_restart(
    gui_url: str, synthetic_pdf: Path
) -> None:
    """A tab whose `since` watermark outruns this server's job ids (the
    cross-session restart case) must still receive the active job when
    its epoch doesn't match, while a matching epoch honors `since`."""
    thread, results = _submit_in_background(str(synthetic_pdf))
    active = _wait_active()
    stale_since = active.job_id + 100  # watermark from a "previous server"

    data = _get_json(f"{gui_url}poll?since={stale_since}&timeout=5&epoch=deadbeef")
    assert data["epoch"] == gui._EPOCH
    assert data["job"] is not None
    assert data["job"]["job_id"] == active.job_id

    # Same watermark with the matching epoch is honored: no job.
    data = _get_json(
        f"{gui_url}poll?since={stale_since}&timeout=0.2&epoch={gui._EPOCH}"
    )
    assert data["job"] is None
    assert data["epoch"] == gui._EPOCH

    # A legacy pre-epoch client (no epoch param at all) also keeps its
    # watermark — forcing since=0 would hand it the active job on every
    # poll in a tight re-render loop.
    data = _get_json(f"{gui_url}poll?since={stale_since}&timeout=0.2")
    assert data["job"] is None

    # A stale tab must not be able to act on the new server's job ids.
    with pytest.raises(urllib.error.HTTPError) as excinfo:
        _post_json(
            f"{gui_url}submit?job={active.job_id}&epoch=deadbeef",
            {"bbox_pt": [0.0, 0.0, 1.0, 1.0], "erasers_pt": [], "page_index": 0},
        )
    assert excinfo.value.code == 409

    _confirm(gui_url, active.job_id)
    thread.join(timeout=10)
    assert not thread.is_alive()
    assert results and isinstance(results[0], gui.Job)
    assert results[0].result_bbox_pt == (10.0, 10.0, 200.0, 150.0)


def test_fresh_tab_gets_active_job_immediately(
    gui_url: str, synthetic_pdf: Path
) -> None:
    """A fresh page load polls with since=0 and an empty epoch — it must
    receive the currently active job without waiting."""
    thread, results = _submit_in_background(str(synthetic_pdf))
    active = _wait_active()

    data = _get_json(f"{gui_url}poll?since=0&timeout=5&epoch=")
    assert data["job"] is not None
    assert data["job"]["job_id"] == active.job_id

    _confirm(gui_url, active.job_id)
    thread.join(timeout=10)
    assert not thread.is_alive()
    assert results and isinstance(results[0], gui.Job)


def test_preferred_port_env(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.delenv("PDF_SNIP_PORT", raising=False)
    assert gui._preferred_port() == 7860
    monkeypatch.setenv("PDF_SNIP_PORT", "7955")
    assert gui._preferred_port() == 7955
    monkeypatch.setenv("PDF_SNIP_PORT", "bogus")
    assert gui._preferred_port() == 7860
    # Out-of-range values would raise OverflowError at socket.bind (not
    # caught by the OSError handler) or land on privileged/random ports.
    for bad in ("70000", "0", "-1", "80"):
        monkeypatch.setenv("PDF_SNIP_PORT", bad)
        assert gui._preferred_port() == 7860


def test_auto_open_flag(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.delenv("PDF_SNIP_AUTO_OPEN", raising=False)
    assert gui._auto_open_enabled()
    for off in ("0", "false", "No"):
        monkeypatch.setenv("PDF_SNIP_AUTO_OPEN", off)
        assert not gui._auto_open_enabled()
    monkeypatch.setenv("PDF_SNIP_AUTO_OPEN", "1")
    assert gui._auto_open_enabled()


def test_client_liveness_window(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(gui, "_last_poll_at", None)
    assert not gui._client_recently_polled()
    gui._note_client_poll()
    assert gui._client_recently_polled()
    monkeypatch.setattr(
        gui, "_last_poll_at", time.monotonic() - (gui.CLIENT_ALIVE_S + 1)
    )
    assert not gui._client_recently_polled()
