"""Integration tests against the real Flask app + local SQLite DB."""

import os

import pytest

os.environ.setdefault("SECRET_KEY", "test-secret")
os.environ.setdefault("MASTER_ENCRYPTION_KEY", "test-master")
os.environ.setdefault("ADMIN_BOOTSTRAP_TOKEN", "boot-test-token")
os.environ["DATABASE_URL"] = "sqlite:///vibei_test.db"

from app import create_app
from app.extensions import db
from app.models import BootstrapState
from app.settings_store import ensure_defaults, set_setting


@pytest.fixture()
def client(tmp_path, monkeypatch):
    db_path = tmp_path / "test.db"
    monkeypatch.setenv("DATABASE_URL", f"sqlite:///{db_path}")
    monkeypatch.setenv("ADMIN_BOOTSTRAP_TOKEN", "boot-test-token")
    monkeypatch.setenv("SECRET_KEY", "test-secret")
    monkeypatch.setenv("MASTER_ENCRYPTION_KEY", "test-master")
    app = create_app()
    app.config.update(
        {
            "TESTING": True,
            "WTF_CSRF_ENABLED": False,
            "SQLALCHEMY_DATABASE_URI": f"sqlite:///{db_path}",
            "SQLALCHEMY_ENGINE_OPTIONS": {"pool_pre_ping": True},
        }
    )
    with app.app_context():
        db.drop_all()
        db.create_all()
        ensure_defaults()
        db.session.add(BootstrapState(used=False))
        db.session.commit()
    return app.test_client()


def test_healthz(client):
    r = client.get("/healthz")
    assert r.status_code == 200
    assert r.get_json()["ok"] is True


def test_config_public(client):
    r = client.get("/api/v1/config")
    assert r.status_code == 200
    body = r.get_json()
    assert "ai_configured" in body
    assert "consent_text" in body


def test_signup_login_refresh(client):
    r = client.post(
        "/api/v1/auth/signup",
        json={"email": "user1@example.com", "password": "password123"},
    )
    assert r.status_code == 201, r.get_json()
    tokens = r.get_json()
    assert tokens["access_token"]
    refresh = tokens["refresh_token"]

    r2 = client.post(
        "/api/v1/auth/login",
        json={"email": "user1@example.com", "password": "password123"},
    )
    assert r2.status_code == 200

    r3 = client.post("/api/v1/auth/refresh", json={"refresh_token": refresh})
    assert r3.status_code == 200, r3.get_json()
    assert r3.get_json()["access_token"]


def test_vision_not_configured(client):
    r = client.post(
        "/api/v1/auth/signup",
        json={"email": "vision@example.com", "password": "password123"},
    )
    assert r.status_code == 201, r.get_json()
    access = r.get_json()["access_token"]
    r2 = client.post(
        "/api/v1/vision/describe",
        headers={"Authorization": f"Bearer {access}"},
        json={"image_base64": "aaaa", "scene_context": "chair"},
    )
    assert r2.status_code in (400, 502, 503)
    err = r2.get_json()["error"]
    assert err in ("not_configured", "invalid", "provider_error")


def test_bootstrap_admin_once(client):
    r = client.post(
        "/bootstrap/admin",
        headers={"X-Bootstrap-Token": "boot-test-token"},
        json={
            "email": "admin@example.com",
            "password": "ChangeMeNow1!",
            "token": "boot-test-token",
        },
    )
    assert r.status_code == 201
    r2 = client.post(
        "/bootstrap/admin",
        headers={"X-Bootstrap-Token": "boot-test-token"},
        json={
            "email": "admin2@example.com",
            "password": "ChangeMeNow1!",
            "token": "boot-test-token",
        },
    )
    assert r2.status_code == 410


def test_settings_take_effect(client):
    with client.application.app_context():
        set_setting("maintenance_message", "Down for a bit", secret=False)
    r = client.get("/api/v1/config")
    assert r.get_json()["maintenance_message"] == "Down for a bit"
