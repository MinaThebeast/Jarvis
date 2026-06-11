import os
from pathlib import Path

from dotenv import load_dotenv

ORCHESTRATOR_ROOT = Path(__file__).resolve().parent.parent
load_dotenv(ORCHESTRATOR_ROOT / ".env")

OPENAI_API_KEY = os.getenv("OPENAI_API_KEY")
DEFAULT_MODEL = "gpt-4o"
DATABASE_PATH = ORCHESTRATOR_ROOT / "jarvis.db"

# Token spend caps (rolling windows). 0 = unlimited.
SPEND_CAP_HOURLY = int(os.getenv("SPEND_CAP_HOURLY", "100000"))
SPEND_CAP_DAILY = int(os.getenv("SPEND_CAP_DAILY", "500000"))

HEARTBEAT_SECONDS = int(os.getenv("HEARTBEAT_SECONDS", "30"))
