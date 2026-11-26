"""Push and worker settings, read from environment variables.

Not from `.env`: `config.Settings` refuses keys it does not know there. With no
APNs key the worker records pushes instead of sending them (TDD §5.9). The key is a
secret: set `APNS_KEY_PATH` to the `.p8` file, never commit it.
"""

from pathlib import Path
from typing import Self

from pydantic import model_validator
from pydantic_settings import BaseSettings


class PushSettings(BaseSettings):
    apns_key_path: Path | None = None
    apns_key_id: str | None = None
    apns_team_id: str | None = None
    apns_topic: str = "com.mattjmcnaughton.feedthegoose"
    # Replaces Apple's hosts; for a fake APNs in tests.
    apns_url: str | None = None

    # Seconds between worker passes.
    worker_interval_seconds: float = 5
    # A reminder is tried this many times, and not at all once this late.
    push_max_attempts: int = 3
    push_stale_after_seconds: int = 900

    @model_validator(mode="after")
    def _all_or_none(self) -> Self:
        apns = (self.apns_key_path, self.apns_key_id, self.apns_team_id)
        if any(v is not None for v in apns) and not all(v is not None for v in apns):
            raise ValueError(
                "set all of APNS_KEY_PATH, APNS_KEY_ID and APNS_TEAM_ID, or none"
            )
        return self
