"""The streak, the stage, and the next day's starting lead (TDD §5.3).

Pure: the thresholds and the full lead are arguments.
"""

from bisect import bisect_right
from collections.abc import Sequence
from fractions import Fraction

from feed_the_goose.domain.chase import DayState


def streak_after(streak: int, result: DayState) -> int:
    """A complete day adds one, a caught day resets to 0, any other day leaves it."""
    if result is DayState.COMPLETE:
        return streak + 1
    if result is DayState.CAUGHT:
        return 0
    return streak


def stage(streak: int, thresholds: Sequence[int]) -> int:
    """The stage: how many of the ascending thresholds the streak has reached."""
    return bisect_right(thresholds, streak)


def starting_lead_after(
    result: DayState, end_lead: Fraction, *, full_lead: int
) -> Fraction:
    """The next day's starting lead: the end lead after a short day, else full."""
    if result is DayState.RUNNING:
        raise ValueError("a running day has not ended")
    if result is DayState.SHORT:
        return end_lead
    return Fraction(full_lead)
