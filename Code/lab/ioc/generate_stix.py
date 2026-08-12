#!/usr/bin/env python3
"""Convert the project's reviewed IOC register to a small STIX 2.1 bundle."""

from __future__ import annotations

import argparse
import csv
import json
import uuid
from datetime import datetime, timezone
from pathlib import Path

NAMESPACE = uuid.UUID("9e3fa38d-018f-43c5-9176-42a7fd8062aa")

# Incident-response exports may legitimately contain long source-reference
# fields. Raise the conservative Python CSV default while keeping a finite
# upper bound so malformed evidence cannot request unbounded memory.
csv.field_size_limit(64 * 1024 * 1024)


def stix_id(kind: str, value: str) -> str:
    return f"indicator--{uuid.uuid5(NAMESPACE, f'{kind}:{value}')}"


def escape(value: str) -> str:
    return value.replace("\\", "\\\\").replace("'", "\\'")


def pattern(kind: str, value: str) -> str:
    value = escape(value)
    if kind == "ipv4":
        return f"[ipv4-addr:value = '{value}']"
    if kind == "domain":
        return f"[domain-name:value = '{value}']"
    if kind == "sha256":
        return f"[file:hashes.'SHA-256' = '{value}']"
    raise ValueError(f"Unsupported IOC type: {kind}")


def main() -> int:
    parser = argparse.ArgumentParser(description="Generate a STIX 2.1 indicator bundle.")
    parser.add_argument("input_csv", type=Path)
    parser.add_argument("output_json", type=Path)
    args = parser.parse_args()
    now = datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")
    objects = []
    with args.input_csv.open(newline="", encoding="utf-8") as handle:
        for row in csv.DictReader(handle):
            kind = row["type"]
            value = row["value"]
            if kind not in {"ipv4", "domain", "sha256"}:
                continue
            labels = ["course-lab", row.get("classification", "needs-review")]
            objects.append(
                {
                    "type": "indicator",
                    "spec_version": "2.1",
                    "id": stix_id(kind, value),
                    "created": now,
                    "modified": now,
                    "name": f"IR course lab observable: {value}",
                    "description": row.get("analyst_note", "Observed in the lab evidence."),
                    "indicator_types": ["unknown"],
                    "pattern": pattern(kind, value),
                    "pattern_type": "stix",
                    "pattern_version": "2.1",
                    "valid_from": now,
                    "labels": labels,
                    "confidence": int(row.get("confidence") or 0),
                }
            )
    bundle = {
        "type": "bundle",
        "id": f"bundle--{uuid.uuid4()}",
        "objects": objects,
    }
    args.output_json.parent.mkdir(parents=True, exist_ok=True)
    args.output_json.write_text(json.dumps(bundle, indent=2) + "\n", encoding="utf-8")
    print(f"Wrote {len(objects)} STIX 2.1 indicators to {args.output_json}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
