"""The problem body every error answers with (API spec "Conventions")."""

from enum import StrEnum

from feed_the_goose.dtos.common import Dto


class ProblemType(StrEnum):
    """What went wrong, for a client to switch on."""

    unauthenticated = "unauthenticated"
    identity_not_admitted = "identity_not_admitted"
    not_found = "not_found"
    no_chase = "no_chase"
    day_settled = "day_settled"
    handle_taken = "handle_taken"
    invalid = "invalid"
    rate_limited = "rate_limited"
    not_implemented = "not_implemented"


class FieldError(Dto):
    """One field that failed validation."""

    field: str
    message: str


class Problem(Dto):
    """An `application/problem+json` body. `errors` is set only for `invalid`."""

    type: ProblemType
    title: str
    status: int
    detail: str | None = None
    errors: list[FieldError] | None = None
