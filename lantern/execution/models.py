from __future__ import annotations

from datetime import datetime

from sqlalchemy import Boolean, DateTime, String, Text
from sqlalchemy.orm import Mapped, mapped_column

from lantern.db import Base


class TradingControl(Base):
    """One row: the kill switch. Stored in the database so it holds across every process."""

    __tablename__ = "trading_control"

    id: Mapped[int] = mapped_column(primary_key=True)
    halted: Mapped[bool] = mapped_column(Boolean, default=False)
    reason: Mapped[str | None] = mapped_column(Text)
    updated_at: Mapped[datetime | None] = mapped_column(DateTime)
    updated_by: Mapped[str | None] = mapped_column(String(100))
