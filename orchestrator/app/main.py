from __future__ import annotations

import json
from contextlib import asynccontextmanager
from typing import Dict, List, Optional

from fastapi import FastAPI, HTTPException
from openai import OpenAI
from pydantic import BaseModel, Field

from app.config import DEFAULT_MODEL, OPENAI_API_KEY
from app.db import init_db, log_audit_event
from app.routes_fleet import router as fleet_router


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
    yield


app = FastAPI(title="JARVIS Orchestrator", lifespan=lifespan)
app.include_router(fleet_router)


def get_openai_client() -> OpenAI:
    if not OPENAI_API_KEY:
        raise HTTPException(
            status_code=500,
            detail="OPENAI_API_KEY is not configured. Set it in the environment or orchestrator/.env.",
        )
    return OpenAI(api_key=OPENAI_API_KEY)


@app.get("/health")
def health() -> Dict[str, str]:
    return {"status": "online", "model": DEFAULT_MODEL}


@app.post("/agent/run", response_model=AgentRunResponse)
def agent_run(body: AgentRunRequest) -> AgentRunResponse:
    model = body.model or DEFAULT_MODEL
    messages: List[Dict[str, str]] = [{"role": "system", "content": body.system_prompt}]

    for item in body.history:
        messages.append({"role": item.role, "content": item.content})

    messages.append({"role": "user", "content": body.user_text})

    client = get_openai_client()

    try:
        completion = client.chat.completions.create(
            model=model,
            messages=messages,
        )
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
