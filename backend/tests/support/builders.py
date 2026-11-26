"""Builders for rows a test needs, written straight to the database.

Each takes an open session and flushes; the caller commits. Defaults follow the
TDD §5.3 example day: 2026-11-26 in America/New_York, Pushups 50 by 10.
"""

import secrets
from datetime import UTC, date, datetime, timedelta
from fractions import Fraction
from uuid import UUID, uuid4

from sqlalchemy.ext.asyncio import AsyncSession

from feed_the_goose.models import Day, Habit, Key, Log
from feed_the_goose.repositories.days import DayRepository
from feed_the_goose.repositories.habits import HabitRepository
from feed_the_goose.repositories.keys import KeyRepository
from feed_the_goose.repositories.logs import LogRepository
from feed_the_goose.services.auth import digest

EXAMPLE_DATE = date(2026, 11, 26)
EXAMPLE_START = datetime(2026, 11, 26, 11, tzinfo=UTC)  # 06:00 New York


async def habit(
    db: AsyncSession,
    user_id: UUID,
    *,
    name: str = "Pushups",
    unit: str = "reps",
    target: int = 50,
    chunk: int = 10,
    position: int = 0,
    effective_from: date = EXAMPLE_DATE,
    archived_from: date | None = None,
) -> Habit:
    return await HabitRepository(db).add(
        Habit(
            user_id=user_id,
            name=name,
            unit=unit,
            chunk=chunk,
            position=position,
            effective_from=effective_from,
            archived_from=archived_from,
            created_at=EXAMPLE_START,
        ),
        target,
    )


async def log(
    db: AsyncSession,
    user_id: UUID,
    habit_id: UUID,
    *,
    amount: int = 10,
    logged_at: datetime = EXAMPLE_START + timedelta(hours=3),
    day: date = EXAMPLE_DATE,
    source: str = "app",
    undone_at: datetime | None = None,
    log_id: UUID | None = None,
) -> Log:
    row = Log(
        id=log_id or uuid4(),
        user_id=user_id,
        habit_id=habit_id,
        amount=amount,
        logged_at=logged_at,
        received_at=logged_at,
        source=source,
        date=day,
        undone_at=undone_at,
    )
    await LogRepository(db).insert(row)
    return row


async def day(
    db: AsyncSession,
    user_id: UUID,
    *,
    on: date = EXAMPLE_DATE,
    starts_at: datetime = EXAMPLE_START,
    hours: int = 18,
    starting_lead: Fraction = Fraction(100),
) -> Day:
    return await DayRepository(db).add(
        Day(
            user_id=user_id,
            date=on,
            starts_at=starts_at,
            ends_at=starts_at + timedelta(hours=hours),
            starting_lead=starting_lead,
        )
    )


async def key(
    db: AsyncSession, user_id: UUID, kind: str, *, revoked: bool = False
) -> str:
    """Store a key of `kind` and return its secret. Only the digest is stored."""
    secret = "ftg_" + secrets.token_urlsafe(32)
    await KeyRepository(db).add(
        Key(
            user_id=user_id,
            kind=kind,
            name=f"test {kind} key",
            digest=digest(secret),
            created_at=EXAMPLE_START,
            revoked_at=EXAMPLE_START if revoked else None,
        )
    )
    return secret
