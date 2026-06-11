from __future__ import annotations

from typing import List, Optional

from fastapi import APIRouter, HTTPException, Query

from app.autonomy_store import list_events_since, record_event
from app.db import get_connection, log_audit_event
from app.schemas import AutonomyEventOut, AutonomyStatus, AutonomyUpdate, GoalOut
from app.system_store import is_autonomy_enabled, set_autonomy_enabled
from app.workflow_store import get_goal, get_workflow_for_goal, list_goals, update_goal_status

router = APIRouter()


@router.get("/autonomy", response_model=AutonomyStatus)
def get_autonomy() -> AutonomyStatus:
    with get_connection() as conn:
        enabled = is_autonomy_enabled(conn)
    return AutonomyStatus(enabled=enabled)


@router.post("/autonomy", response_model=AutonomyStatus)
def post_autonomy(body: AutonomyUpdate) -> AutonomyStatus:
    with get_connection() as conn:
        set_autonomy_enabled(conn, body.enabled)
        enabled = is_autonomy_enabled(conn)
        if body.enabled:
            record_event(
                conn,
                event_type="autonomy_enabled",
                goal_id=None,
                message="Autonomous heartbeat enabled.",
            )
        else:
            record_event(
                conn,
                event_type="autonomy_disabled",
                goal_id=None,
                message="Autonomous heartbeat disabled.",
            )
    log_audit_event(
        agent="autonomy",
        action="autonomy_toggled",
        detail=f'{{"enabled": {str(body.enabled).lower()}}}',
    )
    return AutonomyStatus(enabled=enabled)


@router.get("/autonomy/events", response_model=List[AutonomyEventOut])
def get_autonomy_events(since: int = Query(default=0, ge=0)) -> List[AutonomyEventOut]:
    with get_connection() as conn:
        events = list_events_since(conn, since_id=since)
    return [AutonomyEventOut(**event) for event in events]


@router.get("/goals", response_model=List[GoalOut])
def get_goals() -> List[GoalOut]:
    with get_connection() as conn:
        goals = list_goals(conn)
        payload = []
        for goal in goals:
            workflow = get_workflow_for_goal(conn, goal["id"])
            payload.append(
                GoalOut(
                    **goal,
                    workflow_id=workflow["id"] if workflow else None,
                )
            )
    return payload


@router.post("/goals/{goal_id}/activate", response_model=GoalOut)
def activate_goal(goal_id: int) -> GoalOut:
    with get_connection() as conn:
        goal = get_goal(conn, goal_id)
        if goal is None:
            raise HTTPException(status_code=404, detail=f"Goal {goal_id} not found.")
        if goal["status"] not in ("planned", "paused"):
            raise HTTPException(
                status_code=400,
                detail=f"Goal {goal_id} cannot be activated from status '{goal['status']}'.",
            )
        update_goal_status(conn, goal_id, "active")
        goal = get_goal(conn, goal_id)
        workflow = get_workflow_for_goal(conn, goal_id)
        record_event(
            conn,
            event_type="goal_activated",
            goal_id=goal_id,
            message=f"Goal {goal_id} activated for autonomous advancement.",
        )
    return GoalOut(**goal, workflow_id=workflow["id"] if workflow else None)


@router.post("/goals/{goal_id}/pause", response_model=GoalOut)
def pause_goal(goal_id: int) -> GoalOut:
    with get_connection() as conn:
        goal = get_goal(conn, goal_id)
        if goal is None:
            raise HTTPException(status_code=404, detail=f"Goal {goal_id} not found.")
        if goal["status"] != "active":
            raise HTTPException(
                status_code=400,
                detail=f"Goal {goal_id} cannot be paused from status '{goal['status']}'.",
            )
        update_goal_status(conn, goal_id, "paused")
        goal = get_goal(conn, goal_id)
        workflow = get_workflow_for_goal(conn, goal_id)
        record_event(
            conn,
            event_type="goal_paused",
            goal_id=goal_id,
            message=f"Goal {goal_id} paused.",
        )
    return GoalOut(**goal, workflow_id=workflow["id"] if workflow else None)
