from __future__ import annotations

import sqlite3
from datetime import datetime, timezone
from typing import List, Optional

from app.json_util import dumps_json_list, loads_json_list


def _row_to_goal(row: sqlite3.Row) -> dict:
    return {
        "id": row["id"],
        "description": row["description"],
        "success_criteria": row["success_criteria"],
        "status": row["status"],
        "created_at": row["created_at"],
    }


def _row_to_workflow(row: sqlite3.Row) -> dict:
    return {
        "id": row["id"],
        "goal_id": row["goal_id"],
        "status": row["status"],
        "created_at": row["created_at"],
    }


def _row_to_task(row: sqlite3.Row) -> dict:
    return {
        "id": row["id"],
        "workflow_id": row["workflow_id"],
        "title": row["title"],
        "assignee_role": row["assignee_role"],
        "assignee_agent_id": row["assignee_agent_id"],
        "input": row["input"],
        "output": row["output"],
        "status": row["status"],
        "depends_on": [int(item) for item in loads_json_list(row["depends_on"]) if str(item).isdigit()],
        "created_at": row["created_at"],
    }


def create_goal(
    conn: sqlite3.Connection,
    description: str,
    success_criteria: Optional[str],
    status: str = "planned",
) -> dict:
    created_at = datetime.now(timezone.utc).isoformat()
    cursor = conn.execute(
        """
        INSERT INTO goals (description, success_criteria, status, created_at)
        VALUES (?, ?, ?, ?)
        """,
        (description, success_criteria, status, created_at),
    )
    conn.commit()
    row = conn.execute("SELECT * FROM goals WHERE id = ?", (cursor.lastrowid,)).fetchone()
    return _row_to_goal(row)


def get_goal(conn: sqlite3.Connection, goal_id: int) -> Optional[dict]:
    row = conn.execute("SELECT * FROM goals WHERE id = ?", (goal_id,)).fetchone()
    return _row_to_goal(row) if row else None


def update_goal_status(conn: sqlite3.Connection, goal_id: int, status: str) -> None:
    conn.execute("UPDATE goals SET status = ? WHERE id = ?", (status, goal_id))
    conn.commit()


def list_goals(conn: sqlite3.Connection) -> List[dict]:
    rows = conn.execute("SELECT * FROM goals ORDER BY id DESC").fetchall()
    return [_row_to_goal(row) for row in rows]


def list_goals_by_status(conn: sqlite3.Connection, status: str) -> List[dict]:
    rows = conn.execute(
        "SELECT * FROM goals WHERE status = ? ORDER BY id",
        (status,),
    ).fetchall()
    return [_row_to_goal(row) for row in rows]


def get_workflow_for_goal(conn: sqlite3.Connection, goal_id: int) -> Optional[dict]:
    row = conn.execute(
        "SELECT * FROM workflows WHERE goal_id = ? ORDER BY id DESC LIMIT 1",
        (goal_id,),
    ).fetchone()
    return _row_to_workflow(row) if row else None


def create_workflow(
    conn: sqlite3.Connection,
    goal_id: int,
    status: str = "pending",
) -> dict:
    created_at = datetime.now(timezone.utc).isoformat()
    cursor = conn.execute(
        """
        INSERT INTO workflows (goal_id, status, created_at)
        VALUES (?, ?, ?)
        """,
        (goal_id, status, created_at),
    )
    conn.commit()
    row = conn.execute("SELECT * FROM workflows WHERE id = ?", (cursor.lastrowid,)).fetchone()
    return _row_to_workflow(row)


def get_workflow(conn: sqlite3.Connection, workflow_id: int) -> Optional[dict]:
    row = conn.execute("SELECT * FROM workflows WHERE id = ?", (workflow_id,)).fetchone()
    return _row_to_workflow(row) if row else None


def update_workflow_status(conn: sqlite3.Connection, workflow_id: int, status: str) -> None:
    conn.execute("UPDATE workflows SET status = ? WHERE id = ?", (status, workflow_id))
    conn.commit()


def create_task(
    conn: sqlite3.Connection,
    workflow_id: int,
    title: str,
    assignee_role: str,
    instruction: str,
    depends_on: List[int],
    status: str = "pending",
) -> dict:
    created_at = datetime.now(timezone.utc).isoformat()
    cursor = conn.execute(
        """
        INSERT INTO tasks (
            workflow_id, title, assignee_role, assignee_agent_id, input, output,
            status, depends_on, created_at
        ) VALUES (?, ?, ?, NULL, ?, NULL, ?, ?, ?)
        """,
        (
            workflow_id,
            title,
            assignee_role,
            instruction,
            status,
            dumps_json_list([str(item) for item in depends_on]),
            created_at,
        ),
    )
    conn.commit()
    row = conn.execute("SELECT * FROM tasks WHERE id = ?", (cursor.lastrowid,)).fetchone()
    return _row_to_task(row)


def list_tasks_for_workflow(conn: sqlite3.Connection, workflow_id: int) -> List[dict]:
    rows = conn.execute(
        "SELECT * FROM tasks WHERE workflow_id = ? ORDER BY id",
        (workflow_id,),
    ).fetchall()
    return [_row_to_task(row) for row in rows]


def update_task(
    conn: sqlite3.Connection,
    task_id: int,
    *,
    status: Optional[str] = None,
    output: Optional[str] = None,
    assignee_agent_id: Optional[int] = None,
    depends_on: Optional[List[int]] = None,
) -> None:
    fields = []
    values = []
    if status is not None:
        fields.append("status = ?")
        values.append(status)
    if output is not None:
        fields.append("output = ?")
        values.append(output)
    if assignee_agent_id is not None:
        fields.append("assignee_agent_id = ?")
        values.append(assignee_agent_id)
    if depends_on is not None:
        fields.append("depends_on = ?")
        values.append(dumps_json_list([str(item) for item in depends_on]))

    if not fields:
        return

    values.append(task_id)
    conn.execute(f"UPDATE tasks SET {', '.join(fields)} WHERE id = ?", values)
    conn.commit()
