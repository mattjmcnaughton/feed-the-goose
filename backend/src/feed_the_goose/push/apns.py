"""Sends alerts through Apple's push service (TDD §5.9).

HTTP/2 only, with a provider token: an ES256 JWT signed with the team's `.p8` key.
Apple accepts a token for an hour and refuses one refreshed more than every twenty
minutes, so one is reused for fifty.
"""

from datetime import datetime, timedelta
from typing import Any

import httpx
import structlog
from joserfc import jwt
from joserfc.jwk import ECKey

from feed_the_goose.clock import Clock
from feed_the_goose.models import Installation
from feed_the_goose.push.sender import Outcome

HOSTS = {
    "sandbox": "https://api.sandbox.push.apple.com",
    "production": "https://api.push.apple.com",
}
TOKEN_REUSE = timedelta(minutes=50)

log = structlog.get_logger()


class ApnsSender:
    def __init__(
        self,
        *,
        key_pem: str,
        key_id: str,
        team_id: str,
        topic: str,
        clock: Clock,
        http: httpx.AsyncClient,
        base_url: str | None = None,
    ) -> None:
        """`http` must speak HTTP/2 only. `base_url` replaces Apple's hosts, for
        tests."""
        self._key = ECKey.import_key(key_pem)
        self._key_id = key_id
        self._team_id = team_id
        self._topic = topic
        self._clock = clock
        self._http = http
        self._base_url = base_url
        self._token: tuple[datetime, str] | None = None

    async def send(
        self, installation: Installation, payload: dict[str, Any]
    ) -> Outcome:
        if installation.apns_token is None:
            return Outcome.UNREGISTERED
        base = self._base_url or HOSTS[installation.environment]
        try:
            response = await self._http.post(
                f"{base}/3/device/{installation.apns_token}",
                json=payload,
                headers={
                    "authorization": f"bearer {self._provider_token()}",
                    "apns-topic": self._topic,
                    "apns-push-type": "alert",
                    "apns-priority": "10",
                },
            )
        except httpx.HTTPError as e:
            log.warning("apns_unreachable", error=type(e).__name__)
            return Outcome.FAILED
        if response.status_code == 200:
            return Outcome.SENT
        if response.status_code == 410:
            return Outcome.UNREGISTERED
        log.warning("apns_refused", status=response.status_code, body=response.text)
        return Outcome.FAILED

    def _provider_token(self) -> str:
        now = self._clock.now()
        if self._token is None or now - self._token[0] >= TOKEN_REUSE:
            token = jwt.encode(
                {"alg": "ES256", "kid": self._key_id},
                {"iss": self._team_id, "iat": int(now.timestamp())},
                self._key,
            )
            self._token = (now, token)
        return self._token[1]
