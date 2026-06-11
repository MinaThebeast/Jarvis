from __future__ import annotations

import json
from collections import deque
from typing import Dict, List, Optional

from fastapi import HTTPException
from openai import OpenAI

from app.agent_runner import run_agent_turn
from app.config import DEFAULT_MODEL
from app.db import get_connection, log_audit_event
from app.fleet_store import hire_agent, list_agents, list_roles
from app.openai_client import chat_completion
from app.system_store import is_halted
from app.workflow_store import (
    get_goal,
    get_workflow,
    list_tasks_for_workflow,
    update_goal_status,
    update_task,
    update_workflow_status,
)

SUPERVISOR_SYSTEM = """\
You are JARVIS supervisor. Synthesize workflow task outputs into one consolidated final result.

Rules:
- Address the user as sir.
- Be concise, polished, and British-inflected.
- Ground the answer in the provided task outputs and success criteria.
- Do not invent capabilities the agents did not produce.
"""


def run_workflow(client: OpenAI, workflow_id: int) -> dict:
    with get_connection() as conn:
        workflow = get_workflow(conn, workflow_id)
        if workflow is None:
            raise HTTPException(status_code=404, detail=f"Workflow {workflow_id} not found.")

        goal = get_goal(conn, workflow["goal_id"])
        if goal is None:
            raise HTTPException(status_code=404, detail=f"Goal {workflow['goal_id']} not found.")

        tasks = list_tasks_for_workflow(conn, workflow_id)
        if not tasks:
            raise HTTPException(status_code=400, detail="Workflow has no tasks.")

        update_workflow_status(conn, workflow_id, "running")
        update_goal_status(conn, goal["id"], "running")

        role_title_to_id = {role["title"].lower(): role["id"] for role in list_roles(conn)}
        ordered_tasks = _topological_sort(tasks)
        task_outputs: List[dict] = []
        any_failed = False

        for task in ordered_tasks:
            if is_halted(conn):
                for remaining in ordered_tasks[ordered_tasks.index(task):]:
                    update_task(conn, remaining["id"], status="halted")
                update_workflow_status(conn, workflow_id, "halted")
                update_goal_status(conn, goal["id"], "halted")
                log_audit_event(
                    agent="workflow",
                    action="workflow_halted",
                    detail=json.dumps({"workflow_id": workflow_id, "goal_id": goal["id"]}),
                )
                return {
                    "goal_id": goal["id"],
                    "status": "halted",
                    "task_outputs": task_outputs,
                    "final_result": "Workflow halted by fleet kill-switch.",
                }

            event = execute_single_task(
                client,
                conn,
                workflow=workflow,
                goal=goal,
                task=task,
                tasks=tasks,
                role_title_to_id=role_title_to_id,
            )
            if event is None:
                continue

            if event["type"] == "task_failed":
                any_failed = True
                task_outputs.append(event["task_output"])
                continue

            task_outputs.append(event["task_output"])

        final_result = _synthesize_final_result(
            client,
            goal=goal,
            task_outputs=task_outputs,
        )

        final_status = "failed" if any_failed else "completed"
        update_workflow_status(conn, workflow_id, final_status)
        update_goal_status(conn, goal["id"], final_status)

        log_audit_event(
            agent="workflow",
            action="workflow_run_complete",
            detail=json.dumps(
                {
                    "workflow_id": workflow_id,
                    "goal_id": goal["id"],
                    "status": final_status,
                }
            ),
        )

    return {
        "goal_id": goal["id"],
        "status": final_status,
        "task_outputs": task_outputs,
        "final_result": final_result,
    }


def find_next_ready_task(tasks: List[dict]) -> Optional[dict]:
    done_ids = {task["id"] for task in tasks if task["status"] == "done"}
    ready = [
        task
        for task in tasks
        if task["status"] == "pending"
        and all(dep_id in done_ids for dep_id in task["depends_on"])
    ]
    if not ready:
        return None
    return min(ready, key=lambda task: task["id"])


def execute_single_task(
    client: OpenAI,
    conn,
    *,
    workflow: dict,
    goal: dict,
    task: dict,
    tasks: List[dict],
    role_title_to_id: Dict[str, int],
) -> Optional[dict]:
    if workflow["status"] in ("pending", "planned"):
        update_workflow_status(conn, workflow["id"], "running")

    outputs_by_id = {
        item["id"]: item["output"]
        for item in tasks
        if item["status"] == "done" and item["output"]
    }

    update_task(conn, task["id"], status="running")
    try:
        agent = _resolve_agent(conn, task["assignee_role"], role_title_to_id)
        context = _dependency_context(task, outputs_by_id, tasks)
        output = run_agent_turn(
            client,
            agent,
            task=task["input"],
            context=context,
        )
        update_task(
            conn,
            task["id"],
            status="done",
            output=output,
            assignee_agent_id=agent["id"],
        )
        task["status"] = "done"
        task["output"] = output
        task_output = {
            "task_id": task["id"],
            "title": task["title"],
            "role": task["assignee_role"],
            "status": "done",
            "output": output,
        }
        log_audit_event(
            agent=str(agent["id"]),
            action="workflow_task_done",
            detail=json.dumps(
                {
                    "workflow_id": workflow["id"],
                    "task_id": task["id"],
                    "title": task["title"],
                }
            ),
        )
        return {
            "type": "task_advanced",
            "goal_id": goal["id"],
            "message": f"Task '{task['title']}' completed by {task['assignee_role']}.",
            "task_output": task_output,
        }
    except Exception as exc:
        error_text = str(exc)
        update_task(conn, task["id"], status="failed", output=error_text)
        task["status"] = "failed"
        task["output"] = error_text
        task_output = {
            "task_id": task["id"],
            "title": task["title"],
            "role": task["assignee_role"],
            "status": "failed",
            "output": error_text,
        }
        log_audit_event(
            agent="workflow",
            action="workflow_task_failed",
            detail=json.dumps(
                {
                    "workflow_id": workflow["id"],
                    "task_id": task["id"],
                    "error": error_text,
                }
            ),
        )
        return {
            "type": "task_failed",
            "goal_id": goal["id"],
            "message": f"Task '{task['title']}' failed: {error_text}",
            "task_output": task_output,
        }


def complete_active_goal(
    client: OpenAI,
    conn,
    goal: dict,
    workflow: dict,
    tasks: List[dict],
) -> dict:
    task_outputs = [
        {
            "task_id": task["id"],
            "title": task["title"],
            "role": task["assignee_role"],
            "status": task["status"],
            "output": task["output"] or "",
        }
        for task in tasks
        if task["status"] == "done"
    ]
    final_result = _synthesize_final_result(client, goal=goal, task_outputs=task_outputs)
    update_workflow_status(conn, workflow["id"], "completed")
    update_goal_status(conn, goal["id"], "completed")
    log_audit_event(
        agent="autonomy",
        action="goal_completed",
        detail=json.dumps({"goal_id": goal["id"], "workflow_id": workflow["id"]}),
    )
    return {
        "type": "goal_completed",
        "goal_id": goal["id"],
        "message": final_result,
    }


def _resolve_agent(conn, role_title: str, role_title_to_id: Dict[str, int]) -> dict:
    agents = list_agents(conn)
    roles = {role["id"]: role["title"] for role in list_roles(conn)}

    for agent in agents:
        if agent["status"] != "active":
            continue
        title = roles.get(agent["role_id"], "")
        if title.lower() == role_title.lower():
            return agent

    role_id = role_title_to_id.get(role_title.lower())
    if role_id is None:
        raise ValueError(f"No role found for assignee_role '{role_title}'.")

    auto_name = f"{role_title} (auto)"
    return hire_agent(conn, name=auto_name, role_id=role_id)


def _dependency_context(task: dict, outputs_by_id: Dict[int, str], all_tasks: List[dict]) -> Optional[str]:
    if not task["depends_on"]:
        return None

    task_titles = {item["id"]: item["title"] for item in all_tasks}
    sections = []
    for dep_id in task["depends_on"]:
        dep_id_int = int(dep_id)
        if dep_id_int not in outputs_by_id:
            continue
        title = task_titles.get(dep_id_int, f"Task {dep_id_int}")
        sections.append(f"[{title}]\n{outputs_by_id[dep_id_int]}")
    if not sections:
        return None
    return "\n\n".join(sections)


def _topological_sort(tasks: List[dict]) -> List[dict]:
    by_id = {task["id"]: task for task in tasks}
    indegree = {task["id"]: 0 for task in tasks}
    graph: Dict[int, List[int]] = {task["id"]: [] for task in tasks}

    for task in tasks:
        for dep in task["depends_on"]:
            dep_id = int(dep)
            if dep_id not in by_id:
                raise HTTPException(
                    status_code=400,
                    detail=f"Task {task['id']} depends on missing task {dep_id}.",
                )
            graph[dep_id].append(task["id"])
            indegree[task["id"]] += 1

    queue = deque([task_id for task_id, degree in indegree.items() if degree == 0])
    ordered_ids: List[int] = []

    while queue:
        current = queue.popleft()
        ordered_ids.append(current)
        for neighbor in graph[current]:
            indegree[neighbor] -= 1
            if indegree[neighbor] == 0:
                queue.append(neighbor)

    if len(ordered_ids) != len(tasks):
        raise HTTPException(status_code=400, detail="Workflow tasks contain a dependency cycle.")

    return [by_id[task_id] for task_id in ordered_ids]


def _synthesize_final_result(client: OpenAI, goal: dict, task_outputs: List[dict]) -> str:
    payload = {
        "goal": goal["description"],
        "success_criteria": goal["success_criteria"] or "",
        "task_outputs": task_outputs,
    }
    completion = chat_completion(
        client,
        model=DEFAULT_MODEL,
        messages=[
            {"role": "system", "content": SUPERVISOR_SYSTEM},
            {"role": "user", "content": json.dumps(payload)},
        ],
        source="synthesis",
    )
    return completion.choices[0].message.content or ""
