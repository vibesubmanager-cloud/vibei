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


@api_v1.get("/admin/ai-settings")
@require_admin
def admin_ai_settings_get():
    from ...settings_store import ensure_defaults, get_setting, secret_masked

    ensure_defaults()
    key = get_setting("ai_api_key", "")
    return jsonify(
        {
            "provider": get_setting("ai_provider", "gemini"),
            "model": get_setting("ai_model", "gemini-3.5-flash-lite"),
            "api_key_set": bool(key),
            "api_key_masked": secret_masked("ai_api_key") if key else "",
            "recommended_models": [
                "gemini-3.5-flash-lite",
                "gemini-3.1-flash-lite",
                "gemini-2.5-flash-lite",
                "gemini-3.6-flash",
                "gemini-3.8-flash",
            ],
        }
    )


@api_v1.post("/admin/ai-settings")
@require_admin
def admin_ai_settings_save():
    from ...ai_providers import normalize_gemini_model
    from ...settings_store import ensure_defaults, get_setting, set_setting

    ensure_defaults()
    data = request.get_json(silent=True) or {}
    provider = (data.get("provider") or "gemini").strip().lower() or "gemini"
    model = (data.get("model") or "gemini-3.5-flash-lite").strip() or "gemini-3.5-flash-lite"
    if provider in ("gemini", "google"):
        model = normalize_gemini_model(model)
    key = (data.get("api_key") or data.get("ai_api_key") or "").strip()

    set_setting("ai_provider", provider, secret=False)
    set_setting("ai_model", model, secret=False)
    if key:
        set_setting("ai_api_key", key, secret=True)

    db.session.add(
        AuditLog(
            admin_id=g.admin.id,
            action="ai_settings_update",
            detail=f"provider={provider} model={model} key_updated={bool(key)}",
        )
    )
    db.session.commit()
    return jsonify(
        {
            "ok": True,
            "provider": provider,
            "model": model,
            "api_key_set": bool(get_setting("ai_api_key")),
        }
    )


@api_v1.post("/admin/ai-test")
@require_admin
def admin_ai_test():
    from ...ai_providers import ProviderError, test_connection

    try:
        return jsonify(test_connection())
    except ProviderError as e:
        status = 504 if e.code == "timeout" else 502
        return _err(e.code, e.message, status)
    except Exception as e:
        return _err("server_error", f"AI test failed: {e}", 500)


@api_v1.post("/admin/ai-describe-test")
@require_admin
def admin_ai_describe_test():
    """Upload an image (base64) and run Gemini describe — admin key test."""
    import base64
    import time

    from ...ai_providers import ProviderError, describe_image, normalize_gemini_model
    from ...settings_store import get_setting, set_setting

    data = request.get_json(silent=True) or {}

    # Force Gemini for this admin test path as requested.
    set_setting("ai_provider", "gemini", secret=False)
    current_model = get_setting("ai_model", "")
    set_setting(
        "ai_model",
        normalize_gemini_model(current_model or "gemini-3.5-flash-lite"),
        secret=False,
    )

    b64 = data.get("image_base64") or data.get("imageBase64") or ""
    if not b64:
        return _err("invalid", "Missing image_base64", 400)
    # Strip data-URL prefix if present
    if "," in b64 and b64.strip().startswith("data:"):
        b64 = b64.split(",", 1)[1]
    try:
        raw = base64.b64decode(b64, validate=False)
    except Exception:
        return _err("invalid", "Invalid base64 image", 400)
    if len(raw) > 4 * 1024 * 1024:
        return _err("invalid", "Image too large (max 4MB)", 400)

    t0 = time.time()
    try:
        text = describe_image(
            b64,
            scene_context="Admin panel API key test",
            language="en",
        )
        ms = int((time.time() - t0) * 1000)
        record_activity(
            user_id=None,
            category="ai_describe",
            action="admin_describe_test",
            detail={"latency_ms": ms, "admin_id": g.admin.id},
        )
        return jsonify(
            {
                "ok": True,
                "description": text,
                "provider": "gemini",
                "model": get_setting("ai_model", "gemini-3.5-flash-lite"),
                "latency_ms": ms,
            }
        )
    except ProviderError as e:
        status = 504 if e.code == "timeout" else 502
        return _err(e.code, e.message, status)
    except Exception as e:
        return _err("server_error", f"Describe test failed: {e}", 500)
