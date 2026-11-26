"""API and MCP keys (API spec "Keys")."""

from enum import StrEnum
from uuid import UUID

from pydantic import Field

from feed_the_goose.dtos.common import Dto, Instant


class KeyKind(StrEnum):
    """Where a key works: `api` at /v1, `mcp` at /mcp."""

    api = "api"
    mcp = "mcp"


class KeyCreate(Dto):
    kind: KeyKind
    name: str = Field(min_length=1)


class Key(Dto):
    id: UUID
    kind: KeyKind
    name: str
    created_at: Instant
    last_used_at: Instant | None


class KeyCreated(Key):
    """A new key. `secret` is returned this once only."""

    secret: str
