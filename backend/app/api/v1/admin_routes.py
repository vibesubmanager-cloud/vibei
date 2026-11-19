"""JSON admin API for the GitHub Pages admin panel (HTML/CSS/JS)."""

from __future__ import annotations

from datetime import timedelta
from functools import wraps

import jwt
from flask import current_app, g, jsonify, request
from sqlalchemy import func

from ...activity import record_activity
from ...extensions import db, limiter
from ...models import ActivityEvent, Admin, AuditLog, UsageEvent, User, utcnow
from . import api_v1


def _err(code: str, message: str, status: int):
    return jsonify({"error": code, "message": message}), status


def issue_admin_token(admin: Admin) -> dict:
    now = utcnow()
    token = jwt.encode(
        {
            "sub": str(admin.id),
            "typ": "admin",
            "email": admin.email,
            "exp": now + timedelta(hours=12),
            "iat": now,
        },
        current_app.config["SECRET_KEY"],
        algorithm="HS256",
    )
    return {
        "access_token": token,
        "token_type": "Bearer",
        "expires_in": 12 * 3600,
        "admin": {"id": admin.id, "email": admin.email},
    }


def require_admin(fn):
    @wraps(fn)
    def wrapper(*args, **kwargs):
        auth = request.headers.get("Authorization") or ""
        if not auth.startswith("Bearer "):
            return _err("unauthorized", "Missing admin token", 401)
        token = auth[7:].strip()
        try:
            payload = jwt.decode(
                token, current_app.config["SECRET_KEY"], algorithms=["HS256"]
            )
        except Exception:
            return _err("unauthorized", "Invalid admin token", 401)
        if payload.get("typ") != "admin":
            return _err("unauthorized", "Not an admin token", 401)
        admin = Admin.query.get(int(payload["sub"]))
        if admin is None:
            return _err("unauthorized", "Admin not found", 401)
        g.admin = admin
        return fn(*args, **kwargs)

    return wrapper


@api_v1.post("/admin/login")
@limiter.limit("20 per hour")
def admin_login():
    data = request.get_json(silent=True) or {}
    email = (data.get("email") or "").strip().lower()
    password = data.get("password") or ""
    admin = Admin.query.filter_by(email=email).first()
    if admin is None or not admin.check_password(password):
        return _err("unauthorized", "Invalid credentials", 401)
    if admin.locked_until and admin.locked_until > utcnow():
        return _err("locked", "Account locked. Try later.", 429)
    admin.failed_logins = 0
    db.session.commit()
    record_activity(
        user_id=None,
        category="auth",
        action="admin_login",
        detail={"admin_id": admin.id, "email": admin.email},
    )
    return jsonify(issue_admin_token(admin))


@api_v1.get("/admin/me")
@require_admin
def admin_me():
    return jsonify({"id": g.admin.id, "email": g.admin.email})


@api_v1.get("/admin/dashboard")
@require_admin
def admin_dashboard():
    since = utcnow() - timedelta(days=1)
    week = utcnow() - timedelta(days=7)

    total_users = User.query.count()
    active_24h = User.query.filter(User.last_seen_at >= since).count()
    signups_7d = User.query.filter(User.created_at >= week).count()

    usage_24h = (
        db.session.query(UsageEvent.feature, func.count(UsageEvent.id))
        .filter(UsageEvent.created_at >= since, UsageEvent.ok.is_(True))
        .group_by(UsageEvent.feature)
        .all()
    )
    activity_24h = (
        db.session.query(ActivityEvent.category, func.count(ActivityEvent.id))
        .filter(ActivityEvent.created_at >= since)
        .group_by(ActivityEvent.category)
        .all()
    )

    return jsonify(
        {
            "users": {
                "total": total_users,
                "active_24h": active_24h,
                "signups_7d": signups_7d,
            },
            "usage_24h": {k: v for k, v in usage_24h},
            "activity_24h": {k: v for k, v in activity_24h},
            "ai_requests_24h": sum(
                v
                for k, v in usage_24h
                if k in ("describe", "read", "voice")
            ),
            "object_detection_24h": dict(activity_24h).get("object_detection", 0)
            + dict(activity_24h).get("object_search", 0),
            "scene_description_24h": dict(activity_24h).get("scene_description", 0),
        }
    )


@api_v1.get("/admin/users")
@require_admin
def admin_users():
    users = User.query.order_by(User.created_at.desc()).limit(500).all()
    out = []
    for u in users:
        usage = (
            db.session.query(UsageEvent.feature, func.count(UsageEvent.id))
            .filter(UsageEvent.user_id == u.id, UsageEvent.ok.is_(True))
            .group_by(UsageEvent.feature)
            .all()
        )
        acts = (
            db.session.query(ActivityEvent.category, func.count(ActivityEvent.id))
            .filter(ActivityEvent.user_id == u.id)
            .group_by(ActivityEvent.category)
            .all()
        )
        out.append(
            {
                "id": u.id,
                "email": u.email,
                "disabled": bool(u.disabled),
                "created_at": u.created_at.isoformat() if u.created_at else None,
                "last_login_at": u.last_login_at.isoformat() if u.last_login_at else None,
                "last_seen_at": u.last_seen_at.isoformat() if u.last_seen_at else None,
                "usage": {k: v for k, v in usage},
                "activity": {k: v for k, v in acts},
                "ai_total": sum(v for k, v in usage if k in ("describe", "read", "voice")),
                "object_detection_total": sum(
                    v for k, v in acts if k in ("object_detection", "object_search")
                ),
            }
        )
    return jsonify({"users": out})


@api_v1.get("/admin/users/<int:user_id>")
@require_admin
def admin_user_detail(user_id: int):
    u = User.query.get(user_id)
    if u is None:
        return _err("not_found", "User not found", 404)
    recent = (
        ActivityEvent.query.filter_by(user_id=u.id)
        .order_by(ActivityEvent.created_at.desc())
        .limit(100)
        .all()
    )
    return jsonify(
        {
            "user": {
                "id": u.id,
                "email": u.email,
                "disabled": bool(u.disabled),
                "created_at": u.created_at.isoformat() if u.created_at else None,
                "last_login_at": u.last_login_at.isoformat() if u.last_login_at else None,
                "last_seen_at": u.last_seen_at.isoformat() if u.last_seen_at else None,
            },
            "recent_activity": [
                {
                    "id": a.id,
                    "category": a.category,
                    "action": a.action,
                    "detail": a.detail or {},
                    "ok": a.ok,
                    "created_at": a.created_at.isoformat() if a.created_at else None,
                }
                for a in recent
            ],
        }
    )


@api_v1.post("/admin/users/<int:user_id>/disable")
@require_admin
def admin_disable_user(user_id: int):
    u = User.query.get(user_id)
    if u is None:
        return _err("not_found", "User not found", 404)
    data = request.get_json(silent=True) or {}
    u.disabled = bool(data.get("disabled", True))
    db.session.add(
        AuditLog(
            admin_id=g.admin.id,
            action="user_disable" if u.disabled else "user_enable",
            detail=f"user_id={u.id} email={u.email}",
        )
    )
    db.session.commit()
    return jsonify({"ok": True, "disabled": u.disabled})


@api_v1.get("/admin/activities")
@require_admin
def admin_activities():
    limit = min(int(request.args.get("limit") or 200), 500)
    category = (request.args.get("category") or "").strip()
    q = ActivityEvent.query
    if category:
        q = q.filter_by(category=category)
    rows = q.order_by(ActivityEvent.created_at.desc()).limit(limit).all()
    emails = {}
    for r in rows:
        if r.user_id and r.user_id not in emails:
            u = User.query.get(r.user_id)
            emails[r.user_id] = u.email if u else None
    return jsonify(
        {
            "activities": [
                {
                    "id": r.id,
                    "user_id": r.user_id,
                    "email": emails.get(r.user_id),
                    "category": r.category,
                    "action": r.action,
                    "detail": r.detail or {},
                    "device_id": r.device_id,
                    "ok": r.ok,
                    "created_at": r.created_at.isoformat() if r.created_at else None,
                }
                for r in rows
            ]
        }
    )


@api_v1.get("/admin/usage")
@require_admin
def admin_usage():
    limit = min(int(request.args.get("limit") or 200), 500)
    rows = (
        UsageEvent.query.order_by(UsageEvent.created_at.desc()).limit(limit).all()
    )
    return jsonify(
        {
            "events": [
                {
                    "id": r.id,
                    "user_id": r.user_id,
                    "feature": r.feature,
                    "ok": r.ok,
                    "latency_ms": r.latency_ms,
                    "error_code": r.error_code,
                    "created_at": r.created_at.isoformat() if r.created_at else None,
                }
                for r in rows
            ]
        }
    )
