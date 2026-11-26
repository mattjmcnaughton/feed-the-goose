"""The reminder worker: `python -m feed_the_goose.worker` (TDD §5.9).

Every few seconds it plans the reminders of users whose chase changed or whose day
is new, then sends the ones that are due. Several workers may run at once: due
reminders are claimed with `FOR UPDATE SKIP LOCKED`.
"""

import asyncio
import contextlib

import structlog

from feed_the_goose import wiring
from feed_the_goose.config import settings
from feed_the_goose.logging import configure_logging

log = structlog.get_logger()


async def run(wired: wiring.Wiring, stop: asyncio.Event) -> None:
    """Run passes until `stop` is set. A failed pass is logged and retried."""
    log.info(
        "worker_started",
        sender="apns" if wired.push.apns_key_path else "recording",
        interval=wired.push.worker_interval_seconds,
    )
    while not stop.is_set():
        try:
            planned, sent = await wired.reminders.run_pass()
            if planned or sent:
                log.info("worker_pass", planned=planned, sent=sent)
        except Exception:
            log.exception("worker_pass_failed")
        with contextlib.suppress(TimeoutError):
            await asyncio.wait_for(stop.wait(), wired.push.worker_interval_seconds)


def main() -> None:
    configure_logging()
    asyncio.run(run(wiring.build(settings), asyncio.Event()))


if __name__ == "__main__":
    main()
