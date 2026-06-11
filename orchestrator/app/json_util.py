from __future__ import annotations

from __future__ import annotations

import json
from typing import List


def dumps_json_list(values: List[str]) -> str:
    return json.dumps(values)


def loads_json_list(raw: str | None) -> List[str]:
    if not raw:
        return []
    try:
        parsed = json.loads(raw)
    except json.JSONDecodeError:
        return []
    if not isinstance(parsed, list):
        return []
    return [str(item) for item in parsed]
