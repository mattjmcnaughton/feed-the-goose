"""Records pushes instead of sending them, when no APNs key is set (TDD §5.9).

`GET /dev/pushes` lists what it recorded.
"""

from typing import Any

from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker

from feed_the_goose.clock import Clock
from feed_the_goose.models import Installation, PushDelivery
from feed_the_goose.push.sender import Outcome


class RecordingSender:
    def __init__(
        self, *, clock: Clock, sessions: async_sessionmaker[AsyncSession]
    ) -> None:
        self._clock = clock
        self._sessions = sessions

    async def send(
        self, installation: Installation, payload: dict[str, Any]
    ) -> Outcome:
        async with self._sessions.begin() as db:
            db.add(
                PushDelivery(
                    user_id=installation.user_id,
                    installation_id=installation.installation_id,
                    payload=payload,
                    sent_at=self._clock.now(),
                )
            )
        return Outcome.SENT
