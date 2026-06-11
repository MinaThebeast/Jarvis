from __future__ import annotations

import sqlite3
from contextlib import contextmanager
from datetime import datetime, timezone
from typing import Iterator, List, Optional, Tuple

from app.config import DATABASE_PATH

MIGRATIONS: List[Tuple[str, str]] = [
    (
        "001_audit_events",
        """
        CREATE TABLE IF NOT EXISTS audit_events (
            id INTEGER PRIMARY KEY,
            agent VARCHAR(255) NOT NULL,
            action VARCHAR(255) NOT NULL,
            detail TEXT,
            created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
        );
        """,
    ),
    (
        "002_fleet_tables",
        """
        CREATE TABLE IF NOT EXISTS roles (
            id INTEGER PRIMARY KEY,
            title VARCHAR(255) NOT NULL,
            responsibilities TEXT NOT NULL,
            default_tools TEXT NOT NULL DEFAULT '[]',
            default_skills TEXT NOT NULL DEFAULT '[]',
            created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
        );

        CREATE TABLE IF NOT EXISTS skills (
            id INTEGER PRIMARY KEY,
            name VARCHAR(255) NOT NULL UNIQUE,
            instructions TEXT NOT NULL,
            required_tools TEXT NOT NULL DEFAULT '[]',
            created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
        );

        CREATE TABLE IF NOT EXISTS agents (
            id INTEGER PRIMARY KEY,
            name VARCHAR(255) NOT NULL,
            role_id INTEGER NOT NULL,
            system_prompt TEXT NOT NULL,
            model VARCHAR(255) NOT NULL,
            granted_tools TEXT NOT NULL DEFAULT '[]',
            skills TEXT NOT NULL DEFAULT '[]',
            manager_id INTEGER,
            status VARCHAR(50) NOT NULL DEFAULT 'active',
            created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
        );
        """,
    ),
    (
        "003_seed_starter_roles",
        """
        INSERT INTO roles (title, responsibilities, default_tools, default_skills)
        SELECT 'Copywriter', 'Draft, edit, and refine written content including emails, ads, landing pages, and social posts. Maintain brand voice, clarity, and persuasive tone.', '[]', '[]'
        WHERE NOT EXISTS (SELECT 1 FROM roles WHERE title = 'Copywriter');

        INSERT INTO roles (title, responsibilities, default_tools, default_skills)
        SELECT 'Planner', 'Break down goals into actionable steps, timelines, and milestones. Produce structured plans, priorities, and next actions.', '[]', '[]'
        WHERE NOT EXISTS (SELECT 1 FROM roles WHERE title = 'Planner');

        INSERT INTO roles (title, responsibilities, default_tools, default_skills)
        SELECT 'Analyst', 'Review information, identify patterns, and produce concise summaries, comparisons, and recommendations grounded in provided material.', '[]', '[]'
        WHERE NOT EXISTS (SELECT 1 FROM roles WHERE title = 'Analyst');
        """,
    ),
    (
        "004_workflow_tables",
        """
        CREATE TABLE IF NOT EXISTS goals (
            id INTEGER PRIMARY KEY,
            description TEXT NOT NULL,
            success_criteria TEXT,
            status VARCHAR(50) NOT NULL DEFAULT 'planned',
            created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
        );

        CREATE TABLE IF NOT EXISTS workflows (
            id INTEGER PRIMARY KEY,
            goal_id INTEGER NOT NULL,
            status VARCHAR(50) NOT NULL DEFAULT 'pending',
            created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
        );

        CREATE TABLE IF NOT EXISTS tasks (
            id INTEGER PRIMARY KEY,
            workflow_id INTEGER NOT NULL,
            title VARCHAR(255) NOT NULL,
            assignee_role VARCHAR(255) NOT NULL,
            assignee_agent_id INTEGER,
            input TEXT NOT NULL,
            output TEXT,
            status VARCHAR(50) NOT NULL DEFAULT 'pending',
            depends_on TEXT NOT NULL DEFAULT '[]',
            created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
        );
        """,
    ),
    (
        "005_governance",
        """
        CREATE TABLE IF NOT EXISTS spend_events (
            id INTEGER PRIMARY KEY,
            tokens INTEGER NOT NULL,
            source VARCHAR(255) NOT NULL,
            created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
        );

        CREATE TABLE IF NOT EXISTS system_state (
            key VARCHAR(255) PRIMARY KEY,
            value TEXT NOT NULL,
            updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
        );
        """,
    ),
    (
        "006_seed_operator_role",
        """
        INSERT INTO roles (title, responsibilities, default_tools, default_skills)
        SELECT
            'Operator',
            'Executes tasks on the machine — running commands, controlling apps, and producing files — under approval governance.',
            '["run_shell","run_applescript","control_app","see_screen","see_active_window","type_text","press_keys","mouse_click","save_deliverable"]',
            '[]'
        WHERE NOT EXISTS (SELECT 1 FROM roles WHERE title = 'Operator');
        """,
    ),
    (
        "007_autonomy",
        """
        CREATE TABLE IF NOT EXISTS autonomy_events (
            id INTEGER PRIMARY KEY,
            type VARCHAR(255) NOT NULL,
            goal_id INTEGER,
            message TEXT NOT NULL,
            created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
        );
        """,
    ),
]


def run_migrations(conn: sqlite3.Connection) -> None:
    conn.execute(
        """
        CREATE TABLE IF NOT EXISTS schema_migrations (
            version VARCHAR(255) PRIMARY KEY,
            applied_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
        )
        """
    )
    applied = {
        row[0]
        for row in conn.execute("SELECT version FROM schema_migrations").fetchall()
    }
    for version, sql in MIGRATIONS:
        if version in applied:
            continue
        conn.executescript(sql)
        conn.execute(
            "INSERT INTO schema_migrations (version) VALUES (?)",
            (version,),
        )
    conn.commit()


def init_db() -> None:
    DATABASE_PATH.parent.mkdir(parents=True, exist_ok=True)
    with get_connection() as conn:
        run_migrations(conn)


@contextmanager
def get_connection() -> Iterator[sqlite3.Connection]:
    conn = sqlite3.connect(DATABASE_PATH)
    try:
        conn.row_factory = sqlite3.Row
        yield conn
    finally:
        conn.close()


def log_audit_event(agent: str, action: str, detail: Optional[str] = None) -> None:
    with get_connection() as conn:
        conn.execute(
            """
            INSERT INTO audit_events (agent, action, detail, created_at)
            VALUES (?, ?, ?, ?)
            """,
            (agent, action, detail, datetime.now(timezone.utc).isoformat()),
        )
        conn.commit()
