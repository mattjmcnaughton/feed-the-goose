"""The shared fixtures in clients/fixtures/ against the contract (TDD §4).

Each fixture is one exchange. Its request and response must validate against the DTOs
the route declares and serialize back to the same JSON, every operation in
clients/openapi.json needs a fixture, and so does every error type.
"""

import importlib
import json
import pkgutil
import typing
from pathlib import Path
from typing import Any
from urllib.parse import urlsplit

import pytest
from fastapi.routing import APIRoute
from pydantic import TypeAdapter

from feed_the_goose import routers
from feed_the_goose.dtos.errors import Problem, ProblemType
from feed_the_goose.errors import ProblemError

CLIENTS = Path(__file__).resolve().parents[4] / "clients"
FIXTURES = {
    path.stem: json.loads(path.read_text())
    for path in sorted((CLIENTS / "fixtures").glob("*.json"))
}
OPENAPI = json.loads((CLIENTS / "openapi.json").read_text())
ROUTES = [
    route
    for module in pkgutil.iter_modules(routers.__path__)
    for route in importlib.import_module(
        f"{routers.__name__}.{module.name}"
    ).router.routes
    if isinstance(route, APIRoute) and route.path.startswith("/v1/")
]


def _route(fixture: dict[str, Any]) -> APIRoute:
    method = fixture["request"]["method"]
    path = urlsplit(fixture["request"]["path"]).path
    matches = [
        route
        for route in ROUTES
        if method in route.methods and route.path_regex.match(path)
    ]
    assert len(matches) == 1, f"{method} {path} matches {len(matches)} routes"
    return matches[0]


def _response_type(route: APIRoute, status: int) -> Any:
    if status >= 400:
        return Problem
    if status == (route.status_code or 200):
        return route.response_model
    return route.responses[status]["model"]


def _assert_round_trip(type_: Any, body: Any) -> None:
    adapter = TypeAdapter(type_)
    value = adapter.validate_json(json.dumps(body))
    assert adapter.dump_python(value, mode="json", exclude_unset=True) == body


def test_every_operation_has_a_fixture():
    operations = {
        (method.upper(), path): operation["operationId"]
        for path, methods in OPENAPI["paths"].items()
        for method, operation in methods.items()
    }
    covered = set()
    for fixture in FIXTURES.values():
        route = _route(fixture)
        covered.add((fixture["request"]["method"], route.path))

    missing = [op_id for key, op_id in operations.items() if key not in covered]
    assert missing == []
    assert len(operations) == 25


def test_every_error_type_has_a_fixture():
    covered = {
        fixture["response"]["body"]["type"]
        for fixture in FIXTURES.values()
        if fixture["response"]["status"] >= 400
    }

    assert covered == {t.value for t in ProblemType}


@pytest.mark.parametrize("name", FIXTURES)
def test_fixture_matches_its_route(name: str):
    fixture = FIXTURES[name]
    route = _route(fixture)
    request, response = fixture["request"], fixture["response"]

    assert fixture["name"] == name
    declared = OPENAPI["paths"][route.path][request["method"].lower()]["responses"]
    # 429 is reserved and 501 lasts only until a route's ticket lands, so neither is
    # declared on a route.
    assert str(response["status"]) in declared or response["status"] in (429, 501)

    body_type = typing.get_type_hints(route.endpoint).get("body")
    if body_type is None:
        assert request["body"] is None
    elif response["status"] != 422:  # an invalid request does not validate
        _assert_round_trip(body_type, request["body"])

    response_type = _response_type(route, response["status"])
    if response_type is None:
        assert response["body"] is None
    else:
        _assert_round_trip(response_type, response["body"])


@pytest.mark.parametrize(
    "name", [n for n, f in FIXTURES.items() if f["response"]["status"] >= 400]
)
def test_error_fixture_matches_the_server_problem(name: str):
    response = FIXTURES[name]["response"]
    problem = ProblemError(ProblemType(response["body"]["type"])).problem

    assert response["status"] == problem.status == response["body"]["status"]
    assert response["body"]["title"] == problem.title
