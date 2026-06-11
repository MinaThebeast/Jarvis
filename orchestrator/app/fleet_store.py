from __future__ import annotations

import sqlite3
from datetime import datetime, timezone
from typing import List, Optional

from app.config import DEFAULT_MODEL
from app.json_util import dumps_json_list, loads_json_list
from app.persona import compose_agent_system_prompt


def _row_to_role(row: sqlite3.Row) -> dict:
    return {
        "id": row["id"],
        "title": row["title"],
        "responsibilities": row["responsibilities"],
        "default_tools": loads_json_list(row["default_tools"]),
        "default_skills": loads_json_list(row["default_skills"]),
        "created_at": row["created_at"],
    }


def _row_to_agent(row: sqlite3.Row) -> dict:
    return {
        "id": row["id"],
        "name": row["name"],
        "role_id": row["role_id"],
        "system_prompt": row["system_prompt"],
        "model": row["model"],
        "granted_tools": loads_json_list(row["granted_tools"]),
        "skills": loads_json_list(row["skills"]),
        "manager_id": row["manager_id"],
        "status": row["status"],
        "created_at": row["created_at"],
    }


def _row_to_skill(row: sqlite3.Row) -> dict:
    return {
        "id": row["id"],
        "name": row["name"],
        "instructions": row["instructions"],
        "required_tools": loads_json_list(row["required_tools"]),
        "created_at": row["created_at"],
    }


def create_role(
    conn: sqlite3.Connection,
    title: str,
    responsibilities: str,
    default_tools: List[str],
    default_skills: List[str],
) -> dict:
    created_at = datetime.now(timezone.utc).isoformat()
    cursor = conn.execute(
        """
        INSERT INTO roles (title, responsibilities, default_tools, default_skills, created_at)
        VALUES (?, ?, ?, ?, ?)
        """,
        (
            title,
            responsibilities,
            dumps_json_list(default_tools),
            dumps_json_list(default_skills),
            created_at,
        ),
    )
    conn.commit()
    row = conn.execute("SELECT * FROM roles WHERE id = ?", (cursor.lastrowid,)).fetchone()
    return _row_to_role(row)


def list_roles(conn: sqlite3.Connection) -> List[dict]:
    rows = conn.execute("SELECT * FROM roles ORDER BY id").fetchall()
    return [_row_to_role(row) for row in rows]


def get_role(conn: sqlite3.Connection, role_id: int) -> Optional[dict]:
    row = conn.execute("SELECT * FROM roles WHERE id = ?", (role_id,)).fetchone()
    return _row_to_role(row) if row else None


def hire_agent(
    conn: sqlite3.Connection,
    name: str,
    role_id: int,
    custom_system_prompt: Optional[str] = None,
    model: Optional[str] = None,
    manager_id: Optional[int] = None,
) -> dict:
    role = get_role(conn, role_id)
    if role is None:
        raise ValueError(f"Role {role_id} not found.")

    if manager_id is not None and get_agent(conn, manager_id) is None:
        raise ValueError(f"Manager agent {manager_id} not found.")

    system_prompt = compose_agent_system_prompt(
        agent_name=name,
        role_title=role["title"],
        responsibilities=role["responsibilities"],
        custom_prompt=custom_system_prompt,
    )
    created_at = datetime.now(timezone.utc).isoformat()
    cursor = conn.execute(
        """
        INSERT INTO agents (
            name, role_id, system_prompt, model, granted_tools, skills,
            manager_id, status, created_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        """,
        (
            name,
            role_id,
            system_prompt,
            model or DEFAULT_MODEL,
            dumps_json_list(role["default_tools"]),
            dumps_json_list(role["default_skills"]),
            manager_id,
            "active",
            created_at,
        ),
    )
    conn.commit()
    row = conn.execute("SELECT * FROM agents WHERE id = ?", (cursor.lastrowid,)).fetchone()
    return _row_to_agent(row)


def list_agents(conn: sqlite3.Connection) -> List[dict]:
    rows = conn.execute("SELECT * FROM agents ORDER BY id").fetchall()
    return [_row_to_agent(row) for row in rows]


def get_agent(conn: sqlite3.Connection, agent_id: int) -> Optional[dict]:
    row = conn.execute("SELECT * FROM agents WHERE id = ?", (agent_id,)).fetchone()
    return _row_to_agent(row) if row else None
