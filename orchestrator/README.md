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

Tables: `audit_events`, `roles`, `agents`, `skills` — portable SQL for future Postgres migration.

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
