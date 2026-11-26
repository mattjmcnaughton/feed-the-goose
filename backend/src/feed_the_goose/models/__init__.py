"""SQLAlchemy models (TDD §5.2). Separate from the API's DTOs.

Importing this package registers every table on `Base.metadata`.
"""

from feed_the_goose.models.base import Base
from feed_the_goose.models.chase import Day, Log
from feed_the_goose.models.credentials import Key, Session
from feed_the_goose.models.habits import Habit, HabitTarget
from feed_the_goose.models.push import Installation, PushDelivery, PushJob
from feed_the_goose.models.users import DaySettings, User

__all__ = [
    "Base",
    "Day",
    "DaySettings",
    "Habit",
    "HabitTarget",
    "Installation",
    "Key",
    "Log",
    "PushDelivery",
    "PushJob",
    "Session",
    "User",
]
