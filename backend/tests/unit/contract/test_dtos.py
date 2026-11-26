"""Contract choices that the fixtures alone would not catch."""

from datetime import UTC, datetime, timedelta, timezone
from uuid import UUID

import pytest
from pydantic import ValidationError

from feed_the_goose.dtos.habits import HabitCreate
from feed_the_goose.dtos.keys import Key, KeyKind


def test_instants_are_sent_in_utc_to_the_whole_second():
    created = datetime(
        2026, 11, 26, 18, 0, 0, 123456, tzinfo=timezone(-timedelta(hours=5))
    )
    key = Key(
        id=UUID(int=1),
        kind=KeyKind.api,
        name="Scripts",
        created_at=created,
        last_used_at=datetime(2026, 11, 27, 4, 59, 59, 999999, tzinfo=UTC),
    )

    dumped = key.model_dump(mode="json")

    assert dumped["created_at"] == "2026-11-26T23:00:00Z"
    assert dumped["last_used_at"] == "2026-11-27T04:59:59Z"


def test_requests_refuse_unknown_fields_and_responses_ignore_them():
    with pytest.raises(ValidationError):
        HabitCreate.model_validate(
            {"name": "Pushups", "unit": "reps", "target": 50, "chunk": 10, "x": 1}
        )

    key = Key.model_validate(
        {
            "id": str(UUID(int=1)),
            "kind": "api",
            "name": "Scripts",
            "created_at": "2026-11-26T23:00:00Z",
            "last_used_at": None,
            "added_later": True,
        }
    )
    assert "added_later" not in key.model_dump()
