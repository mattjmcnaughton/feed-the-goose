"""Reminder planning and push senders."""

import httpx
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker

from feed_the_goose.clock import Clock
from feed_the_goose.push.apns import ApnsSender
from feed_the_goose.push.config import PushSettings
from feed_the_goose.push.recording import RecordingSender
from feed_the_goose.push.sender import PushSender


def sender_from(
    push: PushSettings, *, clock: Clock, sessions: async_sessionmaker[AsyncSession]
) -> PushSender:
    """APNs when a key is set, otherwise the recording sender."""
    if push.apns_key_path is None:
        return RecordingSender(clock=clock, sessions=sessions)
    assert push.apns_key_id is not None and push.apns_team_id is not None
    return ApnsSender(
        key_pem=push.apns_key_path.read_text(),
        key_id=push.apns_key_id,
        team_id=push.apns_team_id,
        topic=push.apns_topic,
        clock=clock,
        # APNs speaks HTTP/2 only.
        http=httpx.AsyncClient(http1=False, http2=True, timeout=10),
        base_url=push.apns_url,
    )
