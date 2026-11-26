"""Maps the log DTOs to the log service and back."""

from collections.abc import Generator
from contextlib import contextmanager
from datetime import date
from fractions import Fraction
from uuid import UUID

from feed_the_goose.controllers.chase import chase_dto, rounded
from feed_the_goose.dtos import chase as chase_dtos
from feed_the_goose.dtos import logs as dto
from feed_the_goose.dtos.errors import FieldError, ProblemType
from feed_the_goose.errors import ProblemError
from feed_the_goose.models import Log
from feed_the_goose.services.chase import NoChaseError
from feed_the_goose.services.logs import (
    DaySettledError,
    InvalidLogError,
    LoggedResult,
    LogService,
    NewLog,
    NotFoundError,
)


async def create_log(
    service: LogService, user_id: UUID, body: dto.LogCreate
) -> tuple[dto.LogResult, bool]:
    """The result, and whether the log is new."""
    new = NewLog(
        id=body.id,
        habit_id=body.habit_id,
        amount=body.amount,
        logged_at=body.logged_at,
        source=body.source.value,
    )
    with _problems():
        result = await service.create(user_id, new)
    return _result_dto(result), result.created


async def undo_log(service: LogService, user_id: UUID, log_id: UUID) -> dto.LogResult:
    with _problems():
        result = await service.undo(user_id, log_id)
    return _result_dto(result)


async def list_logs(service: LogService, user_id: UUID, day: date) -> list[dto.Log]:
    return [log_dto(log, steps) for log, steps in await service.for_day(user_id, day)]


def log_dto(log: Log, steps: Fraction) -> dto.Log:
    return dto.Log(
        id=log.id,
        habit_id=log.habit_id,
        amount=log.amount,
        logged_at=log.logged_at,
        source=dto.Source(log.source),
        date=log.date,
        steps=rounded(steps),
        undone_at=log.undone_at,
    )


def _result_dto(result: LoggedResult) -> dto.LogResult:
    return dto.LogResult(
        log=log_dto(result.log, result.steps),
        event=chase_dtos.Event(
            kind=chase_dtos.EventKind(result.event.kind.value),
            habit_id=result.event.habit_id,
            steps=rounded(result.event.steps),
        ),
        chase=chase_dto(result.chase),
    )


@contextmanager
def _problems() -> Generator[None]:
    """Translate the service's errors into problems."""
    try:
        yield
    except NotFoundError:
        raise ProblemError(ProblemType.not_found) from None
    except DaySettledError:
        raise ProblemError(ProblemType.day_settled) from None
    except NoChaseError:
        raise ProblemError(ProblemType.no_chase) from None
    except InvalidLogError as error:
        raise ProblemError(
            ProblemType.invalid,
            errors=[FieldError(field=error.field, message="Value is not valid")],
        ) from None
