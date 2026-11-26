"""Maps the device DTOs to the installation service."""

from uuid import UUID

from feed_the_goose.dtos.devices import DeviceRegistration
from feed_the_goose.dtos.errors import ProblemType
from feed_the_goose.errors import ProblemError
from feed_the_goose.services.auth import Principal, UnauthenticatedError
from feed_the_goose.services.installations import InstallationService, Registration


async def register_device(
    installations: InstallationService,
    principal: Principal,
    installation_id: UUID,
    body: DeviceRegistration,
) -> None:
    registration = Registration(
        apns_token=body.apns_token,
        widget_push_token=body.widget_push_token,
        environment=body.environment.value,
        app_version=body.app_version,
    )
    try:
        await installations.register(principal, installation_id, registration)
    except UnauthenticatedError:
        raise ProblemError(ProblemType.unauthenticated) from None


async def delete_device(
    installations: InstallationService, principal: Principal, installation_id: UUID
) -> None:
    await installations.delete(principal, installation_id)
