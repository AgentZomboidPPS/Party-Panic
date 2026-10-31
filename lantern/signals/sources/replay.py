"""Replay posts and quotes from a JSONL file (one object per line, `type` = post | quote).

Useful for recording a live session once and re-running the pipeline deterministically.
"""

from __future__ import annotations

import asyncio
import json
from datetime import datetime
from pathlib import Path

from lantern.signals.sources.base import Emit, MarketQuote, Post


class ReplaySource:
    name = "replay"

    def __init__(self, path: str, speed: float = 0.0):
        """speed=0 replays as fast as possible; speed=1 keeps the original pacing."""
        self.path = Path(path)
        self.speed = speed

    async def run(self, emit: Emit, stop: asyncio.Event) -> None:
        prev: datetime | None = None
        with self.path.open() as fh:
            for line in fh:
                if stop.is_set():
                    return
                obj = json.loads(line)
                kind = obj.pop("type", "post")
                ts_key = "created_at" if kind == "post" else "observed_at"
                obj[ts_key] = datetime.fromisoformat(obj[ts_key])
                if "close_time" in obj and obj["close_time"]:
                    obj["close_time"] = datetime.fromisoformat(obj["close_time"])
                if self.speed and prev is not None:
                    gap = (obj[ts_key] - prev).total_seconds() / self.speed
                    if gap > 0:
                        await asyncio.sleep(min(gap, 5.0))
                prev = obj[ts_key]
                await emit(Post(**obj) if kind == "post" else MarketQuote(**obj))
