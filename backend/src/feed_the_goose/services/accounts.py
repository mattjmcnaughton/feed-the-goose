"""The signed-in user's account and day settings (API spec "Me", constitution §4).

A change to the day takes effect when the next day starts, so the day under way never
stretches or shrinks. Settings are append-only: the change is a row effective from the
next day, which stays `pending` until that day starts.
"""

from dataclasses import dataclass
from datetime import date, datetime, time, timedelta
from typing import Protocol
from uuid import UUID
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker

from feed_the_goose.clock import Clock
from feed_the_goose.config import Settings
from feed_the_goose.domain import day as rules
from feed_the_goose.models import DaySettings, User
from feed_the_goose.repositories.day_settings import DaySettingsRepository
from feed_the_goose.repositories.users import UserRepository
from feed_the_goose.services.auth import Principal, UnauthenticatedError


class IdentityAdmin(Protocol):
    """Deletes a user at the identity provider (TDD §5.6)."""

    async def delete_identity(self, subject: str) -> None: ...


class NoIdentityAdmin:
    """Does nothing. Deleting the Auth0 user waits for a tenant (TDD §0.2)."""

    async def delete_identity(self, subject: str) -> None:
        return None


class InvalidFieldsError(Exception):
    """Fields that failed a rule, each with a fixed message."""

    def __init__(self, errors: dict[str, str]) -> None:
        super().__init__(", ".join(errors))
        self.errors = errors


@dataclass(frozen=True)
class CurrentDay:
    """The day `now` belongs to, and the user's settings rows, oldest first.

    During the night the current day is the one that just ended.
    """

    date: date
    ends_at: datetime
    settings: list[DaySettings]

    @property
    def next_date(self) -> date:
        return self.date + timedelta(days=1)

    @property
    def current_settings(self) -> DaySettings:
        return _settings_on(self.settings, self.date)

    @property
    def pending_settings(self) -> DaySettings | None:
        latest = self.settings[-1]
        return latest if latest.effective_from > self.date else None


async def current_day(
    db: AsyncSession, user_id: UUID, now: datetime, *, steps_per_day: int
) -> CurrentDay:
    rows = await DaySettingsRepository(db).for_user(user_id)

    def settings_for(day: date) -> rules.DaySettings:
        row = _settings_on(rows, day)
        return rules.DaySettings(row.time_zone, row.day_start, row.day_end)

    today = rules.date_of(now, settings_for)
    window = rules.day_window(today, settings_for(today), steps_per_day=steps_per_day)
    return CurrentDay(date=today, ends_at=window.ends_at, settings=rows)


async def lock_user(db: AsyncSession, principal: Principal) -> User:
    """Lock the principal's user row until the transaction ends."""
    user = await UserRepository(db).lock(principal.user_id)
    if user is None:  # deleted since the credential was checked
        raise UnauthenticatedError
    return user


def _settings_on(rows: list[DaySettings], day: date) -> DaySettings:
    """The row in effect on `day`; the first row covers any earlier date."""
    return next((r for r in reversed(rows) if r.effective_from <= day), rows[0])


@dataclass(frozen=True)
class Account:
    user: User
    current: DaySettings
    pending: DaySettings | None


@dataclass(frozen=True)
class AccountChanges:
    """Fields to change; None leaves a field as it is."""

    display_name: str | None = None
    pursuer: str | None = None
    time_zone: str | None = None
    day_start: time | None = None
    day_end: time | None = None


class AccountService:
    def __init__(
        self,
        *,
        settings: Settings,
        clock: Clock,
        sessions: async_sessionmaker[AsyncSession],
        identity_admin: IdentityAdmin,
    ) -> None:
        self._settings = settings
        self._clock = clock
        self._sessions = sessions
        self._identity_admin = identity_admin

    async def get(self, principal: Principal) -> Account:
        async with self._sessions.begin() as db:
            user = await UserRepository(db).get(principal.user_id)
            if user is None:  # deleted since the credential was checked
                raise UnauthenticatedError
            return await self._account(db, user)

    async def update(self, principal: Principal, changes: AccountChanges) -> Account:
        """Apply `changes`. The pursuer and display name change now; the day's
        settings change from the next day."""
        now = self._clock.now()
        async with self._sessions.begin() as db:
            user = await lock_user(db, principal)
            if changes.pursuer is not None:
                if changes.pursuer not in self._settings.pursuers:
                    raise InvalidFieldsError({"pursuer": "Value is not valid"})
                if changes.pursuer != user.pursuer:
                    user.pursuer = changes.pursuer
                    user.chase_changed_at = now
            if changes.display_name is not None:
                user.display_name = changes.display_name
            if await self._change_day(db, user.id, changes, now):
                # The current chase's `next_day_starts_at` may move.
                user.chase_changed_at = now
            return await self._account(db, user)

    async def delete(self, principal: Principal) -> None:
        """Delete the account and every row of it, which revokes its sessions and
        keys, then the identity at the provider. A failure there rolls back."""
        async with self._sessions.begin() as db:
            user = await lock_user(db, principal)
            await UserRepository(db).delete(user.id)
            await self._identity_admin.delete_identity(user.identity_subject)

    async def _change_day(
        self, db: AsyncSession, user_id: UUID, changes: AccountChanges, now: datetime
    ) -> bool:
        """Write the day's new settings from the next day. True when they changed."""
        if (changes.time_zone, changes.day_start, changes.day_end) == (None,) * 3:
            return False
        day = await current_day(
            db, user_id, now, steps_per_day=self._settings.steps_per_day
        )
        base = day.settings[-1]
        wanted = (
            base.time_zone if changes.time_zone is None else changes.time_zone,
            base.day_start if changes.day_start is None else changes.day_start,
            base.day_end if changes.day_end is None else changes.day_end,
        )
        errors: dict[str, str] = {}
        if changes.time_zone is not None and not _is_zone(changes.time_zone):
            errors["time_zone"] = "Value is not valid"
        if not rules.day_length_is_valid(
            wanted[1],
            wanted[2],
            min_hours=self._settings.min_day_hours,
            max_hours=self._settings.max_day_hours,
        ):
            message = (
                f"The day must be {self._settings.min_day_hours} to "
                f"{self._settings.max_day_hours} hours long"
            )
            for field in ("day_start", "day_end"):
                if getattr(changes, field) is not None:
                    errors[field] = message
        if errors:
            raise InvalidFieldsError(errors)

        # During the night the next day may already have started under the new
        # settings, such as with an earlier start; a day never starts before the
        # change that moved it, so the change waits one more day.
        effective_from = day.next_date
        next_start = rules.day_window(
            effective_from,
            rules.DaySettings(*wanted),
            steps_per_day=self._settings.steps_per_day,
            not_before=day.ends_at,
        ).starts_at
        if next_start <= now:
            effective_from += timedelta(days=1)

        repository = DaySettingsRepository(db)
        changed = False
        for row in day.settings:
            if row.effective_from > effective_from:  # superseded by this change
                await repository.delete(row)
                changed = True
        before = _settings_on(day.settings, effective_from - timedelta(days=1))
        existing = next(
            (r for r in day.settings if r.effective_from == effective_from), None
        )
        if wanted == _values(before):
            if existing is not None:
                await repository.delete(existing)
                changed = True
        elif existing is None:
            await repository.add(
                DaySettings(
                    user_id=user_id,
                    effective_from=effective_from,
                    time_zone=wanted[0],
                    day_start=wanted[1],
                    day_end=wanted[2],
                    created_at=now,
                )
            )
            changed = True
        elif wanted != _values(existing):
            existing.time_zone, existing.day_start, existing.day_end = wanted
            changed = True
        return changed

    async def _account(self, db: AsyncSession, user: User) -> Account:
        day = await current_day(
            db, user.id, self._clock.now(), steps_per_day=self._settings.steps_per_day
        )
        return Account(
            user=user, current=day.current_settings, pending=day.pending_settings
        )


def _values(row: DaySettings) -> tuple[str, time, time]:
    return row.time_zone, row.day_start, row.day_end


def _is_zone(name: str) -> bool:
    try:
        ZoneInfo(name)
    except (ZoneInfoNotFoundError, ValueError):
        return False
    return True
