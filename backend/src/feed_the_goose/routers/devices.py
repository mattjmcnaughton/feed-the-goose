"""Device registration (API spec "Devices and push")."""

from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Depends, Response

from feed_the_goose.controllers import devices as controller
from feed_the_goose.deps import ApiPrincipal, session_or_api_key, wiring
from feed_the_goose.dtos.devices import DeviceRegistration
from feed_the_goose.dtos.errors import ProblemType as P
from feed_the_goose.errors import problems
from feed_the_goose.wiring import Wiring

WiringDep = Annotated[Wiring, Depends(wiring)]

router = APIRouter(
    prefix="/v1/me/devices",
    tags=["devices"],
    dependencies=[Depends(session_or_api_key)],
)


@router.put(
    "/{installation_id}",
    status_code=204,
    response_class=Response,
    operation_id="registerDevice",
    responses=problems(P.unauthenticated, P.invalid),
)
async def register_device(
    installation_id: UUID,
    body: DeviceRegistration,
    principal: ApiPrincipal,
    w: WiringDep,
) -> None:
    """Register or refresh this installation's push tokens."""
    await controller.register_device(w.installations, principal, installation_id, body)


@router.delete(
    "/{installation_id}",
    status_code=204,
    response_class=Response,
    operation_id="deleteDevice",
    responses=problems(P.unauthenticated, P.invalid),
)
async def delete_device(
    installation_id: UUID, principal: ApiPrincipal, w: WiringDep
) -> None:
    await controller.delete_device(w.installations, principal, installation_id)
