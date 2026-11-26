"""Maps the key DTOs to the key service and back."""

from uuid import UUID

from feed_the_goose.dtos import keys as dto
from feed_the_goose.dtos.errors import ProblemType
from feed_the_goose.errors import ProblemError
from feed_the_goose.models import Key
from feed_the_goose.services.auth import CredentialKind, Principal
from feed_the_goose.services.keys import KeyNotFoundError, KeyService


async def list_keys(keys: KeyService, principal: Principal) -> list[dto.Key]:
    return [_key(k) for k in await keys.listed(principal)]


async def create_key(
    keys: KeyService, principal: Principal, body: dto.KeyCreate
) -> dto.KeyCreated:
    created = await keys.create(principal, CredentialKind(body.kind.value), body.name)
    return dto.KeyCreated(**_key(created.key).model_dump(), secret=created.secret)


async def delete_key(keys: KeyService, principal: Principal, key_id: UUID) -> None:
    try:
        await keys.revoke(principal, key_id)
    except KeyNotFoundError:
        raise ProblemError(ProblemType.not_found) from None


def _key(key: Key) -> dto.Key:
    return dto.Key(
        id=key.id,
        kind=dto.KeyKind(key.kind),
        name=key.name,
        created_at=key.created_at,
        last_used_at=key.last_used_at,
    )
