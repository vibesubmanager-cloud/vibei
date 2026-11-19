import os


class Config:
    SECRET_KEY = os.environ.get("SECRET_KEY", "dev-change-me")
    MASTER_ENCRYPTION_KEY = os.environ.get("MASTER_ENCRYPTION_KEY", "")
    ADMIN_BOOTSTRAP_TOKEN = os.environ.get("ADMIN_BOOTSTRAP_TOKEN", "")
    DATABASE_URL = os.environ.get("DATABASE_URL", "sqlite:///vibei_local.db")

    # Neon / Render often provide postgres:// — SQLAlchemy needs postgresql://
    uri = DATABASE_URL
    if uri.startswith("postgres://"):
        uri = uri.replace("postgres://", "postgresql://", 1)
    # psycopg2 does not always accept channel_binding=require
    if "channel_binding=" in uri:
        from urllib.parse import parse_qsl, urlencode, urlparse, urlunparse

        parts = urlparse(uri)
        q = [(k, v) for k, v in parse_qsl(parts.query) if k != "channel_binding"]
        uri = urlunparse(parts._replace(query=urlencode(q)))
    SQLALCHEMY_DATABASE_URI = uri
    SQLALCHEMY_ENGINE_OPTIONS = {
        "pool_pre_ping": True,
        "pool_recycle": 280,
        "connect_args": {"sslmode": "require"}
        if uri.startswith("postgresql")
        else {},
    }
    SQLALCHEMY_TRACK_MODIFICATIONS = False

    JWT_ACCESS_MINUTES = 30
    JWT_REFRESH_DAYS = 30
    SESSION_COOKIE_HTTPONLY = True
    SESSION_COOKIE_SAMESITE = "Lax"
    SESSION_COOKIE_SECURE = os.environ.get("FLASK_ENV") == "production"
    WTF_CSRF_TIME_LIMIT = None
    MAX_CONTENT_LENGTH = 8 * 1024 * 1024

    # Comma-separated origins for the GitHub Pages admin panel.
    # Example: https://youruser.github.io,http://127.0.0.1:5500
    ADMIN_CORS_ORIGINS = [
        o.strip()
        for o in os.environ.get(
            "ADMIN_CORS_ORIGINS",
            "http://127.0.0.1:5500,http://localhost:5500,null",
        ).split(",")
        if o.strip()
    ]
