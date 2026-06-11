from __future__ import annotations

from typing import List, Optional

from pydantic import BaseModel, Field


class RoleCreate(BaseModel):
    title: str
    responsibilities: str
    default_tools: List[str] = Field(default_factory=list)
    default_skills: List[str] = Field(default_factory=list)


class RoleOut(BaseModel):
    id: int
    title: str
    responsibilities: str
    default_tools: List[str]
    default_skills: List[str]
    created_at: str


class AgentHire(BaseModel):
    name: str
    role_id: int
    system_prompt: Optional[str] = None
    model: Optional[str] = None
    manager_id: Optional[int] = None


class AgentOut(BaseModel):
    id: int
    name: str
    role_id: int
    system_prompt: str
    model: str
    granted_tools: List[str]
    skills: List[str]
    manager_id: Optional[int]
    status: str
    created_at: str


class SkillOut(BaseModel):
    id: int
    name: str
    instructions: str
    required_tools: List[str]
    created_at: str


class AgentTaskRun(BaseModel):
    task: str
    context: Optional[str] = None


class AgentTaskResponse(BaseModel):
    agent: str
    output: str
