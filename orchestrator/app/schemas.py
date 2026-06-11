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
    granted_tools: Optional[List[str]] = None


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


class GoalPlanRequest(BaseModel):
    description: str
    success_criteria: Optional[str] = None


class PlannedTaskOut(BaseModel):
    id: int
    title: str
    assignee_role: str
    status: str
    depends_on: List[int]


class GoalPlanResponse(BaseModel):
    goal_id: int
    workflow_id: int
    tasks: List[PlannedTaskOut]


class WorkflowTaskOutput(BaseModel):
    task_id: int
    title: str
    role: str
    status: str
    output: str


class WorkflowRunResponse(BaseModel):
    goal_id: int
    status: str
    task_outputs: List[WorkflowTaskOutput]
    final_result: str


class HaltResponse(BaseModel):
    status: str
    workflows_halted: int
    goals_halted: int
    tasks_halted: int


class ResumeResponse(BaseModel):
    status: str


class SpendSummary(BaseModel):
    hourly_used: int
    hourly_cap: int
    daily_used: int
    daily_cap: int


class AutonomyStatus(BaseModel):
    enabled: bool


class AutonomyUpdate(BaseModel):
    enabled: bool


class AutonomyEventOut(BaseModel):
    id: int
    type: str
    goal_id: Optional[int]
    message: str
    created_at: str


class GoalOut(BaseModel):
    id: int
    description: str
    success_criteria: Optional[str]
    status: str
    created_at: str
    workflow_id: Optional[int] = None
