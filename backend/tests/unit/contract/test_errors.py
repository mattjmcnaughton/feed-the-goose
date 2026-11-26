"""Problem-JSON errors (TDD §5.11), through a small app that installs the handlers."""

import json
from pathlib import Path

from fastapi import FastAPI
from fastapi.testclient import TestClient

from feed_the_goose import errors
from feed_the_goose.app import create_app
from feed_the_goose.dtos.errors import ProblemType
from feed_the_goose.dtos.habits import HabitCreate
from feed_the_goose.errors import ProblemError

FIXTURES = Path(__file__).resolve().parents[4] / "clients" / "fixtures"


def _client() -> TestClient:
    app = FastAPI()
    errors.install(app)

    @app.get("/limited")
    async def limited() -> None:
        raise ProblemError(ProblemType.rate_limited, headers={"Retry-After": "30"})

    @app.post("/habits")
    async def create(body: HabitCreate) -> None:
        return None

    return TestClient(app)


def test_a_problem_error_answers_problem_json():
    response = _client().get("/limited")

    assert response.status_code == 429
    assert response.headers["content-type"] == "application/problem+json"
    assert response.headers["retry-after"] == "30"
    assert response.json() == {
        "type": "rate_limited",
        "title": "Too many requests",
        "status": 429,
    }


def test_a_validation_failure_answers_the_invalid_fixture():
    fixture = json.loads((FIXTURES / "error-invalid.json").read_text())

    response = _client().post("/habits", json=fixture["request"]["body"])

    assert response.status_code == 422
    assert response.headers["content-type"] == "application/problem+json"
    assert response.json() == fixture["response"]["body"]


def test_every_error_response_in_the_schema_is_problem_json():
    schema = create_app().openapi()

    for path, methods in schema["paths"].items():
        for method, operation in methods.items():
            for status, response in operation["responses"].items():
                if status.startswith(("4", "5")):
                    assert list(response["content"]) == ["application/problem+json"], (
                        method,
                        path,
                        status,
                    )
    assert "HTTPValidationError" not in schema["components"]["schemas"]
