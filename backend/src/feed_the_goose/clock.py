"""The clock, passed into services so that tests can fix the time (TDD §5.1)."""

from datetime import UTC, datetime
from typing import Protocol


class Clock(Protocol):
    """Tells the current instant."""

    def now(self) -> datetime:
        """Return the current instant, timezone-aware, in UTC."""
        ...


class SystemClock:
    """The real clock."""

    def now(self) -> datetime:
        return datetime.now(UTC)


class FixedClock:
    """A clock for tests: it says `at` until moved."""

    def __init__(self, at: datetime) -> None:
        self._at = _require_aware(at)

    def now(self) -> datetime:
        return self._at

    def set(self, at: datetime) -> None:
        self._at = _require_aware(at)


def _require_aware(at: datetime) -> datetime:
    if at.tzinfo is None:
        raise ValueError("FixedClock needs a timezone-aware datetime")
    return at.astimezone(UTC)
