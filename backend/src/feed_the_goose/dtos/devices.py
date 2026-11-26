"""Device registration and reminder preferences (API spec "Devices and push")."""

from enum import StrEnum

from pydantic import Field

from feed_the_goose.dtos.common import Dto, LocalTime


class ApnsEnvironment(StrEnum):
    sandbox = "sandbox"
    production = "production"


class DeviceRegistration(Dto):
    apns_token: str = Field(min_length=1)
    widget_push_token: str | None = None
    environment: ApnsEnvironment
    app_version: str = Field(min_length=1)


class QuietHours(Dto):
    """Local times in the user's time zone. `end` may be on the next date."""

    start: LocalTime
    end: LocalTime


class Reminders(Dto):
    enabled: bool
    when_lead_below: int = Field(ge=0)
    quiet_hours: QuietHours | None
