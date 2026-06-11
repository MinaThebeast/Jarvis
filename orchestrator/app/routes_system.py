from __future__ import annotations

import json

from fastapi import APIRouter

from app.db import get_connection, log_audit_event
from app.schemas import HaltResponse, ResumeResponse, SpendSummary
from app.spend_store import get_spend_summary
from app.system_store import halt_fleet, resume_fleet

router = APIRouter()


@router.post("/halt", response_model=HaltResponse)
def post_halt() -> HaltResponse:
    with get_connection() as conn:
        counts = halt_fleet(conn)
    log_audit_event(
        agent="orchestrator",
        action="fleet_halted",
        detail=json.dumps(counts),
    )
    return HaltResponse(status="halted", **counts)


@router.post("/resume", response_model=ResumeResponse)
def post_resume() -> ResumeResponse:
    with get_connection() as conn:
        resume_fleet(conn)
    log_audit_event(agent="orchestrator", action="fleet_resumed", detail=None)
    return ResumeResponse(status="resumed")


@router.get("/spend", response_model=SpendSummary)
def get_spend() -> SpendSummary:
    with get_connection() as conn:
        summary = get_spend_summary(conn)
    return SpendSummary(**summary)
