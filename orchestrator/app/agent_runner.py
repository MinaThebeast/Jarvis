from __future__ import annotations

from typing import Optional

from openai import OpenAI

from app.config import DEFAULT_MODEL
from app.openai_client import chat_completion


def run_agent_turn(
    client: OpenAI,
    agent: dict,
    task: str,
    context: Optional[str] = None,
) -> str:
    user_content = task.strip()
    if context and context.strip():
        user_content = f"Context:\n{context.strip()}\n\nTask:\n{user_content}"

    messages = [
        {"role": "system", "content": agent["system_prompt"]},
        {"role": "user", "content": user_content},
    ]
    model = agent.get("model") or DEFAULT_MODEL
    completion = chat_completion(
        client,
        model=model,
        messages=messages,
        source=f"agent:{agent.get('id', 'unknown')}",
    )
    return completion.choices[0].message.content or ""
