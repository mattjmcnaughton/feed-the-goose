from datetime import UTC, datetime, timedelta, timezone

import pytest

from feed_the_goose.clock import FixedClock, SystemClock


def test_fixed_clock_reports_its_instant_in_utc():
    eastern = timezone(timedelta(hours=-5))
    clock = FixedClock(datetime(2026, 11, 26, 18, 0, tzinfo=eastern))

    assert clock.now() == datetime(2026, 11, 26, 23, 0, tzinfo=UTC)
    assert clock.now().utcoffset() == timedelta(0)


def test_fixed_clock_moves_only_when_set():
    clock = FixedClock(datetime(2026, 11, 26, 11, 0, tzinfo=UTC))
    clock.set(datetime(2026, 11, 26, 12, 0, tzinfo=UTC))

    assert clock.now() == datetime(2026, 11, 26, 12, 0, tzinfo=UTC)


def test_fixed_clock_refuses_a_naive_datetime():
    with pytest.raises(ValueError):
        FixedClock(datetime(2026, 11, 26, 11, 0))


def test_system_clock_is_utc():
    assert SystemClock().now().utcoffset() == timedelta(0)
