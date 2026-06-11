from __future__ import annotations

import json
from typing import Dict, List, Optional

from fastapi import HTTPException
from openai import OpenAI

from app.agent_runner import run_agent_turn
from app.db import get_connection, log_audit_event
from app.executor import (
    complete_active_goal,
    execute_single_task,
    find_next_ready_task,
)
from app.fleet_store import list_roles
from app.openai_client import get_openai_client
from app.spend_store import get_spend_summary, is_spend_cap_exceeded
from app.system_store import is_autonomy_enabled, is_halted
from app.autonomy_store import record_event
from app.workflow_store import (
    get_goal,
    get_workflow_for_goal,
    list_goals_by_status,
    list_tasks_for_workflow,
    update_goal_status,
    update_workflow_status,
)


def advance_goal_one_step(client: OpenAI, goal_id: int) -> Optional[dict]:
    """Run one ready task for an active goal, or complete it if all tasks are done."""
    with get_connection() as conn:
        goal = get_goal(conn, goal_id)
        if goal is None or goal["status"] != "active":
            return None

        if is_halted(conn):
            return None

        workflow = get_workflow_for_goal(conn, goal_id)
        if workflow is None:
            return None

        tasks = list_tasks_for_workflow(conn, workflow["id"])
        if not tasks:
            return None

        if any(task["status"] == "failed" for task in tasks):
            update_goal_status(conn, goal_id, "failed")
            update_workflow_status(conn, workflow["id"], "failed")
            return {
                "type": "goal_failed",
                "goal_id": goal_id,
                "message": f"Goal {goal_id} failed due to a failed task.",
            }

        if any(task["status"] == "running" for task in tasks):
            return None

        pending = [task for task in tasks if task["status"] == "pending"]
        if not pending:
            return complete_active_goal(client, conn, goal, workflow, tasks)

        ready = find_next_ready_task(tasks)
        if ready is None:
            return None

        role_title_to_id = {role["title"].lower(): role["id"] for role in list_roles(conn)}
        return execute_single_task(
            client,
            conn,
            workflow=workflow,
            goal=goal,
            task=ready,
            tasks=tasks,
            role_title_to_id=role_title_to_id,
        )


def heartbeat_tick() -> None:
    with get_connection() as conn:
        if not is_autonomy_enabled(conn):
            return
        if is_halted(conn):
            return
        if is_spend_cap_exceeded(conn):
            summary = get_spend_summary(conn)
            log_audit_event(
                agent="autonomy",
                action="spend_cap_skip",
                detail=json.dumps(summary),
            )
            record_event(
                conn,
                event_type="spend_cap_skip",
                goal_id=None,
                message="Spend cap exceeded; autonomy heartbeat skipped.",
            )
            return
        active_goals = list_goals_by_status(conn, "active")

    try:
        client = get_openai_client()
    except HTTPException:
        return

    for goal in active_goals:
        with get_connection() as conn:
            if not is_autonomy_enabled(conn) or is_halted(conn) or is_spend_cap_exceeded(conn):
                break

        event = advance_goal_one_step(client, goal["id"])
        if event is None:
            continue

        with get_connection() as conn:
            record_event(
                conn,
                event_type=event["type"],
                goal_id=event.get("goal_id"),
                message=event["message"],
            )
