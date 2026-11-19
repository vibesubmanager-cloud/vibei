from datetime import datetime, timezone

from argon2 import PasswordHasher
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.types import JSON

from .extensions import db

ph = PasswordHasher()
JsonType = JSON().with_variant(JSONB(), "postgresql")


def utcnow():
    return datetime.now(timezone.utc)


class Admin(db.Model):
    __tablename__ = "admins"
    id = db.Column(db.Integer, primary_key=True)
    email = db.Column(db.String(255), unique=True, nullable=False, index=True)
    password_hash = db.Column(db.String(255), nullable=False)
    totp_secret = db.Column(db.String(64), nullable=True)
    totp_enabled = db.Column(db.Boolean, default=False)
    failed_logins = db.Column(db.Integer, default=0)
    locked_until = db.Column(db.DateTime(timezone=True), nullable=True)
    created_at = db.Column(db.DateTime(timezone=True), default=utcnow)

    def set_password(self, password: str):
        self.password_hash = ph.hash(password)

    def check_password(self, password: str) -> bool:
        try:
            return ph.verify(self.password_hash, password)
        except Exception:
            return False


class User(db.Model):
    __tablename__ = "users"
    id = db.Column(db.Integer, primary_key=True)
    email = db.Column(db.String(255), unique=True, nullable=False, index=True)
    password_hash = db.Column(db.String(255), nullable=False)
    disabled = db.Column(db.Boolean, default=False)
    created_at = db.Column(db.DateTime(timezone=True), default=utcnow)
    last_login_at = db.Column(db.DateTime(timezone=True), nullable=True)
    last_seen_at = db.Column(db.DateTime(timezone=True), nullable=True)
    personal_objects = db.Column(JsonType, default=dict)
    settings_json = db.Column(JsonType, default=dict)

    def set_password(self, password: str):
        self.password_hash = ph.hash(password)

    def check_password(self, password: str) -> bool:
        try:
            return ph.verify(self.password_hash, password)
        except Exception:
            return False


class Device(db.Model):
    __tablename__ = "devices"
    id = db.Column(db.Integer, primary_key=True)
    user_id = db.Column(db.Integer, db.ForeignKey("users.id"), nullable=False)
    device_id = db.Column(db.String(128), nullable=False)
    platform = db.Column(db.String(32), default="android")
    created_at = db.Column(db.DateTime(timezone=True), default=utcnow)


class RefreshToken(db.Model):
    __tablename__ = "refresh_tokens"
    id = db.Column(db.Integer, primary_key=True)
    user_id = db.Column(db.Integer, db.ForeignKey("users.id"), nullable=False)
    token_hash = db.Column(db.String(128), unique=True, nullable=False)
    expires_at = db.Column(db.DateTime(timezone=True), nullable=False)
    revoked = db.Column(db.Boolean, default=False)
    created_at = db.Column(db.DateTime(timezone=True), default=utcnow)


class Consent(db.Model):
    __tablename__ = "consents"
    id = db.Column(db.Integer, primary_key=True)
    user_id = db.Column(db.Integer, db.ForeignKey("users.id"), nullable=False)
    vision = db.Column(db.Boolean, default=False)
    chat = db.Column(db.Boolean, default=False)
    text_version = db.Column(db.String(64), default="1")
    created_at = db.Column(db.DateTime(timezone=True), default=utcnow)


class Setting(db.Model):
    __tablename__ = "settings"
    id = db.Column(db.Integer, primary_key=True)
    key = db.Column(db.String(128), unique=True, nullable=False, index=True)
    value_enc = db.Column(db.Text, nullable=True)
    value_plain = db.Column(db.Text, nullable=True)
    is_secret = db.Column(db.Boolean, default=False)
    updated_at = db.Column(db.DateTime(timezone=True), default=utcnow, onupdate=utcnow)


class UsageEvent(db.Model):
    __tablename__ = "usage_events"
    id = db.Column(db.Integer, primary_key=True)
    user_id = db.Column(db.Integer, db.ForeignKey("users.id"), nullable=True)
    feature = db.Column(db.String(64), nullable=False)
    ok = db.Column(db.Boolean, default=True)
    latency_ms = db.Column(db.Integer, default=0)
    error_code = db.Column(db.String(64), nullable=True)
    created_at = db.Column(db.DateTime(timezone=True), default=utcnow, index=True)


class ActivityEvent(db.Model):
    """App activity feed for the admin panel (sign-in, searches, AI, detections)."""

    __tablename__ = "activity_events"
    id = db.Column(db.Integer, primary_key=True)
    user_id = db.Column(db.Integer, db.ForeignKey("users.id"), nullable=True, index=True)
    # Categories: auth | object_search | text_search | scene_description |
    #             ai_describe | ai_read | ai_voice | object_detection | other
    category = db.Column(db.String(64), nullable=False, index=True)
    action = db.Column(db.String(128), nullable=False)
    detail = db.Column(JsonType, default=dict)
    device_id = db.Column(db.String(128), nullable=True)
    ok = db.Column(db.Boolean, default=True)
    created_at = db.Column(db.DateTime(timezone=True), default=utcnow, index=True)


class AuditLog(db.Model):
    __tablename__ = "audit_log"
    id = db.Column(db.Integer, primary_key=True)
    admin_id = db.Column(db.Integer, db.ForeignKey("admins.id"), nullable=True)
    action = db.Column(db.String(128), nullable=False)
    detail = db.Column(db.Text, default="")
    created_at = db.Column(db.DateTime(timezone=True), default=utcnow, index=True)


class BootstrapState(db.Model):
    __tablename__ = "bootstrap_state"
    id = db.Column(db.Integer, primary_key=True)
    used = db.Column(db.Boolean, default=False)
    used_at = db.Column(db.DateTime(timezone=True), nullable=True)
