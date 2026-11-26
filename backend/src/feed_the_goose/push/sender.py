"""What sends a push to one installation (TDD §5.9)."""

from enum import StrEnum
from typing import Any, Protocol

from feed_the_goose.models import Installation


class Outcome(StrEnum):
    SENT = "sent"
    # The token is no longer valid; it should be forgotten.
    UNREGISTERED = "unregistered"
    # Anything else: worth trying again later.
    FAILED = "failed"


class PushSender(Protocol):
    async def send(
        self, installation: Installation, payload: dict[str, Any]
    ) -> Outcome: ...
