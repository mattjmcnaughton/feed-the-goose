"""The current day's chase and the history of days (API spec "Chase and history")."""

from dataclasses import dataclass
from datetime import date, datetime
from fractions import Fraction
from uuid import UUID

from sqlalchemy.ext.asyncio import AsyncSession

from feed_the_goose.clock import Clock
from feed_the_goose.config import Settings
from feed_the_goose.domain import chase as rules
from feed_the_goose.domain.streak import stage
from feed_the_goose.repositories.days import DayRepository
from feed_the_goose.services.days import (
    DayRecord,
    DaysService,
    Ensured,
    RefusedError,
)


class NoChaseError(RefusedError):
    """The user has no habit for the current day."""


class InvalidRangeError(RefusedError):
    """`from` is after `to`."""


@dataclass(frozen=True)
class ChaseView:
    """A day's chase at an instant, with the streak including that day."""

    pursuer: str
    record: DayRecord
    state: rules.ChaseState
    complete_days: int
    stage: int


@dataclass(frozen=True)
class DayResult:
    """One day's result. `end_lead` is None until the day settles."""

    date: date
    pursuer: str
    result: rules.DayState
    end_lead: Fraction | None
    complete_days: int


class ChaseService:
    def __init__(
        self,
        *,
        settings: Settings,
        clock: Clock,
        days: DaysService,
    ) -> None:
        self._settings = settings
        self._clock = clock
        self._days = days

    async def today(self, user_id: UUID) -> ChaseView:
        """The current day's chase; during the night, the day that just ended."""
        now = self._clock.now()
        async with self._days.transaction(user_id, now) as (db, ensured):
            return await self.current(db, ensured, now)

    async def current(
        self, db: AsyncSession, ensured: Ensured, now: datetime
    ) -> ChaseView:
        """The current day's chase inside a transaction that ensured the days."""
        if ensured.current is None:
            raise NoChaseError
        record = await self._days.record(db, ensured.calendar, ensured.current)
        return self.view(ensured.user.pursuer, record, now)

    def view(self, pursuer: str, record: DayRecord, at: datetime) -> ChaseView:
        state = record.chase_at(at)
        complete_days = record.streak_before + (
            1 if state.state is rules.DayState.COMPLETE else 0
        )
        return ChaseView(
            pursuer=pursuer,
            record=record,
            state=state,
            complete_days=complete_days,
            stage=stage(complete_days, self._settings.stage_thresholds),
        )

    async def history(self, user_id: UUID, first: date, last: date) -> list[DayResult]:
        """Each day's result from `first` to `last`, both included. A day that has
        not settled shows its state now."""
        if first > last:
            raise InvalidRangeError
        now = self._clock.now()
        async with self._days.transaction(user_id, now) as (db, ensured):
            pursuer = ensured.user.pursuer
            results = []
            for row in await DayRepository(db).between(user_id, first, last):
                if row.settled_at is not None:
                    assert row.result is not None and row.streak_after is not None
                    results.append(
                        DayResult(
                            row.date,
                            pursuer,
                            rules.DayState(row.result),
                            row.end_lead,
                            row.streak_after,
                        )
                    )
                    continue
                record = await self._days.record(db, ensured.calendar, row)
                view = self.view(pursuer, record, now)
                results.append(
                    DayResult(
                        row.date, pursuer, view.state.state, None, view.complete_days
                    )
                )
            return results
