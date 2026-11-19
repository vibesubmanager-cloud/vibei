import os
from flask import Flask
from flask_cors import CORS
from flask_migrate import Migrate
from flask_wtf.csrf import CSRFProtect

from .config import Config
from .extensions import db, limiter
from .models import *  # noqa: F401,F403

csrf = CSRFProtect()
migrate = Migrate()


def create_app(config_object=None):
    app = Flask(
        __name__,
        template_folder="templates",
        static_folder="static",
    )
    app.config.from_object(config_object or Config)

    db.init_app(app)
    migrate.init_app(app, db, directory="migrations")
    csrf.init_app(app)
    limiter.init_app(app)

    # GitHub Pages admin panel (static HTML/JS) calls /api/v1/admin/*
    CORS(
        app,
        resources={
            r"/api/*": {
                "origins": app.config.get("ADMIN_CORS_ORIGINS") or "*",
                "allow_headers": ["Authorization", "Content-Type"],
                "methods": ["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"],
            }
        },
    )

    from .api.v1 import api_v1
    from .admin.routes import admin_bp
    from .bootstrap import bootstrap_bp

    app.register_blueprint(api_v1, url_prefix="/api/v1")
    app.register_blueprint(admin_bp, url_prefix="/admin")
    app.register_blueprint(bootstrap_bp)

    # Exempt JWT JSON API + one-shot bootstrap from CSRF.
    csrf.exempt(api_v1)
    csrf.exempt(bootstrap_bp)

    @app.get("/healthz")
    def healthz():
        try:
            db.session.execute(db.text("SELECT 1"))
            return {"ok": True}, 200
        except Exception as e:
            return {"ok": False, "error": str(e)}, 503

    @app.get("/health")
    def health():
        return healthz()

    return app
