from datetime import timezone

from flask import Blueprint, jsonify, request

from .extensions import db
from .models import Admin, BootstrapState, utcnow
from .settings_store import ensure_defaults

bootstrap_bp = Blueprint("bootstrap", __name__)


@bootstrap_bp.post("/bootstrap/admin")
def bootstrap_admin():
    ensure_defaults()
    state = BootstrapState.query.first()
    if state is None:
        state = BootstrapState(used=False)
        db.session.add(state)
        db.session.commit()
    if state.used:
        return jsonify({"error": "disabled", "message": "Bootstrap already used"}), 410

    token = request.headers.get("X-Bootstrap-Token") or (
        request.get_json(silent=True) or {}
    ).get("token")
    expected = request.environ.get("ADMIN_BOOTSTRAP_TOKEN") or __import__(
        "os"
    ).environ.get("ADMIN_BOOTSTRAP_TOKEN", "")
    if not expected or token != expected:
        return jsonify({"error": "unauthorized", "message": "Bad bootstrap token"}), 401

    data = request.get_json(silent=True) or {}
    email = (data.get("email") or "").strip().lower()
    password = data.get("password") or ""
    if not email or len(password) < 10:
        return jsonify({"error": "invalid", "message": "email + password(10+) required"}), 400
    if Admin.query.filter_by(email=email).first():
        return jsonify({"error": "conflict", "message": "Admin exists"}), 409

    admin = Admin(email=email)
    admin.set_password(password)
    db.session.add(admin)
    state.used = True
    state.used_at = utcnow()
    db.session.commit()
    return jsonify({"ok": True, "email": email}), 201
