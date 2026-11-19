"""activity events + user last login/seen

Revision ID: 0002
Revises: 0001
Create Date: 2026-11-19
"""

from alembic import op
import sqlalchemy as sa

revision = "0002"
down_revision = "0001"
branch_labels = None
depends_on = None


def upgrade():
    op.add_column("users", sa.Column("last_login_at", sa.DateTime(timezone=True)))
    op.add_column("users", sa.Column("last_seen_at", sa.DateTime(timezone=True)))
    op.create_table(
        "activity_events",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("user_id", sa.Integer(), sa.ForeignKey("users.id"), nullable=True),
        sa.Column("category", sa.String(64), nullable=False),
        sa.Column("action", sa.String(128), nullable=False),
        sa.Column("detail", sa.JSON()),
        sa.Column("device_id", sa.String(128)),
        sa.Column("ok", sa.Boolean(), server_default=sa.text("true")),
        sa.Column("created_at", sa.DateTime(timezone=True)),
    )
    op.create_index("ix_activity_events_user_id", "activity_events", ["user_id"])
    op.create_index("ix_activity_events_category", "activity_events", ["category"])
    op.create_index("ix_activity_events_created_at", "activity_events", ["created_at"])


def downgrade():
    op.drop_index("ix_activity_events_created_at", table_name="activity_events")
    op.drop_index("ix_activity_events_category", table_name="activity_events")
    op.drop_index("ix_activity_events_user_id", table_name="activity_events")
    op.drop_table("activity_events")
    op.drop_column("users", "last_seen_at")
    op.drop_column("users", "last_login_at")
