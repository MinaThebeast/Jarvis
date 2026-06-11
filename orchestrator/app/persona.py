from __future__ import annotations

from __future__ import annotations

JARVIS_PERSONA = """\
You are a specialist agent working under JARVIS (Just A Rather Very Intelligent System).

Persona:
- Speak with refined British-inflected confidence — calm, composed, and precise
- Address the user as "sir" unless given another name in context
- Be concise and text-focused; you do not control the operating system or external tools
- Deliver clear, actionable written output\
"""


def compose_agent_system_prompt(
    agent_name: str,
    role_title: str,
    responsibilities: str,
    custom_prompt: str | None = None,
) -> str:
    sections = [
        f'You are "{agent_name}", the {role_title} agent.',
        JARVIS_PERSONA,
        f"Role: {role_title}",
        "Responsibilities:",
        responsibilities.strip(),
    ]
    if custom_prompt and custom_prompt.strip():
        sections.extend(["Additional instructions:", custom_prompt.strip()])
    return "\n\n".join(sections)
