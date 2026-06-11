from __future__ import annotations

import json

from fastapi import APIRouter, HTTPException

from app.db import get_connection, log_audit_event
from app.openai_client import get_openai_client
from app.system_store import require_not_halted
from app.planner import plan_goal
from app.executor import run_workflow
from app.schemas import GoalPlanRequest, GoalPlanResponse, WorkflowRunResponse

router = APIRouter()


@router.post("/goals/plan", response_model=GoalPlanResponse)
def post_goal_plan(body: GoalPlanRequest) -> GoalPlanResponse:
    description = body.description.strip()
    if not description:
        raise HTTPException(status_code=400, detail="description cannot be empty.")

    with get_connection() as conn:
        require_not_halted(conn)

    client = get_openai_client()
    result = plan_goal(client, description=description, success_criteria=body.success_criteria)
    log_audit_event(
        agent="planner",
        action="goal_planned",
        detail=json.dumps(
            {
                "goal_id": result["goal_id"],
                "workflow_id": result["workflow_id"],
                "task_count": len(result["tasks"]),
            }
        ),
    )
    return GoalPlanResponse(**result)


@router.post("/workflows/{workflow_id}/run", response_model=WorkflowRunResponse)
def post_workflow_run(workflow_id: int) -> WorkflowRunResponse:
    with get_connection() as conn:
        require_not_halted(conn)

    client = get_openai_client()
    result = run_workflow(client, workflow_id)
    return WorkflowRunResponse(**result)
