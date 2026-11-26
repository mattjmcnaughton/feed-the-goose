"""Maps the Me DTOs to the account service and back."""

from collections.abc import Generator
from contextlib import contextmanager
from datetime import time

from feed_the_goose.dtos.errors import FieldError, ProblemType
from feed_the_goose.dtos.me import PendingDay, User, UserUpdate
from feed_the_goose.errors import ProblemError
from feed_the_goose.services.accounts import (
    Account,
    AccountChanges,
    AccountService,
    InvalidFieldsError,
)
from feed_the_goose.services.auth import Principal, UnauthenticatedError


@contextmanager
def _problems() -> Generator[None]:
    try:
        yield
    except UnauthenticatedError:
        raise ProblemError(ProblemType.unauthenticated) from None
    except InvalidFieldsError as e:
        raise ProblemError(
            ProblemType.invalid,
            errors=[FieldError(field=f, message=m) for f, m in e.errors.items()],
        ) from None


async def get_me(accounts: AccountService, principal: Principal) -> User:
    with _problems():
        return user_dto(await accounts.get(principal))


async def update_me(
    accounts: AccountService, principal: Principal, body: UserUpdate
) -> User:
    changes = AccountChanges(
        display_name=body.display_name,
        pursuer=None if body.pursuer is None else body.pursuer.value,
        time_zone=body.time_zone,
        day_start=_time(body.day_start),
        day_end=_time(body.day_end),
    )
    with _problems():
        return user_dto(await accounts.update(principal, changes))


async def delete_me(accounts: AccountService, principal: Principal) -> None:
    with _problems():
        await accounts.delete(principal)


def _time(value: str | None) -> time | None:
    return None if value is None else time.fromisoformat(value)


def _hhmm(value: time) -> str:
    return value.strftime("%H:%M")


def user_dto(account: Account) -> User:
    user, current, pending = account.user, account.current, account.pending
    return User(
        id=user.id,
        email=user.email,
        display_name=user.display_name,
        pursuer=user.pursuer,  # type: ignore[arg-type]  # validated by the DTO
        time_zone=current.time_zone,
        day_start=_hhmm(current.day_start),
        day_end=_hhmm(current.day_end),
        pending=None
        if pending is None
        else PendingDay(
            effective_from=pending.effective_from,
            time_zone=pending.time_zone,
            day_start=_hhmm(pending.day_start),
            day_end=_hhmm(pending.day_end),
        ),
        created_at=user.created_at,
    )
