"""Maps the reminder DTOs to the reminder service and back."""

from datetime import time

from feed_the_goose.dtos.devices import QuietHours, Reminders
from feed_the_goose.dtos.errors import ProblemType
from feed_the_goose.errors import ProblemError
from feed_the_goose.services.auth import Principal, UnauthenticatedError
from feed_the_goose.services.reminders import ReminderPreferences, ReminderService


async def get_reminders(reminders: ReminderService, principal: Principal) -> Reminders:
    try:
        return _dto(await reminders.get(principal))
    except UnauthenticatedError:
        raise ProblemError(ProblemType.unauthenticated) from None


async def update_reminders(
    reminders: ReminderService, principal: Principal, body: Reminders
) -> Reminders:
    quiet = body.quiet_hours
    preferences = ReminderPreferences(
        enabled=body.enabled,
        when_lead_below=body.when_lead_below,
        quiet_hours=None
        if quiet is None
        else (time.fromisoformat(quiet.start), time.fromisoformat(quiet.end)),
    )
    try:
        return _dto(await reminders.update(principal, preferences))
    except UnauthenticatedError:
        raise ProblemError(ProblemType.unauthenticated) from None


def _dto(preferences: ReminderPreferences) -> Reminders:
    quiet = preferences.quiet_hours
    return Reminders(
        enabled=preferences.enabled,
        when_lead_below=preferences.when_lead_below,
        quiet_hours=None
        if quiet is None
        else QuietHours(
            start=quiet[0].strftime("%H:%M"), end=quiet[1].strftime("%H:%M")
        ),
    )
