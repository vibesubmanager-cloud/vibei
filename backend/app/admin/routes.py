from __future__ import annotations

from datetime import timedelta
from functools import wraps

import cloudinary
import cloudinary.uploader
import pyotp
from flask import (
    Blueprint,
    flash,
    g,
    jsonify,
    redirect,
    render_template,
    request,
    session,
    url_for,
)
from flask_wtf.csrf import generate_csrf

from ..ai_providers import ProviderError, test_connection
from ..extensions import db, limiter
from ..models import Admin, AuditLog, UsageEvent, User, utcnow
from ..settings_store import (
    ensure_defaults,
    get_bool,
    get_setting,
    secret_masked,
    set_setting,
)

admin_bp = Blueprint("admin", __name__, template_folder="../templates")


def audit(action: str, detail: str = ""):
    db.session.add(
        AuditLog(
            admin_id=getattr(g, "admin", None).id if getattr(g, "admin", None) else None,
            action=action,
            detail=detail[:500],
        )
    )
    db.session.commit()


def login_required(fn):
    @wraps(fn)
    def wrapper(*args, **kwargs):
        aid = session.get("admin_id")
        if not aid:
            return redirect(url_for("admin.login"))
        admin = Admin.query.get(aid)
        if admin is None:
            session.clear()
            return redirect(url_for("admin.login"))
        g.admin = admin
        return fn(*args, **kwargs)

    return wrapper


@admin_bp.app_context_processor
def inject_csrf():
    return {"csrf_token": generate_csrf}


@admin_bp.get("/")
def index():
    if session.get("admin_id"):
        return redirect(url_for("admin.dashboard"))
    return redirect(url_for("admin.login"))


@admin_bp.route("/login", methods=["GET", "POST"])
@limiter.limit("10 per minute")
def login():
    ensure_defaults()
    if request.method == "GET":
        return render_template("admin/login.html")
    email = (request.form.get("email") or "").strip().lower()
    password = request.form.get("password") or ""
    totp = request.form.get("totp") or ""
    admin = Admin.query.filter_by(email=email).first()
    if admin and admin.locked_until and admin.locked_until > utcnow():
        flash("Account locked. Try later.", "error")
        return render_template("admin/login.html"), 429
    if admin is None or not admin.check_password(password):
        if admin:
            admin.failed_logins = (admin.failed_logins or 0) + 1
            if admin.failed_logins >= 8:
                admin.locked_until = utcnow() + timedelta(minutes=15)
            db.session.commit()
        flash("Invalid credentials", "error")
        return render_template("admin/login.html"), 401
    if admin.totp_enabled:
        if not admin.totp_secret or not pyotp.TOTP(admin.totp_secret).verify(totp, valid_window=1):
            flash("Invalid 2FA code", "error")
            return render_template("admin/login.html"), 401
    admin.failed_logins = 0
    admin.locked_until = None
    db.session.commit()
    session["admin_id"] = admin.id
    session.permanent = True
    audit("login", admin.email)
    return redirect(url_for("admin.dashboard"))


@admin_bp.post("/logout")
@login_required
def logout():
    audit("logout")
    session.clear()
    return redirect(url_for("admin.login"))


@admin_bp.get("/dashboard")
@login_required
def dashboard():
    return render_template(
        "admin/dashboard.html",
        ai_configured=bool(get_setting("ai_api_key") and get_setting("ai_model")),
        provider=get_setting("ai_provider"),
    )


@admin_bp.route("/ai", methods=["GET", "POST"])
@login_required
def ai_providers():
    if request.method == "POST":
        set_setting("ai_provider", request.form.get("ai_provider") or "openai")
        set_setting("ai_model", (request.form.get("ai_model") or "").strip())
        key = (request.form.get("ai_api_key") or "").strip()
        if key:
            set_setting("ai_api_key", key, secret=True)
        audit("update_ai_providers")
        flash("AI settings saved", "ok")
        return redirect(url_for("admin.ai_providers"))
    return render_template(
        "admin/ai.html",
        provider=get_setting("ai_provider", "openai"),
        model=get_setting("ai_model"),
        key_masked=secret_masked("ai_api_key"),
    )


@admin_bp.post("/ai/test")
@login_required
def ai_test():
    try:
        result = test_connection()
        audit("test_ai_connection", result.get("provider", ""))
        return jsonify(result)
    except ProviderError as e:
        return jsonify({"ok": False, "error": e.code, "message": e.message}), 400


@admin_bp.route("/features", methods=["GET", "POST"])
@login_required
def features():
    if request.method == "POST":
        for k in (
            "feature_online_describe",
            "feature_online_read",
            "feature_voice_assistant",
        ):
            set_setting(k, "1" if request.form.get(k) == "on" else "0")
        for k in ("prompt_describe", "prompt_read", "prompt_voice", "languages"):
            set_setting(k, request.form.get(k) or "")
        set_setting("max_image_bytes", request.form.get("max_image_bytes") or "3145728")
        set_setting("provider_timeout_sec", request.form.get("provider_timeout_sec") or "25")
        audit("update_features")
        flash("Features saved", "ok")
        return redirect(url_for("admin.features"))
    return render_template(
        "admin/features.html",
        describe=get_bool("feature_online_describe", True),
        read=get_bool("feature_online_read", True),
        voice=get_bool("feature_voice_assistant", True),
        prompt_describe=get_setting("prompt_describe"),
        prompt_read=get_setting("prompt_read"),
        prompt_voice=get_setting("prompt_voice"),
        max_image_bytes=get_setting("max_image_bytes"),
        provider_timeout_sec=get_setting("provider_timeout_sec"),
        languages=get_setting("languages"),
    )


@admin_bp.route("/limits", methods=["GET", "POST"])
@login_required
def limits():
    if request.method == "POST":
        for k in ("quota_describe_day", "quota_read_day", "quota_voice_day"):
            set_setting(k, request.form.get(k) or "50")
        audit("update_limits")
        flash("Limits saved", "ok")
        return redirect(url_for("admin.limits"))
    return render_template(
        "admin/limits.html",
        quota_describe_day=get_setting("quota_describe_day"),
        quota_read_day=get_setting("quota_read_day"),
        quota_voice_day=get_setting("quota_voice_day"),
    )


@admin_bp.route("/cloudinary", methods=["GET", "POST"])
@login_required
def cloudinary_page():
    if request.method == "POST":
        set_setting("cloudinary_cloud_name", request.form.get("cloud_name") or "")
        key = (request.form.get("api_key") or "").strip()
        secret = (request.form.get("api_secret") or "").strip()
        if key:
            set_setting("cloudinary_api_key", key, secret=True)
        if secret:
            set_setting("cloudinary_api_secret", secret, secret=True)
        audit("update_cloudinary")
        flash("Cloudinary saved", "ok")
        return redirect(url_for("admin.cloudinary_page"))
    return render_template(
        "admin/cloudinary.html",
        cloud_name=get_setting("cloudinary_cloud_name"),
        api_key_masked=secret_masked("cloudinary_api_key"),
        api_secret_masked=secret_masked("cloudinary_api_secret"),
    )


@admin_bp.post("/cloudinary/test")
@login_required
def cloudinary_test():
    name = get_setting("cloudinary_cloud_name")
    key = get_setting("cloudinary_api_key")
    secret = get_setting("cloudinary_api_secret")
    if not (name and key and secret):
        return jsonify({"ok": False, "message": "Cloudinary not configured"}), 400
    cloudinary.config(cloud_name=name, api_key=key, api_secret=secret, secure=True)
    # 1x1 JPEG
    tiny = (
        b"/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAAgGBgcGBQgHBwcJCQgKDBQNDAsLDBkS"
        b"Ew8UHRofHh0aHBwgJC4nICIsIxwcKDcpLDAxNDQ0Hyc5PTgyPC4zNDL/2wBDAQkJ"
        b"CQwLDBgNDRgyIRwhMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIy"
        b"MjIyMjIyMjIyMjIyMjL/wAARCAABAAEDASIAAhEBAxEB/8QAFQABAQAAAAAAAAAA"
        b"AAAAAAAAAAn/xAAUEAEAAAAAAAAAAAAAAAAAAAAA/8QAFQEBAQAAAAAAAAAAAAAA"
        b"AAAAAAn/xAAUEQEAAAAAAAAAAAAAAAAAAAAA/9oADAMBAAIQAxAAAAGfAP/EABQQ"
        b"AQAAAAAAAAAAAAAAAAAAAAD/2gAIAQEAAQUCf//EABQRAQAAAAAAAAAAAAAAAAAA"
        b"AAD/2gAIAQMBAT8Bf//EABQRAQAAAAAAAAAAAAAAAAAAAAD/2gAIAQIBAT8Bf//Z"
    )
    import base64
    from io import BytesIO

    try:
        res = cloudinary.uploader.upload(
            BytesIO(base64.b64decode(tiny)),
            folder="vibei_admin_test",
            overwrite=True,
            resource_type="image",
        )
        audit("test_cloudinary")
        return jsonify({"ok": True, "public_id": res.get("public_id")})
    except Exception as e:
        return jsonify({"ok": False, "message": str(e)}), 400


@admin_bp.route("/app-config", methods=["GET", "POST"])
@login_required
def app_config():
    if request.method == "POST":
        for k in ("maintenance_message", "min_app_version", "consent_text", "consent_version"):
            set_setting(k, request.form.get(k) or "")
        audit("update_app_config")
        flash("App config saved", "ok")
        return redirect(url_for("admin.app_config"))
    return render_template(
        "admin/app_config.html",
        maintenance_message=get_setting("maintenance_message"),
        min_app_version=get_setting("min_app_version"),
        consent_text=get_setting("consent_text"),
        consent_version=get_setting("consent_version"),
    )


@admin_bp.get("/users")
@login_required
def users():
    q = (request.args.get("q") or "").strip().lower()
    query = User.query
    if q:
        query = query.filter(User.email.contains(q))
    rows = query.order_by(User.id.desc()).limit(200).all()
    return render_template("admin/users.html", users=rows, q=q)


@admin_bp.post("/users/<int:uid>/disable")
@login_required
def user_disable(uid):
    u = User.query.get_or_404(uid)
    u.disabled = True
    db.session.commit()
    audit("disable_user", u.email)
    return redirect(url_for("admin.users"))


@admin_bp.post("/users/<int:uid>/enable")
@login_required
def user_enable(uid):
    u = User.query.get_or_404(uid)
    u.disabled = False
    db.session.commit()
    audit("enable_user", u.email)
    return redirect(url_for("admin.users"))


@admin_bp.post("/users/<int:uid>/delete")
@login_required
def user_delete(uid):
    u = User.query.get_or_404(uid)
    email = u.email
    db.session.delete(u)
    db.session.commit()
    audit("delete_user", email)
    return redirect(url_for("admin.users"))


@admin_bp.get("/users/<int:uid>/export")
@login_required
def user_export(uid):
    u = User.query.get_or_404(uid)
    audit("export_user", u.email)
    return jsonify(
        {
            "id": u.id,
            "email": u.email,
            "disabled": u.disabled,
            "created_at": u.created_at.isoformat() if u.created_at else None,
            "personal_objects": u.personal_objects,
            "settings": u.settings_json,
        }
    )


@admin_bp.get("/usage")
@login_required
def usage():
    since = utcnow() - timedelta(days=7)
    rows = (
        UsageEvent.query.filter(UsageEvent.created_at >= since)
        .order_by(UsageEvent.id.desc())
        .limit(500)
        .all()
    )
    return render_template("admin/usage.html", events=rows)


@admin_bp.get("/audit")
@login_required
def audit_page():
    rows = AuditLog.query.order_by(AuditLog.id.desc()).limit(300).all()
    return render_template("admin/audit.html", logs=rows)
