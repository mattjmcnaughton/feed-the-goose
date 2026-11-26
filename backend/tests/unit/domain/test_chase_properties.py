"""Properties of the chase over random valid days and logs, in plain pytest.

- The lead never rises without a log.
- Earned never exceeds the steps of a full day.
- The order in which logs arrive does not change the state.
"""

import random
from datetime import date, datetime, time, timedelta
from fractions import Fraction

import pytest

from feed_the_goose.domain.chase import ChaseState, HabitTarget, LogEntry, chase_at
from feed_the_goose.domain.day import DaySettings, DayWindow, day_window

STEPS_PER_DAY = 100
ZONES = ("America/New_York", "America/Los_Angeles", "Europe/London", "Asia/Kolkata")
SEEDS = range(200)


def random_day(rng: random.Random) -> DayWindow:
    start = time(rng.randrange(0, 24), rng.choice((0, 15, 30, 45)))
    length = timedelta(hours=rng.randrange(8, 23))
    end = (datetime.combine(date(2026, 1, 1), start) + length).time()
    settings = DaySettings(time_zone=rng.choice(ZONES), day_start=start, day_end=end)
    day = date(2026, 1, 1) + timedelta(days=rng.randrange(0, 365))
    return day_window(day, settings, steps_per_day=STEPS_PER_DAY)


def random_instant(rng: random.Random, day: DayWindow) -> datetime:
    """Anywhere from the start to two hours after the end, so night logs occur."""
    span = day.ends_at - day.starts_at + timedelta(hours=2)
    return day.starts_at + timedelta(
        minutes=rng.randrange(0, span // timedelta(minutes=1))
    )


def random_case(
    seed: int,
) -> tuple[DayWindow, int, list[HabitTarget], list[LogEntry], random.Random]:
    rng = random.Random(seed)
    day = random_day(rng)
    habits = [
        HabitTarget(habit_id=f"h{i}", target=rng.randrange(1, 100))
        for i in range(rng.randrange(1, 9))
    ]
    logs = [
        LogEntry(
            id=f"log{i:03}",
            habit_id=rng.choice(habits).habit_id,
            amount=rng.randrange(1, 60),
            logged_at=random_instant(rng, day),
        )
        for i in range(rng.randrange(0, 25))
    ]
    return day, rng.randrange(1, 101), habits, logs, rng


def state(
    day: DayWindow,
    lead: int,
    habits: list[HabitTarget],
    logs: list[LogEntry],
    at: datetime,
) -> ChaseState:
    return chase_at(day, Fraction(lead), habits, logs, at, steps_per_day=STEPS_PER_DAY)


@pytest.mark.parametrize("seed", SEEDS)
def test_the_lead_never_rises_without_a_log(seed: int) -> None:
    day, lead, habits, logs, rng = random_case(seed)
    instants = sorted(random_instant(rng, day) for _ in range(6))

    for earlier, later in zip(instants, instants[1:], strict=False):
        made_by_earlier = [log for log in logs if log.logged_at <= earlier]
        before = state(day, lead, habits, made_by_earlier, earlier)
        after = state(day, lead, habits, made_by_earlier, later)
        assert after.lead <= before.lead


@pytest.mark.parametrize("seed", SEEDS)
def test_earned_never_exceeds_a_full_day(seed: int) -> None:
    day, lead, habits, logs, rng = random_case(seed)

    at = day.ends_at + timedelta(hours=2)
    result = state(day, lead, habits, logs, at)

    assert 0 <= result.earned <= STEPS_PER_DAY
    assert sum(o.steps for o in result.outcomes) <= STEPS_PER_DAY


@pytest.mark.parametrize("seed", SEEDS)
def test_arrival_order_does_not_change_the_state(seed: int) -> None:
    day, lead, habits, logs, rng = random_case(seed)
    at = random_instant(rng, day)
    shuffled = logs[:]
    rng.shuffle(shuffled)

    assert state(day, lead, habits, shuffled, at) == state(day, lead, habits, logs, at)
