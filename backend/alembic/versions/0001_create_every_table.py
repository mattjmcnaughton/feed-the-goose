"""Create every table of TDD §5.2, with cascading deletes from users.

Leads are exact fractions stored as text, such as `100/3` (models/base.py).

Revision ID: 0001
Revises:
Create Date: 2026-11-26
"""

from collections.abc import Sequence

import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

from alembic import op

revision: str = "0001"
down_revision: str | None = None
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "users",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("identity_subject", sa.Text(), nullable=False),
        sa.Column("email", sa.Text(), nullable=False),
        sa.Column("display_name", sa.Text(), nullable=False),
        sa.Column("pursuer", sa.Text(), nullable=False),
        sa.Column("handle", sa.Text(), nullable=True),
        sa.Column("public", sa.Boolean(), nullable=False),
        sa.Column("reminders_enabled", sa.Boolean(), nullable=False),
        sa.Column("reminder_lead_below", sa.Integer(), nullable=False),
        sa.Column("quiet_hours_start", sa.Time(), nullable=True),
        sa.Column("quiet_hours_end", sa.Time(), nullable=True),
        sa.Column("chase_changed_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("reminders_planned_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_users")),
        sa.UniqueConstraint("handle", name=op.f("uq_users_handle")),
        sa.UniqueConstraint("identity_subject", name=op.f("uq_users_identity_subject")),
    )
    op.create_table(
        "day_settings",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("user_id", sa.Uuid(), nullable=False),
        sa.Column("effective_from", sa.Date(), nullable=False),
        sa.Column("time_zone", sa.Text(), nullable=False),
        sa.Column("day_start", sa.Time(), nullable=False),
        sa.Column("day_end", sa.Time(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.ForeignKeyConstraint(
            ["user_id"],
            ["users.id"],
            name=op.f("fk_day_settings_user_id_users"),
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_day_settings")),
        sa.UniqueConstraint(
            "user_id",
            "effective_from",
            name=op.f("uq_day_settings_user_id_effective_from"),
        ),
    )
    op.create_table(
        "days",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("user_id", sa.Uuid(), nullable=False),
        sa.Column("date", sa.Date(), nullable=False),
        sa.Column("starts_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("ends_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("starting_lead", sa.Text(), nullable=False),
        sa.Column("result", sa.Text(), nullable=True),
        sa.Column("end_lead", sa.Text(), nullable=True),
        sa.Column("caught_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("streak_after", sa.Integer(), nullable=True),
        sa.Column("settled_at", sa.DateTime(timezone=True), nullable=True),
        sa.CheckConstraint(
            "result IS NULL OR result IN ('complete', 'short', 'caught')",
            name=op.f("ck_days_result_settled"),
        ),
        sa.ForeignKeyConstraint(
            ["user_id"],
            ["users.id"],
            name=op.f("fk_days_user_id_users"),
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_days")),
        sa.UniqueConstraint("user_id", "date", name=op.f("uq_days_user_id_date")),
    )
    op.create_table(
        "habits",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("user_id", sa.Uuid(), nullable=False),
        sa.Column("name", sa.Text(), nullable=False),
        sa.Column("unit", sa.Text(), nullable=False),
        sa.Column("chunk", sa.Integer(), nullable=False),
        sa.Column("position", sa.Integer(), nullable=False),
        sa.Column("effective_from", sa.Date(), nullable=False),
        sa.Column("archived_from", sa.Date(), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.CheckConstraint("chunk > 0", name=op.f("ck_habits_chunk_positive")),
        sa.ForeignKeyConstraint(
            ["user_id"],
            ["users.id"],
            name=op.f("fk_habits_user_id_users"),
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_habits")),
    )
    op.create_index(op.f("ix_habits_user_id"), "habits", ["user_id"], unique=False)
    op.create_table(
        "installations",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("user_id", sa.Uuid(), nullable=False),
        sa.Column("installation_id", sa.Text(), nullable=False),
        sa.Column("apns_token", sa.Text(), nullable=True),
        sa.Column("widget_push_token", sa.Text(), nullable=True),
        sa.Column("environment", sa.Text(), nullable=False),
        sa.Column("app_version", sa.Text(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.CheckConstraint(
            "environment IN ('sandbox', 'production')",
            name=op.f("ck_installations_environment"),
        ),
        sa.ForeignKeyConstraint(
            ["user_id"],
            ["users.id"],
            name=op.f("fk_installations_user_id_users"),
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_installations")),
        sa.UniqueConstraint(
            "user_id",
            "installation_id",
            name=op.f("uq_installations_user_id_installation_id"),
        ),
    )
    op.create_table(
        "keys",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("user_id", sa.Uuid(), nullable=False),
        sa.Column("kind", sa.Text(), nullable=False),
        sa.Column("name", sa.Text(), nullable=False),
        sa.Column("digest", sa.Text(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("last_used_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("revoked_at", sa.DateTime(timezone=True), nullable=True),
        sa.CheckConstraint("kind IN ('api', 'mcp')", name=op.f("ck_keys_kind")),
        sa.ForeignKeyConstraint(
            ["user_id"],
            ["users.id"],
            name=op.f("fk_keys_user_id_users"),
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_keys")),
        sa.UniqueConstraint("digest", name=op.f("uq_keys_digest")),
    )
    op.create_index(op.f("ix_keys_user_id"), "keys", ["user_id"], unique=False)
    op.create_table(
        "push_deliveries",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("user_id", sa.Uuid(), nullable=False),
        sa.Column("installation_id", sa.Text(), nullable=False),
        sa.Column("payload", postgresql.JSONB(astext_type=sa.Text()), nullable=False),
        sa.Column("sent_at", sa.DateTime(timezone=True), nullable=False),
        sa.ForeignKeyConstraint(
            ["user_id"],
            ["users.id"],
            name=op.f("fk_push_deliveries_user_id_users"),
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_push_deliveries")),
    )
    op.create_index(
        op.f("ix_push_deliveries_user_id"), "push_deliveries", ["user_id"], unique=False
    )
    op.create_table(
        "push_jobs",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("user_id", sa.Uuid(), nullable=False),
        sa.Column("date", sa.Date(), nullable=False),
        sa.Column("kind", sa.Text(), nullable=False),
        sa.Column("due_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("payload", postgresql.JSONB(astext_type=sa.Text()), nullable=False),
        sa.Column("sent_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("attempts", sa.Integer(), nullable=False),
        sa.ForeignKeyConstraint(
            ["user_id"],
            ["users.id"],
            name=op.f("fk_push_jobs_user_id_users"),
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_push_jobs")),
        sa.UniqueConstraint(
            "user_id", "date", "kind", name=op.f("uq_push_jobs_user_id_date_kind")
        ),
    )
    op.create_index(op.f("ix_push_jobs_due_at"), "push_jobs", ["due_at"], unique=False)
    op.create_table(
        "sessions",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("user_id", sa.Uuid(), nullable=False),
        sa.Column("token_digest", sa.Text(), nullable=False),
        sa.Column("device_name", sa.Text(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("last_used_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("expires_at", sa.DateTime(timezone=True), nullable=False),
        sa.ForeignKeyConstraint(
            ["user_id"],
            ["users.id"],
            name=op.f("fk_sessions_user_id_users"),
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_sessions")),
        sa.UniqueConstraint("token_digest", name=op.f("uq_sessions_token_digest")),
    )
    op.create_index(op.f("ix_sessions_user_id"), "sessions", ["user_id"], unique=False)
    op.create_table(
        "habit_targets",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("habit_id", sa.Uuid(), nullable=False),
        sa.Column("effective_from", sa.Date(), nullable=False),
        sa.Column("target", sa.Integer(), nullable=False),
        sa.CheckConstraint("target > 0", name=op.f("ck_habit_targets_target_positive")),
        sa.ForeignKeyConstraint(
            ["habit_id"],
            ["habits.id"],
            name=op.f("fk_habit_targets_habit_id_habits"),
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_habit_targets")),
        sa.UniqueConstraint(
            "habit_id",
            "effective_from",
            name=op.f("uq_habit_targets_habit_id_effective_from"),
        ),
    )
    op.create_table(
        "logs",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("user_id", sa.Uuid(), nullable=False),
        sa.Column("habit_id", sa.Uuid(), nullable=False),
        sa.Column("amount", sa.Integer(), nullable=False),
        sa.Column("logged_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("received_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("source", sa.Text(), nullable=False),
        sa.Column("date", sa.Date(), nullable=False),
        sa.Column("undone_at", sa.DateTime(timezone=True), nullable=True),
        sa.CheckConstraint(
            "source IN ('app', 'widget', 'shortcuts', 'api', 'mcp')",
            name=op.f("ck_logs_source"),
        ),
        sa.CheckConstraint("amount > 0", name=op.f("ck_logs_amount_positive")),
        sa.ForeignKeyConstraint(
            ["habit_id"],
            ["habits.id"],
            name=op.f("fk_logs_habit_id_habits"),
            ondelete="CASCADE",
        ),
        sa.ForeignKeyConstraint(
            ["user_id"],
            ["users.id"],
            name=op.f("fk_logs_user_id_users"),
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_logs")),
    )
    op.create_index(
        op.f("ix_logs_user_id_date"), "logs", ["user_id", "date"], unique=False
    )


def downgrade() -> None:
    op.drop_index(op.f("ix_logs_user_id_date"), table_name="logs")
    op.drop_table("logs")
    op.drop_table("habit_targets")
    op.drop_index(op.f("ix_sessions_user_id"), table_name="sessions")
    op.drop_table("sessions")
    op.drop_index(op.f("ix_push_jobs_due_at"), table_name="push_jobs")
    op.drop_table("push_jobs")
    op.drop_index(op.f("ix_push_deliveries_user_id"), table_name="push_deliveries")
    op.drop_table("push_deliveries")
    op.drop_index(op.f("ix_keys_user_id"), table_name="keys")
    op.drop_table("keys")
    op.drop_table("installations")
    op.drop_index(op.f("ix_habits_user_id"), table_name="habits")
    op.drop_table("habits")
    op.drop_table("days")
    op.drop_table("day_settings")
    op.drop_table("users")
