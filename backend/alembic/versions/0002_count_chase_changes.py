"""Count a user's chase changes instead of stamping them.

`chase_version` goes up by one, under the user's lock, with each write that
changes the current chase, and the worker stores the version it planned in
`reminders_planned_version`. A timestamp read before the lock could be older than
the last plan; a counter cannot. Every user is planned again once.

Revision ID: 0002
Revises: 0001
Create Date: 2026-11-26
"""

from collections.abc import Sequence

import sqlalchemy as sa

from alembic import op

revision: str = "0002"
down_revision: str | None = "0001"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column(
        "users",
        sa.Column("chase_version", sa.Integer(), server_default="0", nullable=False),
    )
    op.add_column(
        "users", sa.Column("reminders_planned_version", sa.Integer(), nullable=True)
    )
    op.drop_column("users", "chase_changed_at")


def downgrade() -> None:
    op.add_column(
        "users",
        sa.Column("chase_changed_at", sa.DateTime(timezone=True), nullable=True),
    )
    # With no change times, plan every user again.
    op.execute("UPDATE users SET reminders_planned_at = NULL")
    op.drop_column("users", "reminders_planned_version")
    op.drop_column("users", "chase_version")
