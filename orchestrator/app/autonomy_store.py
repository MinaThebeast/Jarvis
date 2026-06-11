from __future__ import annotations

import sqlite3
from datetime import datetime, timezone
from typing import List, Optional


def _row_to_event(row: sqlite3.Row) -> dict:
    return {
        "id": row["id"],
        "type": row["type"],
        "goal_id": row["goal_id"],
        "message": row["message"],
        "created_at": row["created_at"],
    }


def record_event(
    conn: sqlite3.Connection,
    event_type: str,
    goal_id: Optional[int],
    message: str,
) -> dict:
    created_at = datetime.now(timezone.utc).isoformat()
    cursor = conn.execute(
        """
        INSERT INTO autonomy_events (type, goal_id, message, created_at)
        VALUES (?, ?, ?, ?)
        """,
        (event_type, goal_id, message, created_at),
    )
    conn.commit()
    row = conn.execute(
        "SELECT * FROM autonomy_events WHERE id = ?",
        (cursor.lastrowid,),
    ).fetchone()
    return _row_to_event(row)


def list_events_since(conn: sqlite3.Connection, since_id: int = 0) -> List[dict]:
    rows = conn.execute(
        """
        SELECT * FROM autonomy_events
        WHERE id > ?
        ORDER BY id
        """,
        (since_id,),
    ).fetchall()
    return [_row_to_event(row) for row in rows]
