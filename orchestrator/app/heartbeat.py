from __future__ import annotations

import asyncio
import logging

from app.autonomy_engine import heartbeat_tick
from app.config import HEARTBEAT_SECONDS

logger = logging.getLogger(__name__)


async def heartbeat_loop() -> None:
    while True:
        await asyncio.sleep(HEARTBEAT_SECONDS)
        try:
            await asyncio.to_thread(heartbeat_tick)
        except Exception:
            logger.exception("Autonomy heartbeat tick failed")
