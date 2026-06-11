from __future__ import annotations

import json
from typing import List

from fastapi import APIRouter, HTTPException

from app.agent_runner import run_agent_turn
from app.db import get_connection, log_audit_event
from app.fleet_store import (
    create_role,
    get_agent,
    get_role,
    hire_agent,
    list_agents,
    list_roles,
)
from app.openai_client import get_openai_client
from app.system_store import require_not_halted
from app.schemas import (
    AgentHire,
    AgentOut,
    AgentTaskResponse,
    AgentTaskRun,
    RoleCreate,
    RoleOut,
)

router = APIRouter()


@router.post("/roles", response_model=RoleOut)
def post_role(body: RoleCreate) -> RoleOut:
    with get_connection() as conn:
        role = create_role(
            conn,
            title=body.title.strip(),
            responsibilities=body.responsibilities.strip(),
            default_tools=body.default_tools,
            default_skills=body.default_skills,
        )
    return RoleOut(**role)


@router.get("/roles", response_model=List[RoleOut])
def get_roles() -> List[RoleOut]:
    with get_connection() as conn:
        roles = list_roles(conn)
    return [RoleOut(**role) for role in roles]


@router.get("/roles/{role_id}", response_model=RoleOut)
def get_role_by_id(role_id: int) -> RoleOut:
    with get_connection() as conn:
        role = get_role(conn, role_id)
    if role is None:
        raise HTTPException(status_code=404, detail=f"Role {role_id} not found.")
    return RoleOut(**role)


@router.post("/agents", response_model=AgentOut)
def post_agent(body: AgentHire) -> AgentOut:
    name = body.name.strip()
    if not name:
        raise HTTPException(status_code=400, detail="Agent name cannot be empty.")

    with get_connection() as conn:
        try:
            agent = hire_agent(
                conn,
                name=name,
                role_id=body.role_id,
                custom_system_prompt=body.system_prompt,
                model=body.model,
                manager_id=body.manager_id,
                granted_tools=body.granted_tools,
            )
        except ValueError as exc:
            raise HTTPException(status_code=404, detail=str(exc)) from exc

    log_audit_event(
        agent=f"agent:{agent['id']}",
        action="agent_hired",
        detail=json.dumps({"name": agent["name"], "role_id": agent["role_id"]}),
    )
    return AgentOut(**agent)


@router.get("/agents", response_model=List[AgentOut])
def get_agents() -> List[AgentOut]:
    with get_connection() as conn:
        agents = list_agents(conn)
    return [AgentOut(**agent) for agent in agents]


@router.get("/agents/{agent_id}", response_model=AgentOut)
def get_agent_by_id(agent_id: int) -> AgentOut:
    with get_connection() as conn:
        agent = get_agent(conn, agent_id)
    if agent is None:
        raise HTTPException(status_code=404, detail=f"Agent {agent_id} not found.")
    return AgentOut(**agent)


@router.post("/agents/{agent_id}/run", response_model=AgentTaskResponse)
def run_agent_task(agent_id: int, body: AgentTaskRun) -> AgentTaskResponse:
    task = body.task.strip()
    if not task:
        raise HTTPException(status_code=400, detail="Task cannot be empty.")

    with get_connection() as conn:
        agent = get_agent(conn, agent_id)

    if agent is None:
        raise HTTPException(status_code=404, detail=f"Agent {agent_id} not found.")
    if agent["status"] != "active":
        raise HTTPException(status_code=400, detail=f"Agent {agent_id} is not active.")

    with get_connection() as conn:
        require_not_halted(conn)

    user_content = task
    if body.context and body.context.strip():
        user_content = f"Context:\n{body.context.strip()}\n\nTask:\n{task}"

    client = get_openai_client()

    try:
        output = run_agent_turn(client, agent, task=task, context=body.context)
    except HTTPException:
        raise
    except Exception as exc:
        log_audit_event(
            agent=str(agent_id),
            action="agent_task_error",
            detail=json.dumps({"agent_id": agent_id, "error": str(exc)}),
        )
        raise HTTPException(status_code=502, detail=f"OpenAI request failed: {exc}") from exc

    log_audit_event(
        agent=str(agent_id),
        action="agent_task_run",
        detail=json.dumps(
            {
                "agent_id": agent_id,
                "name": agent["name"],
                "task": task[:500],
                "output_length": len(output),
            }
        ),
    )
    return AgentTaskResponse(agent=agent["name"], output=output)
