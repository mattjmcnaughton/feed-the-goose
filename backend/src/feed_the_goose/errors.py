"""Problem-JSON errors (TDD §5.11).

Every error answers `application/problem+json` with a `type` from `ProblemType`. One
handler builds them, and no response echoes an exception's text.
"""

from typing import Any

from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse

from feed_the_goose.dtos.errors import FieldError, Problem, ProblemType

MEDIA_TYPE = "application/problem+json"

_STATUS_AND_TITLE: dict[ProblemType, tuple[int, str]] = {
    ProblemType.unauthenticated: (401, "Not signed in"),
    ProblemType.identity_not_admitted: (403, "This account is not admitted"),
    ProblemType.not_found: (404, "Not found"),
    ProblemType.no_chase: (404, "No chase today"),
    ProblemType.day_settled: (409, "That day has settled"),
    ProblemType.handle_taken: (409, "That handle is taken"),
    ProblemType.invalid: (422, "The request is invalid"),
    ProblemType.rate_limited: (429, "Too many requests"),
    ProblemType.not_implemented: (501, "Not implemented yet"),
}


class ProblemError(Exception):
    """Raise to answer with a problem body. `detail` must be fixed text."""

    def __init__(
        self,
        type: ProblemType,  # noqa: A002 - the field's name in the contract
        detail: str | None = None,
        errors: list[FieldError] | None = None,
        headers: dict[str, str] | None = None,
    ) -> None:
        status, title = _STATUS_AND_TITLE[type]
        super().__init__(type.value)
        self.problem = Problem(
            type=type, title=title, status=status, detail=detail, errors=errors
        )
        self.headers = headers


def not_implemented() -> ProblemError:
    """The error a route answers until its ticket lands."""
    return ProblemError(ProblemType.not_implemented)


def problems(*types: ProblemType) -> dict[int | str, dict[str, Any]]:
    """Declare a route's error responses in OpenAPI, for `responses=`."""
    return {
        _STATUS_AND_TITLE[t][0]: {
            "description": " or ".join(
                f"`{u.value}`" for u in types if _STATUS_AND_TITLE[u][0] == status
            ),
            "content": {MEDIA_TYPE: {"schema": {"$ref": _ref("Problem")}}},
        }
        for t in types
        for status in [_STATUS_AND_TITLE[t][0]]
    }


def install(app: FastAPI) -> None:
    """Register the handlers and add the problem schemas to the app's OpenAPI."""
    app.exception_handler(ProblemError)(_problem_handler)
    app.exception_handler(RequestValidationError)(_validation_handler)

    build = app.openapi

    def openapi() -> dict[str, Any]:
        if app.openapi_schema:
            return app.openapi_schema
        schema = build()  # cached by FastAPI, so the changes below are kept
        # FastAPI's own 422 body is replaced by the problem body it really sends.
        invalid = problems(ProblemType.invalid)[422]
        for path in schema["paths"].values():
            for operation in path.values():
                if "422" in operation["responses"]:
                    operation["responses"]["422"] = invalid
        problem = Problem.model_json_schema(ref_template=_ref("{model}"))
        defs = problem.pop("$defs")
        schemas = schema.setdefault("components", {}).setdefault("schemas", {})
        schemas.pop("HTTPValidationError", None)
        schemas.pop("ValidationError", None)
        schemas.update(defs, Problem=problem)
        return schema

    app.openapi = openapi


def _ref(name: str) -> str:
    return f"#/components/schemas/{name}"


def _response(problem: Problem, headers: dict[str, str] | None = None) -> JSONResponse:
    return JSONResponse(
        problem.model_dump(mode="json", exclude_none=True),
        status_code=problem.status,
        media_type=MEDIA_TYPE,
        headers=headers,
    )


async def _problem_handler(_: Request, exc: ProblemError) -> JSONResponse:
    return _response(exc.problem, exc.headers)


async def _validation_handler(_: Request, exc: RequestValidationError) -> JSONResponse:
    errors = [
        FieldError(
            field=".".join(str(part) for part in error["loc"][1:]) or error["loc"][0],
            message=error["msg"],
        )
        for error in exc.errors()
    ]
    return _response(ProblemError(ProblemType.invalid, errors=errors).problem)
