"""initial schema

Revision ID: 0001
Revises:
Create Date: 2026-11-15
"""

from alembic import op
import sqlalchemy as sa

revision = "0001"
down_revision = None
branch_labels = None
depends_on = None


def upgrade():
    op.create_table(
        "admins",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("email", sa.String(255), nullable=False, unique=True),
        sa.Column("password_hash", sa.String(255), nullable=False),
        sa.Column("totp_secret", sa.String(64)),
        sa.Column("totp_enabled", sa.Boolean(), server_default=sa.text("false")),
        sa.Column("failed_logins", sa.Integer(), server_default="0"),
        sa.Column("locked_until", sa.DateTime(timezone=True)),
        sa.Column("created_at", sa.DateTime(timezone=True)),
    )
    op.create_table(
        "users",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("email", sa.String(255), nullable=False, unique=True),
        sa.Column("password_hash", sa.String(255), nullable=False),
        sa.Column("disabled", sa.Boolean(), server_default=sa.text("false")),
        sa.Column("created_at", sa.DateTime(timezone=True)),
        sa.Column("personal_objects", sa.JSON()),
        sa.Column("settings_json", sa.JSON()),
    )
    op.create_table(
        "devices",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("user_id", sa.Integer(), sa.ForeignKey("users.id"), nullable=False),
        sa.Column("device_id", sa.String(128), nullable=False),
        sa.Column("platform", sa.String(32)),
        sa.Column("created_at", sa.DateTime(timezone=True)),
    )
    op.create_table(
        "refresh_tokens",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("user_id", sa.Integer(), sa.ForeignKey("users.id"), nullable=False),
        sa.Column("token_hash", sa.String(128), nullable=False, unique=True),
        sa.Column("expires_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("revoked", sa.Boolean(), server_default=sa.text("false")),
        sa.Column("created_at", sa.DateTime(timezone=True)),
    )
    op.create_table(
        "consents",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("user_id", sa.Integer(), sa.ForeignKey("users.id"), nullable=False),
        sa.Column("vision", sa.Boolean(), server_default=sa.text("false")),
        sa.Column("chat", sa.Boolean(), server_default=sa.text("false")),
        sa.Column("text_version", sa.String(64)),
        sa.Column("created_at", sa.DateTime(timezone=True)),
    )
    op.create_table(
        "settings",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("key", sa.String(128), nullable=False, unique=True),
        sa.Column("value_enc", sa.Text()),
        sa.Column("value_plain", sa.Text()),
        sa.Column("is_secret", sa.Boolean(), server_default=sa.text("false")),
        sa.Column("updated_at", sa.DateTime(timezone=True)),
    )
    op.create_table(
        "usage_events",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("user_id", sa.Integer(), sa.ForeignKey("users.id")),
        sa.Column("feature", sa.String(64), nullable=False),
        sa.Column("ok", sa.Boolean(), server_default=sa.text("true")),
        sa.Column("latency_ms", sa.Integer(), server_default="0"),
        sa.Column("error_code", sa.String(64)),
        sa.Column("created_at", sa.DateTime(timezone=True)),
    )
    op.create_table(
        "audit_log",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("admin_id", sa.Integer(), sa.ForeignKey("admins.id")),
        sa.Column("action", sa.String(128), nullable=False),
        sa.Column("detail", sa.Text()),
        sa.Column("created_at", sa.DateTime(timezone=True)),
    )
    op.create_table(
        "bootstrap_state",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("used", sa.Boolean(), server_default=sa.text("false")),
        sa.Column("used_at", sa.DateTime(timezone=True)),
    )


def downgrade():
    for t in (
        "bootstrap_state",
        "audit_log",
        "usage_events",
        "settings",
        "consents",
        "refresh_tokens",
        "devices",
        "users",
        "admins",
    ):
        op.drop_table(t)
