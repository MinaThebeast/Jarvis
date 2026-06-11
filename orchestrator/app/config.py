import os
from pathlib import Path

from dotenv import load_dotenv

ORCHESTRATOR_ROOT = Path(__file__).resolve().parent.parent
load_dotenv(ORCHESTRATOR_ROOT / ".env")

OPENAI_API_KEY = os.getenv("OPENAI_API_KEY")
DEFAULT_MODEL = "gpt-4o"
DATABASE_PATH = ORCHESTRATOR_ROOT / "jarvis.db"
