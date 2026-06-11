# JARVIS Orchestrator

Local Python backend for JARVIS. Runs separately from the Swift app, talks to OpenAI, and logs runs to SQLite.

## Setup

1. Copy your API key into `orchestrator/.env` (or export `OPENAI_API_KEY`):

```bash
echo 'OPENAI_API_KEY=sk-your-key-here' > orchestrator/.env
```

2. Start the service:

```bash
./scripts/start-orchestrator.sh
```

The server binds to **127.0.0.1:8765** only.

## Test with curl

**Health check:**

```bash
curl -s http://127.0.0.1:8765/health | python3 -m json.tool
```

Expected:

```json
{
    "status": "online",
    "model": "gpt-4o"
}
```

**Agent run (text-only):**

```bash
curl -s http://127.0.0.1:8765/agent/run \
  -H 'Content-Type: application/json' \
  -d '{
    "system_prompt": "You are JARVIS, a concise British AI assistant. Address the user as sir.",
    "history": [],
    "user_text": "What is 2 plus 2?"
  }' | python3 -m json.tool
```

Expected shape:

```json
{
    "content": "..."
}
```

Optional fields: `history` (prior messages), `model` (defaults to `gpt-4o`).

## Database

SQLite file: `orchestrator/jarvis.db`

Tables: `audit_events`, `roles`, `agents`, `skills`, `goals`, `workflows`, `tasks` — portable SQL for future Postgres migration.

Starter roles seeded on first run: **Copywriter**, **Planner**, **Analyst** (text-only, no OS tools).

---

## Agent fleet

### List starter roles

```bash
curl -s http://127.0.0.1:8765/roles | python3 -m json.tool
```

### Hire an agent from a role

```bash
curl -s http://127.0.0.1:8765/agents \
  -H 'Content-Type: application/json' \
  -d '{
    "name": "Quill",
    "role_id": 1
  }' | python3 -m json.tool
```

Use the `id` from a Copywriter/Planner/Analyst role returned by `GET /roles`. Optional fields: `system_prompt`, `model`, `manager_id`.

### Run a task with a hired agent

```bash
curl -s http://127.0.0.1:8765/agents/1/run \
  -H 'Content-Type: application/json' \
  -d '{
    "task": "Write a one-sentence tagline for a minimalist smart-home assistant.",
    "context": "Brand tone: refined, British, confident."
  }' | python3 -m json.tool
```

Expected shape:

```json
{
    "agent": "Quill",
    "output": "..."
}
```

Runs are logged to `audit_events` with the agent id. Hired agents are persisted in `agents`.

---

## Goal workflows

Plan a multi-step goal across roles, then execute tasks in dependency order with a final supervisor synthesis.

### Plan a goal

```bash
curl -s http://127.0.0.1:8765/goals/plan \
  -H 'Content-Type: application/json' \
  -d '{
    "description": "Launch a minimalist smart-home assistant called Lumen.",
    "success_criteria": "A phased launch plan, brand tagline, and risk summary."
  }' | python3 -m json.tool
```

Expected shape:

```json
{
    "goal_id": 1,
    "workflow_id": 1,
    "tasks": [
        {
            "id": 1,
            "title": "...",
            "assignee_role": "Planner",
            "status": "pending",
            "depends_on": []
        }
    ]
}
```

Tasks are persisted in `goals`, `workflows`, and `tasks`. The planner assigns each task to an available role title.

### Run a workflow

```bash
curl -s -X POST http://127.0.0.1:8765/workflows/1/run | python3 -m json.tool
```

Expected shape:

```json
{
    "goal_id": 1,
    "status": "completed",
    "task_outputs": [
        {
            "task_id": 1,
            "title": "...",
            "role": "Planner",
            "status": "done",
            "output": "..."
        }
    ],
    "final_result": "..."
}
```

The executor runs tasks sequentially in topological order, auto-hiring agents when needed, then synthesizes a consolidated `final_result`. Parallel execution is a future optimization.

---

## Autonomous heartbeat

Autonomy is **off by default**. When enabled, a background heartbeat advances **one ready task per active goal** per tick (default every 30s), respecting fleet halt and spend caps.

Environment:

- `HEARTBEAT_SECONDS` — tick interval (default `30`)

### Check autonomy status

```bash
curl -s http://127.0.0.1:8765/autonomy | python3 -m json.tool
```

Expected:

```json
{
    "enabled": false
}
```

### Enable autonomy

```bash
curl -s -X POST http://127.0.0.1:8765/autonomy \
  -H 'Content-Type: application/json' \
  -d '{"enabled": true}' | python3 -m json.tool
```

### Plan a goal, then activate it

```bash
curl -s http://127.0.0.1:8765/goals/plan \
  -H 'Content-Type: application/json' \
  -d '{
    "description": "Draft a three-bullet launch checklist for Lumen.",
    "success_criteria": "Three concise bullets."
  }' | python3 -m json.tool
```

Note the `goal_id`, then:

```bash
curl -s -X POST http://127.0.0.1:8765/goals/1/activate | python3 -m json.tool
```

### List goals

```bash
curl -s http://127.0.0.1:8765/goals | python3 -m json.tool
```

### Watch autonomous advancement events

Poll for new events after each heartbeat tick (`since` is the last event id you saw):

```bash
curl -s 'http://127.0.0.1:8765/autonomy/events?since=0' | python3 -m json.tool
```

Event types include `task_advanced`, `goal_completed`, `goal_failed`, `goal_activated`, `spend_cap_skip`, and `autonomy_enabled`.

### Pause a goal

```bash
curl -s -X POST http://127.0.0.1:8765/goals/1/pause | python3 -m json.tool
```

With autonomy enabled and a goal **active**, the heartbeat advances one ready task per tick. With autonomy **off** or the fleet **halted** (`POST /halt`), no tasks advance.
