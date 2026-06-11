from __future__ import annotations

import asyncio
import json
from contextlib import asynccontextmanager
from typing import Dict, List, Optional

from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, Field

from app.config import DEFAULT_MODEL
from app.db import get_connection, init_db, log_audit_event
from app.heartbeat import heartbeat_loop
from app.openai_client import chat_completion, get_openai_client
from app.routes_autonomy import router as autonomy_router
from app.routes_fleet import router as fleet_router
from app.routes_system import router as system_router
from app.routes_workflow import router as workflow_router
from app.system_store import require_not_halted


class HistoryMessage(BaseModel):
    role: str
    content: str


class AgentRunRequest(BaseModel):
    system_prompt: str
    history: List[HistoryMessage] = Field(default_factory=list)
    user_text: str
    model: Optional[str] = None


class AgentRunResponse(BaseModel):
    content: str


@asynccontextmanager
async def lifespan(_: FastAPI):
    init_db()
    heartbeat_task = asyncio.create_task(heartbeat_loop())
    yield
    heartbeat_task.cancel()
    try:
        await heartbeat_task
    except asyncio.CancelledError:
        pass


app = FastAPI(title="JARVIS Orchestrator", lifespan=lifespan)
app.include_router(fleet_router)
app.include_router(workflow_router)
app.include_router(system_router)
app.include_router(autonomy_router)


@app.get("/health")
def health() -> Dict[str, str]:
    return {"status": "online", "model": DEFAULT_MODEL}


@app.post("/agent/run", response_model=AgentRunResponse)
def agent_run(body: AgentRunRequest) -> AgentRunResponse:
    with get_connection() as conn:
        require_not_halted(conn)

    model = body.model or DEFAULT_MODEL
    messages: List[Dict[str, str]] = [{"role": "system", "content": body.system_prompt}]

    for item in body.history:
        messages.append({"role": item.role, "content": item.content})

    messages.append({"role": "user", "content": body.user_text})

    client = get_openai_client()

    try:
        completion = chat_completion(
            client,
            model=model,
            messages=messages,
            source="agent_run",
        )
    except HTTPException:
        raise
    except Exception as exc:
        log_audit_event(
            agent="orchestrator",
            action="agent_run_error",
            detail=json.dumps({"model": model, "error": str(exc)}),
        )
        raise HTTPException(status_code=502, detail=f"OpenAI request failed: {exc}") from exc

    content = completion.choices[0].message.content or ""
    log_audit_event(
        agent="orchestrator",
        action="agent_run",
        detail=json.dumps(
            {
                "model": model,
                "user_text": body.user_text[:500],
                "reply_length": len(content),
            }
        ),
    )
    return AgentRunResponse(content=content)
