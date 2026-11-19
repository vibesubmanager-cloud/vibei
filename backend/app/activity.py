"""Record app activities for the admin panel dashboard."""

from __future__ import annotations

from .extensions import db
from .models import ActivityEvent, User, utcnow


def record_activity(
    *,
    user_id: int | None,
    category: str,
    action: str,
    detail: dict | None = None,
    device_id: str | None = None,
    ok: bool = True,
    touch_seen: bool = True,
) -> ActivityEvent:
    ev = ActivityEvent(
        user_id=user_id,
        category=category,
        action=action,
        detail=detail or {},
        device_id=device_id,
        ok=ok,
    )
    db.session.add(ev)
    if touch_seen and user_id is not None:
        user = User.query.get(user_id)
        if user is not None:
            user.last_seen_at = utcnow()
    db.session.commit()
    return ev
