from __future__ import annotations

from fastapi import APIRouter

from spectre import __version__, audit
from spectre.api.deps import DB
from spectre.schemas import AuditOut

router = APIRouter(tags=["system"])


@router.get("/health")
def health() -> dict:
    return {"status": "ok", "version": __version__}


@router.get("/audit", response_model=list[AuditOut])
def audit_log(db: DB, limit: int = 100, entity_type: str | None = None):
    return audit.recent(db, limit=limit, entity_type=entity_type)
