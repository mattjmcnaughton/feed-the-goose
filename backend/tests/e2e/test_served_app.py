"""Serves the app with uvicorn on a free port and talks to it over HTTP."""

import os
import socket
import subprocess
import sys
import time
from collections.abc import Iterator

import httpx
import pytest


def _free_port() -> int:
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


@pytest.fixture(scope="module")
def base_url() -> Iterator[str]:
    port = _free_port()
    server = subprocess.Popen(
        [sys.executable, "-m", "uvicorn", "feed_the_goose.app:app"]
        + ["--host", "127.0.0.1", "--port", str(port)],
        env={**os.environ, "ENV": "test"},
    )
    url = f"http://127.0.0.1:{port}"
    try:
        deadline = time.monotonic() + 15
        while time.monotonic() < deadline:
            try:
                httpx.get(f"{url}/healthz", timeout=1)
                break
            except httpx.TransportError:
                time.sleep(0.1)
        else:
            pytest.fail("the server did not start")
        yield url
    finally:
        server.terminate()
        server.wait(timeout=10)


def test_served_app_is_live_and_ready(base_url: str):
    assert httpx.get(f"{base_url}/healthz").status_code == 200
    assert httpx.get(f"{base_url}/readyz").status_code == 200
