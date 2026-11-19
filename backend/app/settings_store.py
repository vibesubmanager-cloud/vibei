"""Encrypted settings store with process-level cache invalidation."""

from __future__ import annotations

from .crypto_util import decrypt_secret, encrypt_secret, mask_secret
from .extensions import db
from .models import Setting, utcnow

_cache: dict[str, str] | None = None


def invalidate_cache():
    global _cache
    _cache = None


def _load_all() -> dict[str, str]:
    global _cache
    if _cache is not None:
        return _cache
    out: dict[str, str] = {}
    for row in Setting.query.all():
        if row.is_secret and row.value_enc:
            try:
                out[row.key] = decrypt_secret(row.value_enc)
            except Exception:
                out[row.key] = ""
        else:
            out[row.key] = row.value_plain or ""
    _cache = out
    return out


def get_setting(key: str, default: str = "") -> str:
    return _load_all().get(key, default)


def get_bool(key: str, default: bool = False) -> bool:
    v = get_setting(key, "1" if default else "0").lower()
    return v in ("1", "true", "yes", "on")


def get_int(key: str, default: int = 0) -> int:
    try:
        return int(get_setting(key, str(default)))
    except ValueError:
        return default


def set_setting(key: str, value: str, *, secret: bool = False):
    row = Setting.query.filter_by(key=key).first()
    if row is None:
        row = Setting(key=key)
        db.session.add(row)
    row.is_secret = secret
    row.updated_at = utcnow()
    if secret:
        if value:
            row.value_enc = encrypt_secret(value)
        # empty value means keep existing secret
        row.value_plain = None
    else:
        row.value_plain = value
        row.value_enc = None
    db.session.commit()
    invalidate_cache()


def secret_masked(key: str) -> str:
    val = get_setting(key, "")
    return mask_secret(val)


DEFAULTS = {
    "ai_provider": "gemini",
    "ai_model": "gemini-2.0-flash",
    # Set via admin panel or env — never commit real keys.
    "ai_api_key": "",
    "feature_online_describe": "1",
    "feature_online_read": "1",
    "feature_voice_assistant": "1",
    "prompt_describe": (
        "You are the eyes of a blind person. Describe what the camera sees in short, "
        "natural sentences. Start with anything important or hazardous, then the layout: "
        "what is ahead, on the left, on the right, and how near. Group related things "
        "(for example items on a desk) instead of listing them one by one. Name electronics "
        "and cables, such as charging cables, when you can see them. Say 'it looks like' "
        "when unsure. Never invent details. Do not repeat what was already said in the "
        "previous description. Keep it concise. Plain spoken English, no lists or formatting."
    ),
    "prompt_locate": (
        "Find the target object in the image. Reply with JSON only: "
        '{"found":true|false,"matches":[{"grid":"top-left|top-center|top-right|'
        'middle-left|center|middle-right|bottom-left|bottom-center|bottom-right",'
        '"description":"short","confidence":0.0}]}'
    ),
    "prompt_read": (
        "Extract all readable text in correct reading order. "
        "Preserve paragraphs and columns."
    ),
    "prompt_voice": (
        "Map the user utterance to one app intent JSON with keys: "
        "intent, params, reply. Intents: object_search, text_search, "
        "describe, describe_detail, document_read, stop, clarify."
    ),
    "max_image_bytes": str(3 * 1024 * 1024),
    "provider_timeout_sec": "25",
    "languages": "en",
    "quota_describe_day": "50",
    "quota_read_day": "50",
    "quota_voice_day": "100",
    "maintenance_message": "",
    "min_app_version": "0.1.0",
    "consent_text": (
        "Online vision sends camera frames to our servers for description "
        "or reading. Frames are processed in memory and not stored."
    ),
    "consent_version": "1",
}


def ensure_defaults():
    import os

    secrets = {"ai_api_key", "cloudinary_api_key", "cloudinary_api_secret"}
    for k, v in DEFAULTS.items():
        row = Setting.query.filter_by(key=k).first()
        if row is None:
            set_setting(k, v, secret=k in secrets)
        elif k == "ai_api_key" and not get_setting("ai_api_key"):
            set_setting(k, v, secret=True)
        elif k in ("ai_provider", "ai_model") and not get_setting(k):
            set_setting(k, v, secret=False)

    # Seed Cloudinary / AI from environment when DB values are empty.
    env_map = {
        "cloudinary_cloud_name": os.environ.get("CLOUDINARY_CLOUD_NAME", ""),
        "cloudinary_api_key": os.environ.get("CLOUDINARY_API_KEY", ""),
        "cloudinary_api_secret": os.environ.get("CLOUDINARY_API_SECRET", ""),
        "ai_api_key": os.environ.get("AI_API_KEY", ""),
        "ai_provider": os.environ.get("AI_PROVIDER", ""),
        "ai_model": os.environ.get("AI_MODEL", ""),
    }
    for key, value in env_map.items():
        if value and not get_setting(key):
            set_setting(key, value, secret=key in secrets)
