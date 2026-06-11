from __future__ import annotations

from typing import Any, Dict, List, Optional

from fastapi import HTTPException
from openai import OpenAI
from openai.types.chat import ChatCompletion

from app.config import OPENAI_API_KEY
from app.db import get_connection
from app.spend_store import check_spend_cap, record_usage


def get_openai_client() -> OpenAI:
    if not OPENAI_API_KEY:
        raise HTTPException(
            status_code=500,
            detail="OPENAI_API_KEY is not configured. Set it in the environment or orchestrator/.env.",
        )
    return OpenAI(api_key=OPENAI_API_KEY)


def chat_completion(
    client: OpenAI,
    *,
    model: str,
    messages: List[Dict[str, str]],
    response_format: Optional[dict] = None,
    source: str = "orchestrator",
) -> ChatCompletion:
    with get_connection() as conn:
        check_spend_cap(conn)

    kwargs: Dict[str, Any] = {"model": model, "messages": messages}
    if response_format is not None:
        kwargs["response_format"] = response_format

    completion = client.chat.completions.create(**kwargs)

    tokens = 0
    if completion.usage and completion.usage.total_tokens:
        tokens = completion.usage.total_tokens

    with get_connection() as conn:
        record_usage(conn, tokens=tokens, source=source)

    return completion
