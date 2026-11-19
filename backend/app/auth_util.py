from __future__ import annotations

import hashlib
import secrets
from datetime import timedelta
from functools import wraps

import jwt
from flask import current_app, g, jsonify, request

from .extensions import db
from .models import RefreshToken, User, utcnow


def _hash_token(token: str) -> str:
    return hashlib.sha256(token.encode("utf-8")).hexdigest()


def issue_tokens(user: User) -> dict:
    now = utcnow()
    access = jwt.encode(
        {
            "sub": str(user.id),
            "typ": "access",
            "exp": now + timedelta(minutes=current_app.config["JWT_ACCESS_MINUTES"]),
            "iat": now,
        },
        current_app.config["SECRET_KEY"],
        algorithm="HS256",
    )
    refresh = secrets.token_urlsafe(48)
    row = RefreshToken(
        user_id=user.id,
        token_hash=_hash_token(refresh),
        expires_at=now + timedelta(days=current_app.config["JWT_REFRESH_DAYS"]),
    )
    db.session.add(row)
    db.session.commit()
    return {
        "access_token": access,
        "refresh_token": refresh,
        "token_type": "Bearer",
        "expires_in": current_app.config["JWT_ACCESS_MINUTES"] * 60,
    }


def _as_utc(dt):
    if dt is None:
        return None
    if dt.tzinfo is None:
        from datetime import timezone

        return dt.replace(tzinfo=timezone.utc)
    return dt


def refresh_access(refresh_token: str) -> dict:
    row = RefreshToken.query.filter_by(
        token_hash=_hash_token(refresh_token), revoked=False
    ).first()
    if row is None or _as_utc(row.expires_at) < utcnow():
        raise ValueError("invalid_refresh")
    user = User.query.get(row.user_id)
    if user is None or user.disabled:
        raise ValueError("unauthorized")
    row.revoked = True
    db.session.commit()
    return issue_tokens(user)


def revoke_refresh(refresh_token: str):
    row = RefreshToken.query.filter_by(token_hash=_hash_token(refresh_token)).first()
    if row:
        row.revoked = True
        db.session.commit()


def require_user(fn):
    @wraps(fn)
    def wrapper(*args, **kwargs):
        auth = request.headers.get("Authorization", "")
        if not auth.startswith("Bearer "):
            return jsonify({"error": "unauthorized", "message": "Missing token"}), 401
        token = auth[7:]
        try:
            payload = jwt.decode(
                token, current_app.config["SECRET_KEY"], algorithms=["HS256"]
            )
            if payload.get("typ") != "access":
                raise jwt.InvalidTokenError("wrong type")
            user = User.query.get(int(payload["sub"]))
        except Exception:
            return jsonify({"error": "unauthorized", "message": "Invalid token"}), 401
        if user is None or user.disabled:
            return jsonify({"error": "unauthorized", "message": "User disabled"}), 401
        g.user = user
        return fn(*args, **kwargs)

    return wrapper
