"""The served app, a signed-in user set up for reminders, and a fake APNs.

The fixed clock starts at 10:00 in New York on 2026-11-26. The user's first habit
is created then, so their first day runs from 10:00 to 00:00 at the usual pace of
100/18 = 5.56 steps an hour, from a lead of 100.
"""

import asyncio
import uuid
from collections.abc import AsyncIterator
from dataclasses import dataclass, field

import h2.config
import h2.connection
import h2.events
import httpx
import pytest
from joserfc.jwk import ECKey

from tests.e2e.mcp.conftest import base_url  # noqa: F401  (the served app)

DEVICE_TOKEN = "a1" * 32


@dataclass
class ApnsRequest:
    headers: dict[str, str]
    body: bytes


@dataclass
class FakeApns:
    """Speaks HTTP/2 only, like APNs. Answers 200, or the status set for a token."""

    url: str = ""
    requests: list[ApnsRequest] = field(default_factory=list)
    status_for: dict[str, int] = field(default_factory=dict)
    connections: list[asyncio.StreamWriter] = field(default_factory=list)

    async def handle(
        self, reader: asyncio.StreamReader, writer: asyncio.StreamWriter
    ) -> None:
        conn = h2.connection.H2Connection(
            h2.config.H2Configuration(client_side=False, header_encoding="utf-8")
        )
        self.connections.append(writer)
        conn.initiate_connection()
        writer.write(conn.data_to_send())
        streams: dict[int, ApnsRequest] = {}
        while data := await reader.read(65535):
            for event in conn.receive_data(data):
                if isinstance(event, h2.events.RequestReceived):
                    streams[event.stream_id] = ApnsRequest(
                        {str(k): str(v) for k, v in event.headers or ()}, b""
                    )
                elif isinstance(event, h2.events.DataReceived):
                    streams[event.stream_id].body += event.data
                    conn.acknowledge_received_data(
                        event.flow_controlled_length, event.stream_id
                    )
                elif isinstance(event, h2.events.StreamEnded):
                    request = streams.pop(event.stream_id)
                    self.requests.append(request)
                    token = request.headers[":path"].rsplit("/", 1)[-1]
                    status = self.status_for.get(token, 200)
                    body = b'{"reason":"Unregistered"}' if status == 410 else b""
                    conn.send_headers(
                        event.stream_id,
                        [(":status", str(status)), ("content-length", str(len(body)))],
                        end_stream=not body,
                    )
                    if body:
                        conn.send_data(event.stream_id, body, end_stream=True)
            writer.write(conn.data_to_send())
            await writer.drain()
        writer.close()


@pytest.fixture
async def fake_apns() -> AsyncIterator[FakeApns]:
    fake = FakeApns()
    server = await asyncio.start_server(fake.handle, "127.0.0.1", 0)
    fake.url = f"http://127.0.0.1:{server.sockets[0].getsockname()[1]}"
    async with server:
        yield fake
        # The sender keeps its connection open; close it so the server can stop.
        for writer in fake.connections:
            writer.close()


@pytest.fixture
def apns_key() -> ECKey:
    """A team signing key made for the test, like the `.p8` Apple issues."""
    return ECKey.generate_key("P-256")


@dataclass
class Account:
    rest: httpx.AsyncClient
    user_id: uuid.UUID
    email: str
    habit_id: str
    installation_id: str


@pytest.fixture
async def account(sign_in, base_url) -> AsyncIterator[Account]:  # noqa: F811
    """A user with Pushups 50 by 10, one installation and reminders on below 60."""
    user = await sign_in()
    headers = {"Authorization": f"Bearer {user.token}"}
    async with httpx.AsyncClient(base_url=base_url, headers=headers) as rest:
        habit = await rest.post(
            "/v1/habits",
            json={"name": "Pushups", "unit": "reps", "target": 50, "chunk": 10},
        )
        assert habit.status_code == 201, habit.text
        installation_id = str(uuid.uuid4())
        device = await rest.put(
            f"/v1/me/devices/{installation_id}",
            json={
                "apns_token": DEVICE_TOKEN,
                "environment": "sandbox",
                "app_version": "1.0",
            },
        )
        assert device.status_code == 204, device.text
        reminders = await rest.put(
            "/v1/me/reminders",
            json={"enabled": True, "when_lead_below": 60, "quiet_hours": None},
        )
        assert reminders.status_code == 200, reminders.text
        yield Account(
            rest, user.user_id, user.email, habit.json()["id"], installation_id
        )
        # The worker plans and sends for every user, so leave none behind.
        assert (await rest.delete("/v1/me")).status_code == 204
