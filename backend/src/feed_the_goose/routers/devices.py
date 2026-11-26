"""Device registration (API spec "Devices and push").

A stub from T02: each route answers 501 `not_implemented` until T09 lands.
"""

from uuid import UUID

from fastapi import APIRouter, Response

from feed_the_goose.dtos.devices import DeviceRegistration
from feed_the_goose.dtos.errors import ProblemType as P
from feed_the_goose.errors import not_implemented, problems

router = APIRouter(prefix="/v1/me/devices", tags=["devices"])


@router.put(
    "/{installation_id}",
    status_code=204,
    response_class=Response,
    operation_id="registerDevice",
    responses=problems(P.unauthenticated, P.invalid),
)
async def register_device(installation_id: UUID, body: DeviceRegistration) -> None:
    """Register or refresh this installation's push tokens."""
    raise not_implemented()


@router.delete(
    "/{installation_id}",
    status_code=204,
    response_class=Response,
    operation_id="deleteDevice",
    responses=problems(P.unauthenticated, P.invalid),
)
async def delete_device(installation_id: UUID) -> None:
    raise not_implemented()
