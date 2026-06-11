from __future__ import annotations

import sqlite3
from datetime import datetime, timezone
from typing import Dict

from fastapi import HTTPException

HALT_KEY = "fleet_halted"
AUTONOMY_KEY = "autonomy_enabled"


def is_halted(conn: sqlite3.Connection) -> bool:
    row = conn.execute(
        "SELECT value FROM system_state WHERE key = ?",
        (HALT_KEY,),
    ).fetchone()
    return row is not None and row["value"] == "true"


def set_halted(conn: sqlite3.Connection, halted: bool) -> None:
    now = datetime.now(timezone.utc).isoformat()
    conn.execute(
        """
        INSERT INTO system_state (key, value, updated_at)
        VALUES (?, ?, ?)
        ON CONFLICT(key) DO UPDATE SET value = excluded.value, updated_at = excluded.updated_at
        """,
        (HALT_KEY, "true" if halted else "false", now),
    )
    conn.commit()


def halt_fleet(conn: sqlite3.Connection) -> Dict[str, int]:
    set_halted(conn, True)

    workflows = conn.execute(
        "UPDATE workflows SET status = 'halted' WHERE status = 'running'"
    ).rowcount
    goals = conn.execute(
        "UPDATE goals SET status = 'halted' WHERE status IN ('running', 'active')"
    ).rowcount
    tasks = conn.execute(
        "UPDATE tasks SET status = 'halted' WHERE status = 'running'"
    ).rowcount
    conn.commit()

    return {
        "workflows_halted": workflows,
        "goals_halted": goals,
        "tasks_halted": tasks,
    }


def resume_fleet(conn: sqlite3.Connection) -> None:
    set_halted(conn, False)


def require_not_halted(conn: sqlite3.Connection) -> None:
    if is_halted(conn):
        raise HTTPException(
            status_code=503,
            detail="Fleet is halted. POST /resume to re-enable agent runs.",
        )


def is_autonomy_enabled(conn: sqlite3.Connection) -> bool:
    row = conn.execute(
        "SELECT value FROM system_state WHERE key = ?",
        (AUTONOMY_KEY,),
    ).fetchone()
    return row is not None and row["value"] == "true"


def set_autonomy_enabled(conn: sqlite3.Connection, enabled: bool) -> None:
    now = datetime.now(timezone.utc).isoformat()
    conn.execute(
        """
        INSERT INTO system_state (key, value, updated_at)
        VALUES (?, ?, ?)
        ON CONFLICT(key) DO UPDATE SET value = excluded.value, updated_at = excluded.updated_at
        """,
        (AUTONOMY_KEY, "true" if enabled else "false", now),
    )
    conn.commit()
