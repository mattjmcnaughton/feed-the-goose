"""Application configuration via environment variables.

Every rule number is a setting here, never a constant in rule code (constitution §1).
Rule code receives the values it needs as inputs; it never imports this module.
"""

from typing import Annotated, Literal

from pydantic import field_validator
from pydantic_settings import BaseSettings, NoDecode


class Settings(BaseSettings):
    """Application settings loaded from environment variables."""

    env: Literal["development", "test", "production"] = "development"

    log_level: str = "INFO"
    log_format: str = "json"
    host: str = "0.0.0.0"
    port: int = 8000

    database_url: str = (
        "postgresql+asyncpg://postgres:postgres@localhost:5432/feed_the_goose"
    )

    # Who may sign up: a comma-separated list of emails.
    allowed_emails: Annotated[tuple[str, ...], NoDecode] = ()

    # Development guard (TDD §5.6). Both are refused when env is production.
    dev_sign_in_enabled: bool = False
    dev_routes_enabled: bool = False

    # Pursuers the server accepts.
    pursuers: tuple[str, ...] = ("goose",)

    # Rule numbers (TDD §5.3, §5.5; API spec).
    steps_per_day: int = 100
    starting_lead: int = 100
    min_day_hours: int = 8
    max_day_hours: int = 22
    stage_thresholds: tuple[int, ...] = (3, 7, 14, 30)
    max_habits: int = 8
    log_clock_skew_seconds: int = 120
    default_day_start: str = "06:00"
    default_day_end: str = "00:00"

    # Credentials (API spec "Credentials").
    session_lifetime_days: int = 90

    # Auth0 (TDD §5.6). No tenant exists yet, so its verifier is off until the
    # issuer is set. It must match the tokens' `iss` exactly, including Auth0's
    # trailing slash: https://example.us.auth0.com/.
    auth0_issuer: str | None = None
    auth0_audience: str = "https://feed-the-goose.mattjmcnaughton.com/v1"

    # Reminders (TDD §5.9).
    reminder_lead_below: int = 30
    reminder_before_seconds: int = 3600

    model_config = {"env_file": ".env", "env_file_encoding": "utf-8"}

    @field_validator("allowed_emails", mode="before")
    @classmethod
    def _split_emails(cls, value: object) -> object:
        if isinstance(value, str):
            return tuple(e.strip().lower() for e in value.split(",") if e.strip())
        return value


settings = Settings()
