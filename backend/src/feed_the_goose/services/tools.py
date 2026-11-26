"""The tool catalog, for MCP and a future in-app assistant (TDD §5.7, constitution §6).

Each tool goes through the same controller and service as its REST route, so the
rules run in one place and a tool's result has the route's shape. Two things
differ, because a model reads the result:

- Habit names and units are user text, so they come back as `{"untrusted": "..."}`.
- An error is a code and fixed text. It never echoes the input or an exception.

Excluded on purpose: anything that edits or deletes habits, keys, settings or the
account.
"""

from collections.abc import Awaitable, Callable
from dataclasses import dataclass
from datetime import timedelta
from typing import TYPE_CHECKING, Any, Literal
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field
from pydantic import ValidationError as PydanticValidationError

from feed_the_goose.controllers import chase as chase_controller
from feed_the_goose.controllers import days as days_controller
from feed_the_goose.controllers import habits as habits_controller
from feed_the_goose.controllers import logs as logs_controller
from feed_the_goose.dtos.chase import Chase
from feed_the_goose.dtos.errors import ProblemType
from feed_the_goose.dtos.logs import LogCreate, LogResult, Source
from feed_the_goose.errors import ProblemError
from feed_the_goose.services.accounts import current_day
from feed_the_goose.services.auth import Principal

if TYPE_CHECKING:
    from feed_the_goose.wiring import Wiring

Kind = Literal["read", "write"]

# The fixed text for each refusal a tool can meet.
_MESSAGES: dict[ProblemType, str] = {
    ProblemType.not_found: "No such habit or log.",
    ProblemType.no_chase: "There is no chase today. Habits are added in the app.",
    ProblemType.day_settled: "That day has settled, so its logs cannot change.",
    ProblemType.invalid: "The request is invalid.",
    ProblemType.unauthenticated: "Send an MCP key.",
}


class ToolError(Exception):
    """A refusal the caller can show. `message` is fixed text."""

    def __init__(self, code: str, message: str) -> None:
        super().__init__(f"{code}: {message}")
        self.code, self.message = code, message


INVALID_ARGUMENTS = ToolError("invalid_arguments", "Match the tool's input schema.")
UNKNOWN_TOOL = ToolError("unknown_tool", "No tool has that name.")
FAILED = ToolError("internal", "The tool failed. Try again later.")


@dataclass(frozen=True)
class ToolContext:
    wiring: "Wiring"
    principal: Principal


class _Input(BaseModel):
    model_config = ConfigDict(extra="forbid")


class NoInput(_Input):
    pass


class HistoryInput(_Input):
    days: int = Field(
        default=30, ge=1, le=366, description="How many days back, today included."
    )


class LogHabitInput(_Input):
    habit_id: UUID = Field(description="From list_habits or get_chase.")
    amount: int | None = Field(
        default=None, gt=0, description="Defaults to the habit's chunk."
    )
    idempotency_key: UUID = Field(
        description="A new UUID per log. Sending it again returns the same log."
    )


class UndoLogInput(_Input):
    log_id: UUID = Field(description="The `id` of the log, from log_habit.")


Json = dict[str, Any]


@dataclass(frozen=True)
class CatalogTool:
    name: str
    kind: Kind
    description: str
    input: type[_Input]
    run: Callable[[ToolContext, Any], Awaitable[Json]]


def _untrusted(habit: Json) -> Json:
    return {
        **habit,
        "name": {"untrusted": habit["name"]},
        "unit": {"untrusted": habit["unit"]},
    }


def _chase(chase: Chase) -> Json:
    body = chase.model_dump(mode="json")
    return {**body, "habits": [_untrusted(h) for h in body["habits"]]}


async def get_chase(ctx: ToolContext, _: NoInput) -> Json:
    w = ctx.wiring
    return _chase(await chase_controller.get_today(w.chase, ctx.principal.user_id))


async def list_habits(ctx: ToolContext, _: NoInput) -> Json:
    habits = await habits_controller.list_habits(ctx.wiring.habits, ctx.principal)
    return {"habits": [_untrusted(h.model_dump(mode="json")) for h in habits]}


async def get_history(ctx: ToolContext, args: HistoryInput) -> Json:
    w = ctx.wiring
    async with w.sessions.begin() as db:
        today = await current_day(
            db,
            ctx.principal.user_id,
            w.clock.now(),
            steps_per_day=w.settings.steps_per_day,
        )
    first = today.date - timedelta(days=args.days - 1)
    days = await days_controller.list_days(
        w.chase, ctx.principal.user_id, first, today.date
    )
    return {"days": [d.model_dump(mode="json") for d in days]}


async def log_habit(ctx: ToolContext, args: LogHabitInput) -> Json:
    w = ctx.wiring
    body = LogCreate(
        id=args.idempotency_key,
        habit_id=args.habit_id,
        amount=args.amount,
        logged_at=w.clock.now(),
        source=Source.mcp,
    )
    result, _ = await logs_controller.create_log(w.logs, ctx.principal.user_id, body)
    return _log_result(result)


async def undo_log(ctx: ToolContext, args: UndoLogInput) -> Json:
    w = ctx.wiring
    return _log_result(
        await logs_controller.undo_log(w.logs, ctx.principal.user_id, args.log_id)
    )


def _log_result(result: LogResult) -> Json:
    return {**result.model_dump(mode="json"), "chase": _chase(result.chase)}


CATALOG: tuple[CatalogTool, ...] = (
    CatalogTool(
        "get_chase",
        "read",
        "Today's chase: the lead over the pursuer, each habit's progress and the "
        "streak. Same as GET /v1/chase/today.",
        NoInput,
        get_chase,
    ),
    CatalogTool(
        "list_habits",
        "read",
        "The active and upcoming habits, with their IDs, targets and chunks.",
        NoInput,
        list_habits,
    ),
    CatalogTool(
        "get_history",
        "read",
        "Each recent day's result, newest last, ending with today.",
        HistoryInput,
        get_history,
    ),
    CatalogTool(
        "log_habit",
        "write",
        "Log an amount of a habit now. Returns the log, what it earned and the "
        "chase. Retrying with the same idempotency_key makes no second log.",
        LogHabitInput,
        log_habit,
    ),
    CatalogTool(
        "undo_log",
        "write",
        "Undo a log whose day has not settled. Undoing twice is the same as once.",
        UndoLogInput,
        undo_log,
    ),
)

TOOLS = {tool.name: tool for tool in CATALOG}


def input_schema(tool: CatalogTool) -> Json:
    return tool.input.model_json_schema()


async def call_tool(ctx: ToolContext, name: str, arguments: Json) -> Json:
    """Run a tool. Raises `ToolError`, whose message is fixed text, on any failure."""
    tool = TOOLS.get(name)
    if tool is None:
        raise UNKNOWN_TOOL
    try:
        args = tool.input.model_validate(arguments)
    except PydanticValidationError:
        raise INVALID_ARGUMENTS from None
    try:
        return await tool.run(ctx, args)
    except ProblemError as error:
        kind = error.problem.type
        if kind not in _MESSAGES:
            raise FAILED from None
        raise ToolError(kind.value, _MESSAGES[kind]) from None
