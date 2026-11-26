"""The public profile page (TDD §5.8).

One self-contained HTML document built with `string.Template` from the pursuer's
template, `<pursuer>.html`. The pursuer's words and art live in that template; this
module fills in published fields only. The display name is the only user text, and it
is escaped.
"""

import base64
from functools import cache
from html import escape
from importlib.resources import files
from string import Template

from feed_the_goose.dtos.common import ChaseState
from feed_the_goose.dtos.profile import PublicProfile

NOT_FOUND = (
    "<!doctype html><html lang=en><meta charset=utf-8>"
    "<title>Not found</title><p>Not found.</p></html>"
)


@cache
def _template(pursuer: str) -> Template:
    return Template((files(__package__) / f"{pursuer}.html").read_text())


@cache
def _font() -> str:
    data = (files(__package__) / "shrikhand.woff2").read_bytes()
    return base64.b64encode(data).decode()


def _run_ended(profile: PublicProfile) -> int:
    """Complete days since the last catch before the shown day: the run a catch on
    the shown day ended. Counted from the published results only."""
    run = 0
    for day in reversed(profile.days[:-1]):
        if day.result is ChaseState.caught:
            break
        run += day.result is ChaseState.complete
    return run


def render(profile: PublicProfile, address: str, *, full_lead: int) -> str:
    """The page for `profile`. `address` is the page's host and path, shown as text;
    `full_lead` is the lead that draws the pursuer at its usual distance."""
    # A complete day's pursuer has stopped at its usual distance, whatever the lead.
    lead = full_lead if profile.state is ChaseState.complete else profile.lead
    distance = min(max(lead / full_lead, 0), 1.3)
    counts = {state: 0 for state in ChaseState}
    for day in profile.days:
        counts[day.result] += 1
    return _template(profile.pursuer).substitute(
        font=_font(),
        state=profile.state.value,
        display_name=escape(profile.display_name),
        address=escape(address),
        complete_days=profile.complete_days,
        days_word="day" if profile.complete_days == 1 else "days",
        stage=profile.stage,
        lead=round(profile.lead),
        run_ended=(run := _run_ended(profile)),
        run="run" if run else "norun",
        distance=f"{min(distance, 1):.3f}",
        overshoot=f"{round(max(0, distance - 1) * 400)}px",
        cells="".join(
            f'<i class="{d.result.value}" title="{d.date}: {d.result.value}"></i>'
            for d in profile.days
        ),
        complete_count=counts[ChaseState.complete],
        short_count=counts[ChaseState.short],
        caught_count=counts[ChaseState.caught],
    )
