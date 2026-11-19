from datetime import timedelta

from .extensions import db
from .models import UsageEvent, utcnow
from .settings_store import get_int


def under_quota(user_id: int | None, feature: str) -> bool:
    if user_id is None:
        return True
    day_key = {
        "describe": "quota_describe_day",
        "read": "quota_read_day",
        "voice": "quota_voice_day",
    }.get(feature, "quota_describe_day")
    limit = get_int(day_key, 50)
    since = utcnow() - timedelta(days=1)
    used = (
        UsageEvent.query.filter(
            UsageEvent.user_id == user_id,
            UsageEvent.feature == feature,
            UsageEvent.created_at >= since,
            UsageEvent.ok.is_(True),
        ).count()
    )
    return used < limit


def record_usage(
    user_id: int | None,
    feature: str,
    ok: bool,
    latency_ms: int,
    error_code: str | None = None,
):
    ev = UsageEvent(
        user_id=user_id,
        feature=feature,
        ok=ok,
        latency_ms=latency_ms,
        error_code=error_code,
    )
    db.session.add(ev)
    db.session.commit()
