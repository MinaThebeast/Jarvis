from __future__ import annotations

import json
import sqlite3
from datetime import datetime, timedelta, timezone
from typing import Dict

from fastapi import HTTPException

from app.config import SPEND_CAP_DAILY, SPEND_CAP_HOURLY
from app.db import log_audit_event


def record_usage(conn: sqlite3.Connection, tokens: int, source: str) -> None:
    if tokens <= 0:
        return
    created_at = datetime.now(timezone.utc).isoformat()
    conn.execute(
        """
        INSERT INTO spend_events (tokens, source, created_at)
        VALUES (?, ?, ?)
        """,
        (tokens, source, created_at),
    )
    conn.commit()


def _tokens_since(conn: sqlite3.Connection, since: datetime) -> int:
    row = conn.execute(
        """
        SELECT COALESCE(SUM(tokens), 0) AS total
        FROM spend_events
        WHERE created_at >= ?
        """,
        (since.isoformat(),),
    ).fetchone()
    return int(row["total"]) if row else 0


def get_spend_summary(conn: sqlite3.Connection) -> Dict[str, int]:
    now = datetime.now(timezone.utc)
    hourly_used = _tokens_since(conn, now - timedelta(hours=1))
    daily_used = _tokens_since(conn, now - timedelta(hours=24))
    return {
        "hourly_used": hourly_used,
        "hourly_cap": SPEND_CAP_HOURLY,
        "daily_used": daily_used,
        "daily_cap": SPEND_CAP_DAILY,
    }


def check_spend_cap(conn: sqlite3.Connection) -> None:
    summary = get_spend_summary(conn)

    if SPEND_CAP_HOURLY > 0 and summary["hourly_used"] >= SPEND_CAP_HOURLY:
        detail = (
            f"Hourly token cap exceeded ({summary['hourly_used']}/{SPEND_CAP_HOURLY}). "
            "Try again after the rolling hour window clears."
        )
        log_audit_event(
            agent="orchestrator",
            action="spend_cap_exceeded",
            detail=json.dumps({"window": "hourly", **summary}),
        )
        raise HTTPException(status_code=429, detail=detail)

    if SPEND_CAP_DAILY > 0 and summary["daily_used"] >= SPEND_CAP_DAILY:
        detail = (
            f"Daily token cap exceeded ({summary['daily_used']}/{SPEND_CAP_DAILY}). "
            "Try again after the rolling 24-hour window clears."
        )
        log_audit_event(
            agent="orchestrator",
            action="spend_cap_exceeded",
            detail=json.dumps({"window": "daily", **summary}),
        )
        raise HTTPException(status_code=429, detail=detail)


def is_spend_cap_exceeded(conn: sqlite3.Connection) -> bool:
    summary = get_spend_summary(conn)
    if SPEND_CAP_HOURLY > 0 and summary["hourly_used"] >= SPEND_CAP_HOURLY:
        return True
    if SPEND_CAP_DAILY > 0 and summary["daily_used"] >= SPEND_CAP_DAILY:
        return True
    return False
