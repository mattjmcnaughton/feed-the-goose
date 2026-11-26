"""The one place that builds services from settings (TDD §5.1).

Tickets add their own registration lines here and nothing else.
"""

from dataclasses import dataclass

from feed_the_goose.clock import Clock, SystemClock
from feed_the_goose.config import Settings


@dataclass(frozen=True)
class Wiring:
    """The application's effects and services, built once."""

    settings: Settings
    clock: Clock


def build(settings: Settings, clock: Clock | None = None) -> Wiring:
    """Build the wiring from settings. Tests pass a fixed clock."""
    return Wiring(settings=settings, clock=clock or SystemClock())
