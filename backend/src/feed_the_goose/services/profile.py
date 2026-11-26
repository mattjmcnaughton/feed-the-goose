"""The public profile and its settings (TDD §5.8, constitution §5).

Anyone may read a profile its user published. The read re-checks publication every
time and returns `PublishedProfile`, which holds only the fields named for publication:
never habit names, units, amounts, log times or the day's hours.
"""

from dataclasses import dataclass
from datetime import date, datetime, timedelta
from fractions import Fraction
from uuid import UUID

from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker

from feed_the_goose.clock import Clock
from feed_the_goose.domain import chase as rules
from feed_the_goose.repositories.days import DayRepository
from feed_the_goose.repositories.profiles import ProfileRepository
from feed_the_goose.repositories.users import UserRepository
from feed_the_goose.services.chase import ChaseService
from feed_the_goose.services.days import DaysService, RefusedError

# How many days of results a profile shows, ending with the current day.
HISTORY_DAYS = 35

# Handles that would shadow a route at `/{handle}` (TDD §5.8).
RESERVED_HANDLES = frozenset(
    {
        "v1",
        "mcp",
        "dev",
        "healthz",
        "readyz",
        "docs",
        "redoc",
        "openapi.json",
        "static",
        "favicon.ico",
        "robots.txt",
        ".well-known",
    }
)


class ProfileNotFoundError(RefusedError):
    """No profile is published at that handle, or it has nothing to show yet."""


class HandleTakenError(Exception):
    """Another user holds the handle."""


class HandleReservedError(Exception):
    """The handle would shadow a route."""


@dataclass(frozen=True)
class ProfileSettings:
    handle: str | None
    public: bool


@dataclass(frozen=True)
class PublishedDay:
    date: date
    result: rules.DayState


@dataclass(frozen=True)
class PublishedProfile:
    """The published projection, and nothing else."""

    display_name: str
    pursuer: str
    complete_days: int
    stage: int
    state: rules.DayState
    lead: Fraction
    as_of: datetime
    steps_per_hour: Fraction
    caught_at: datetime | None
    days: list[PublishedDay]


class ProfileService:
    def __init__(
        self,
        *,
        clock: Clock,
        sessions: async_sessionmaker[AsyncSession],
        days: DaysService,
        chase: ChaseService,
    ) -> None:
        self._clock = clock
        self._sessions = sessions
        self._days = days
        self._chase = chase

    async def get_settings(self, user_id: UUID) -> ProfileSettings:
        async with self._sessions() as db:
            user = await UserRepository(db).get(user_id)
            if user is None:
                raise LookupError("the principal's user is gone")
            return ProfileSettings(user.handle, user.public)

    async def update_settings(
        self, user_id: UUID, handle: str, public: bool
    ) -> ProfileSettings:
        if handle in RESERVED_HANDLES:
            raise HandleReservedError
        async with self._sessions() as db, db.begin():
            holder = await ProfileRepository(db).holder(handle)
            if holder is not None and holder != user_id:
                raise HandleTakenError
            user = await UserRepository(db).get(user_id)
            if user is None:
                raise LookupError("the principal's user is gone")
            user.handle, user.public = handle, public
            try:
                await db.flush()
            except IntegrityError:
                # Another user took the handle since the check.
                raise HandleTakenError from None
            return ProfileSettings(user.handle, user.public)

    async def published(self, handle: str) -> PublishedProfile:
        """The profile published at `handle`, with its days settled up to now."""
        async with self._sessions() as db:
            user_id = await ProfileRepository(db).published(handle)
        if user_id is None:
            raise ProfileNotFoundError
        now = self._clock.now()
        async with self._days.transaction(user_id, now) as (db, ensured):
            user = ensured.user
            # Checked again under the lock, in case it was unpublished meanwhile.
            if not user.public or user.handle != handle:
                raise ProfileNotFoundError
            days = DayRepository(db)
            row = ensured.current or await days.latest(user_id)
            if row is None:
                raise ProfileNotFoundError
            record = await self._days.record(db, ensured.calendar, row)
            view = self._chase.view(user.pursuer, record, now)
            first = row.date - timedelta(days=HISTORY_DAYS - 1)
            history = []
            for day in await days.between(user_id, first, row.date):
                # Only the day shown can be unsettled: ensure_days settled the rest.
                result = view.state.state if day.result is None else day.result
                history.append(PublishedDay(day.date, rules.DayState(result)))
            return PublishedProfile(
                display_name=user.display_name,
                pursuer=user.pursuer,
                complete_days=view.complete_days,
                stage=view.stage,
                state=view.state.state,
                lead=view.state.lead,
                as_of=view.state.at,
                steps_per_hour=record.window.steps_per_hour,
                caught_at=view.state.caught_at,
                days=history,
            )
