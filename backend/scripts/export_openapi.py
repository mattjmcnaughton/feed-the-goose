"""Write the API contract to clients/openapi.json, or check that it is current (TDD §4).

Keeps only the /v1 paths and the schemas they reference, with sorted keys, two-space
indent and a trailing newline.

    uv run python scripts/export_openapi.py          # write
    uv run python scripts/export_openapi.py --check  # fail when the file is stale
"""

import json
import sys
from pathlib import Path
from typing import Any

from feed_the_goose.app import create_app

TARGET = Path(__file__).resolve().parents[2] / "clients" / "openapi.json"
REF_PREFIX = "#/components/schemas/"


def contract() -> str:
    spec = create_app().openapi()
    spec["paths"] = {p: v for p, v in spec["paths"].items() if p.startswith("/v1/")}
    schemas = spec["components"]["schemas"]
    spec["components"]["schemas"] = {
        name: schemas[name] for name in _referenced(spec["paths"], schemas)
    }
    return json.dumps(spec, indent=2, sort_keys=True) + "\n"


def _referenced(node: Any, schemas: dict[str, Any]) -> set[str]:
    """The schema names reachable from `node`."""
    found: set[str] = set()
    pending = [node]
    while pending:
        item = pending.pop()
        if isinstance(item, dict):
            ref = item.get("$ref")
            if isinstance(ref, str) and ref.startswith(REF_PREFIX):
                name = ref.removeprefix(REF_PREFIX)
                if name not in found:
                    found.add(name)
                    pending.append(schemas[name])
            pending.extend(item.values())
        elif isinstance(item, list):
            pending.extend(item)
    return found


def main() -> int:
    text = contract()
    if "--check" in sys.argv[1:]:
        if not TARGET.exists() or TARGET.read_text() != text:
            print(
                f"{TARGET} is stale. Run `just openapi` and commit the result.",
                file=sys.stderr,
            )
            return 1
        print(f"{TARGET} is current.")
        return 0
    TARGET.parent.mkdir(parents=True, exist_ok=True)
    TARGET.write_text(text)
    print(f"Wrote {TARGET}.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
