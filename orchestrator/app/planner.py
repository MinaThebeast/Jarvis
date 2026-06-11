from __future__ import annotations

import json
from typing import List, Optional

from fastapi import APIRouter, HTTPException
from openai import OpenAI

from app.config import DEFAULT_MODEL
from app.openai_client import chat_completion
from app.db import get_connection
from app.fleet_store import list_roles
from app.workflow_store import create_goal, create_task, create_workflow, update_task


PLANNER_SYSTEM = """\
You are JARVIS workflow planner. Decompose the user's goal into a short ordered task list.

Rules:
- Use ONLY role titles from the provided available roles list.
- Use at least 2 different roles when the goal warrants multiple specialties.
- Each task needs: title, role, instruction, depends_on (array of zero-based indexes of earlier tasks).
- Keep tasks text-only; agents do not control the OS.
- Return valid JSON only, matching the schema exactly.
"""


def plan_goal(
    client: OpenAI,
    description: str,
    success_criteria: Optional[str],
) -> dict:
    with get_connection() as conn:
        roles = list_roles(conn)
    if not roles:
        raise HTTPException(status_code=400, detail="No roles available to plan against.")

    role_titles = [role["title"] for role in roles]
    user_prompt = {
        "goal": description,
        "success_criteria": success_criteria or "",
        "available_roles": role_titles,
        "schema": {
            "tasks": [
                {
                    "title": "string",
                    "role": "one of available_roles",
                    "instruction": "string",
                    "depends_on": ["zero-based indexes of prior tasks"],
                }
            ]
        },
    }

    planned_tasks = _request_plan(client, user_prompt)
    _validate_planned_tasks(planned_tasks, role_titles)

    with get_connection() as conn:
        goal = create_goal(conn, description=description, success_criteria=success_criteria)
        workflow = create_workflow(conn, goal_id=goal["id"], status="pending")

        task_ids: List[int] = []
        for item in planned_tasks:
            index_deps = item.get("depends_on") or []
            task = create_task(
                conn,
                workflow_id=workflow["id"],
                title=item["title"],
                assignee_role=item["role"],
                instruction=item["instruction"],
                depends_on=[],
            )
            task_ids.append(task["id"])

        for idx, item in enumerate(planned_tasks):
            index_deps = item.get("depends_on") or []
            resolved_deps = []
            for dep in index_deps:
                if not isinstance(dep, int) or dep < 0 or dep >= len(task_ids) or dep >= idx:
                    raise HTTPException(
                        status_code=400,
                        detail=f"Invalid dependency index {dep} on planned task {idx}.",
                    )
                resolved_deps.append(task_ids[dep])
            update_task(conn, task_ids[idx], depends_on=resolved_deps)

        tasks = [
            {
                "id": task_ids[idx],
                "title": planned_tasks[idx]["title"],
                "assignee_role": planned_tasks[idx]["role"],
                "status": "pending",
                "depends_on": [
                    task_ids[dep]
                    for dep in (planned_tasks[idx].get("depends_on") or [])
                ],
            }
            for idx in range(len(planned_tasks))
        ]

    return {
        "goal_id": goal["id"],
        "workflow_id": workflow["id"],
        "tasks": tasks,
    }


def _request_plan(client: OpenAI, user_prompt: dict) -> List[dict]:
    last_error = "Unknown planner error."
    for attempt in range(2):
        try:
            completion = chat_completion(
                client,
                model=DEFAULT_MODEL,
                response_format={"type": "json_object"},
                messages=[
                    {"role": "system", "content": PLANNER_SYSTEM},
                    {"role": "user", "content": json.dumps(user_prompt)},
                ],
                source="planner",
            )
            content = completion.choices[0].message.content or ""
            payload = json.loads(content)
            tasks = payload.get("tasks")
            if not isinstance(tasks, list) or not tasks:
                raise ValueError("Planner JSON missing non-empty tasks array.")
            return tasks
        except HTTPException:
            raise
        except (json.JSONDecodeError, ValueError, KeyError, TypeError) as exc:
            last_error = str(exc)
    raise HTTPException(status_code=400, detail=f"Planner returned malformed JSON: {last_error}")


def _validate_planned_tasks(tasks: List[dict], role_titles: List[str]) -> None:
    allowed = {title.lower(): title for title in role_titles}
    for idx, task in enumerate(tasks):
        title = str(task.get("title", "")).strip()
        instruction = str(task.get("instruction", "")).strip()
        role = str(task.get("role", "")).strip()
        if not title or not instruction or not role:
            raise HTTPException(status_code=400, detail=f"Planned task {idx} missing title, role, or instruction.")
        canonical = allowed.get(role.lower())
        if canonical is None:
            raise HTTPException(
                status_code=400,
                detail=f"Planned task {idx} uses unknown role '{role}'. Allowed: {', '.join(role_titles)}.",
            )
        task["role"] = canonical
        depends_on = task.get("depends_on") or []
        if not isinstance(depends_on, list):
            raise HTTPException(status_code=400, detail=f"Planned task {idx} has invalid depends_on.")
