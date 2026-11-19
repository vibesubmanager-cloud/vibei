from __future__ import annotations

import base64
import time

import json

from flask import Response, g, jsonify, request, stream_with_context
from email_validator import EmailNotValidError, validate_email

from ...ai_providers import (
    ProviderError,
    describe_image,
    describe_image_stream,
    locate_target,
    read_image,
    understand_voice,
)
from ...activity import record_activity
from ...auth_util import issue_tokens, refresh_access, require_user, revoke_refresh
from ...extensions import db, limiter
from ...models import Consent, User, utcnow
from ...quota import record_usage, under_quota
from ...settings_store import get_bool, get_int, get_setting
from . import api_v1


def _err(code: str, message: str, status: int):
    return jsonify({"error": code, "message": message}), status


@api_v1.post("/auth/signup")
@limiter.limit("10 per hour")
def signup():
    data = request.get_json(silent=True) or {}
    email = (data.get("email") or "").strip().lower()
    password = data.get("password") or ""
    try:
        validate_email(email, check_deliverability=False)
    except EmailNotValidError:
        return _err("invalid", "Invalid email", 400)
    if len(password) < 8:
        return _err("invalid", "Password must be at least 8 characters", 400)
    if User.query.filter_by(email=email).first():
        return _err("conflict", "Email already registered", 409)
    user = User(email=email)
    user.set_password(password)
    user.last_login_at = utcnow()
    user.last_seen_at = utcnow()
    db.session.add(user)
    db.session.commit()
    record_activity(
        user_id=user.id,
        category="auth",
        action="signup",
        detail={"email": user.email},
        device_id=(data.get("device_id") or None),
    )
    tokens = issue_tokens(user)
    return jsonify({"user": {"id": user.id, "email": user.email}, **tokens}), 201


@api_v1.post("/auth/login")
@limiter.limit("20 per hour")
def login():
    data = request.get_json(silent=True) or {}
    email = (data.get("email") or "").strip().lower()
    password = data.get("password") or ""
    user = User.query.filter_by(email=email).first()
    if user is None or not user.check_password(password) or user.disabled:
        return _err("unauthorized", "Invalid credentials", 401)
    user.last_login_at = utcnow()
    user.last_seen_at = utcnow()
    db.session.commit()
    record_activity(
        user_id=user.id,
        category="auth",
        action="login",
        detail={"email": user.email},
        device_id=(data.get("device_id") or None),
    )
    return jsonify({"user": {"id": user.id, "email": user.email}, **issue_tokens(user)})


@api_v1.post("/auth/refresh")
@limiter.limit("60 per hour")
def refresh():
    data = request.get_json(silent=True) or {}
    token = data.get("refresh_token") or ""
    try:
        return jsonify(refresh_access(token))
    except ValueError:
        return _err("unauthorized", "Invalid refresh token", 401)


@api_v1.post("/auth/logout")
@require_user
def logout():
    data = request.get_json(silent=True) or {}
    revoke_refresh(data.get("refresh_token") or "")
    return jsonify({"ok": True})


@api_v1.delete("/auth/account")
@require_user
def delete_account():
    user = g.user
    db.session.delete(user)
    db.session.commit()
    return jsonify({"ok": True})


@api_v1.get("/config")
def public_config():
    return jsonify(
        {
            "feature_online_describe": get_bool("feature_online_describe", True),
            "feature_online_read": get_bool("feature_online_read", True),
            "feature_voice_assistant": get_bool("feature_voice_assistant", True),
            "ai_configured": bool(get_setting("ai_api_key") and get_setting("ai_model")),
            "maintenance_message": get_setting("maintenance_message"),
            "min_app_version": get_setting("min_app_version", "0.1.0"),
            "consent_text": get_setting("consent_text"),
            "consent_version": get_setting("consent_version", "1"),
            "languages": get_setting("languages", "en"),
        }
    )


@api_v1.post("/consent")
@require_user
def consent():
    data = request.get_json(silent=True) or {}
    c = Consent(
        user_id=g.user.id,
        vision=bool(data.get("vision")),
        chat=bool(data.get("chat")),
        text_version=str(data.get("text_version") or get_setting("consent_version", "1")),
    )
    db.session.add(c)
    db.session.commit()
    return jsonify({"ok": True})


@api_v1.post("/sync/personal")
@require_user
def sync_personal():
    data = request.get_json(silent=True) or {}
    objs = data.get("personal_objects")
    if isinstance(objs, dict):
        g.user.personal_objects = objs
        db.session.commit()
    return jsonify({"personal_objects": g.user.personal_objects or {}})


def _decode_image(data: dict) -> str:
    b64 = data.get("image_base64") or data.get("imageBase64") or ""
    if not b64:
        raise ValueError("missing_image")
    raw = base64.b64decode(b64, validate=False)
    max_b = get_int("max_image_bytes", 3 * 1024 * 1024)
    if len(raw) > max_b:
        raise ValueError("image_too_large")
    # Intentionally discard raw after returning b64 string for provider call.
    return b64


@api_v1.post("/vision/describe")
@require_user
@limiter.limit("30 per minute")
def vision_describe():
    if not get_bool("feature_online_describe", True):
        return _err("not_configured", "Online features are not set up", 503)
    t0 = time.time()
    data = request.get_json(silent=True) or {}
    try:
        b64 = _decode_image(data)
    except ValueError as e:
        return _err("invalid", str(e), 400)
    if not under_quota(g.user.id, "describe"):
        record_usage(g.user.id, "describe", False, 0, "quota_exceeded")
        return _err("quota_exceeded", "Daily describe quota exceeded", 429)
    try:
        text = describe_image(
            b64,
            str(data.get("scene_context") or data.get("sceneContext") or ""),
            str(data.get("language") or "en"),
            previous_description=str(
                data.get("previous_description")
                or data.get("previousDescription")
                or ""
            ),
            view_changed=bool(
                data.get("view_changed") or data.get("viewChanged") or False
            ),
        )
        ms = int((time.time() - t0) * 1000)
        record_usage(g.user.id, "describe", True, ms)
        record_activity(
            user_id=g.user.id,
            category="ai_describe",
            action="vision_describe",
            detail={"latency_ms": ms},
        )
        return jsonify({"text": text, "description": text})
    except ProviderError as e:
        ms = int((time.time() - t0) * 1000)
        record_usage(g.user.id, "describe", False, ms, e.code)
        status = 503 if e.code == "not_configured" else 502
        return _err(e.code, e.message, status)


@api_v1.post("/events")
@require_user
@limiter.limit("120 per minute")
def report_events():
    """Phone app reports offline feature usage (object search, scene, OCR, etc.)."""
    data = request.get_json(silent=True) or {}
    events = data.get("events")
    if not isinstance(events, list) or not events:
        # Single-event shorthand
        events = [data] if data.get("category") or data.get("action") else []
    if not events:
        return _err("invalid", "No events", 400)

    allowed = {
        "object_search",
        "object_detection",
        "text_search",
        "scene_description",
        "document_read",
        "auth",
        "other",
    }
    saved = 0
    for ev in events[:50]:
        if not isinstance(ev, dict):
            continue
        category = str(ev.get("category") or "other").strip()[:64]
        if category not in allowed:
            category = "other"
        action = str(ev.get("action") or "event").strip()[:128]
        detail = ev.get("detail") if isinstance(ev.get("detail"), dict) else {}
        record_activity(
            user_id=g.user.id,
            category=category,
            action=action,
            detail=detail,
            device_id=(ev.get("device_id") or data.get("device_id") or None),
            ok=bool(ev.get("ok", True)),
        )
        saved += 1
    return jsonify({"ok": True, "saved": saved})


@api_v1.post("/vision/describe_stream")
@require_user
@limiter.limit("30 per minute")
def vision_describe_stream():
    if not get_bool("feature_online_describe", True):
        return _err("not_configured", "Online features are not set up", 503)
    data = request.get_json(silent=True) or {}
    try:
        b64 = _decode_image(data)
    except ValueError as e:
        return _err("invalid", str(e), 400)
    if not under_quota(g.user.id, "describe"):
        record_usage(g.user.id, "describe", False, 0, "quota_exceeded")
        return _err("quota_exceeded", "Daily describe quota exceeded", 429)

    scene = str(data.get("scene_context") or data.get("sceneContext") or "")
    lang = str(data.get("language") or "en")
    prev = str(
        data.get("previous_description") or data.get("previousDescription") or ""
    )
    changed = bool(data.get("view_changed") or data.get("viewChanged") or False)
    uid = g.user.id
    t0 = time.time()

    def generate():
        try:
            for delta in describe_image_stream(
                b64,
                scene,
                lang,
                previous_description=prev,
                view_changed=changed,
            ):
                yield f"data: {json.dumps({'delta': delta})}\n\n"
            yield "data: [DONE]\n\n"
            ms = int((time.time() - t0) * 1000)
            record_usage(uid, "describe", True, ms)
        except ProviderError as e:
            ms = int((time.time() - t0) * 1000)
            record_usage(uid, "describe", False, ms, e.code)
            yield f"data: {json.dumps({'error': e.code, 'message': e.message})}\n\n"

    return Response(
        stream_with_context(generate()),
        mimetype="text/event-stream",
        headers={
            "Cache-Control": "no-cache",
            "X-Accel-Buffering": "no",
        },
    )


@api_v1.post("/vision/read")
@require_user
@limiter.limit("30 per minute")
def vision_read():
    if not get_bool("feature_online_read", True):
        return _err("not_configured", "Online features are not set up", 503)
    t0 = time.time()
    data = request.get_json(silent=True) or {}
    try:
        b64 = _decode_image(data)
    except ValueError as e:
        return _err("invalid", str(e), 400)
    if not under_quota(g.user.id, "read"):
        record_usage(g.user.id, "read", False, 0, "quota_exceeded")
        return _err("quota_exceeded", "Daily read quota exceeded", 429)
    try:
        text = read_image(b64, str(data.get("language") or "en"))
        ms = int((time.time() - t0) * 1000)
        record_usage(g.user.id, "read", True, ms)
        return jsonify({"text": text})
    except ProviderError as e:
        ms = int((time.time() - t0) * 1000)
        record_usage(g.user.id, "read", False, ms, e.code)
        status = 503 if e.code == "not_configured" else 502
        return _err(e.code, e.message, status)


@api_v1.post("/vision/locate")
@require_user
@limiter.limit("30 per minute")
def vision_locate():
    if not get_bool("feature_online_describe", True):
        return _err("not_configured", "Online features are not set up", 503)
    t0 = time.time()
    data = request.get_json(silent=True) or {}
    target = (data.get("target") or data.get("query") or "").strip()
    if not target:
        return _err("invalid", "Missing target", 400)
    try:
        b64 = _decode_image(data)
    except ValueError as e:
        return _err("invalid", str(e), 400)
    if not under_quota(g.user.id, "describe"):
        record_usage(g.user.id, "describe", False, 0, "quota_exceeded")
        return _err("quota_exceeded", "Daily locate quota exceeded", 429)
    try:
        result = locate_target(
            b64, target, str(data.get("language") or "en")
        )
        ms = int((time.time() - t0) * 1000)
        record_usage(g.user.id, "describe", True, ms)
        return jsonify(result)
    except ProviderError as e:
        ms = int((time.time() - t0) * 1000)
        record_usage(g.user.id, "describe", False, ms, e.code)
        status = 503 if e.code == "not_configured" else 502
        return _err(e.code, e.message, status)


@api_v1.post("/voice/understand")
@require_user
@limiter.limit("60 per minute")
def voice_understand():
    if not get_bool("feature_voice_assistant", True):
        return _err("not_configured", "Online features are not set up", 503)
    t0 = time.time()
    data = request.get_json(silent=True) or {}
    transcript = (data.get("transcript") or "").strip()
    if not transcript:
        return _err("invalid", "Missing transcript", 400)
    if not under_quota(g.user.id, "voice"):
        record_usage(g.user.id, "voice", False, 0, "quota_exceeded")
        return _err("quota_exceeded", "Daily voice quota exceeded", 429)
    try:
        result = understand_voice(transcript, data.get("context") or {})
        ms = int((time.time() - t0) * 1000)
        record_usage(g.user.id, "voice", True, ms)
        return jsonify(result)
    except ProviderError as e:
        ms = int((time.time() - t0) * 1000)
        record_usage(g.user.id, "voice", False, ms, e.code)
        status = 503 if e.code == "not_configured" else 502
        return _err(e.code, e.message, status)
