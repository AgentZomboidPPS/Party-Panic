from __future__ import annotations

from sqlalchemy import select
from sqlalchemy.orm import Session

from lantern.models import AuditEvent


def record(
    session: Session,
    *,
    actor: str,
    entity_type: str,
    entity_id: int | None,
    action: str,
    detail: dict | None = None,
) -> AuditEvent:
    event = AuditEvent(
        actor=actor, entity_type=entity_type, entity_id=entity_id, action=action, detail=detail
    )
    session.add(event)
    session.flush()
    return event


def recent(session: Session, limit: int = 100, entity_type: str | None = None) -> list[AuditEvent]:
    q = select(AuditEvent).order_by(AuditEvent.id.desc()).limit(limit)
    if entity_type:
        q = q.where(AuditEvent.entity_type == entity_type)
    return list(session.execute(q).scalars())
