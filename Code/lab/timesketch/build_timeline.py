#!/usr/bin/env python3
"""Build a Timesketch-compatible CSV from JSONL, CSV, and text evidence."""

from __future__ import annotations

import argparse
import csv
import json
import re
from datetime import datetime, timezone
from pathlib import Path

ISO_RE = re.compile(r"\b(20\d{2}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:?\d{2})?)")
SYSLOG_RE = re.compile(r"^(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\s+(\d{1,2})\s+(\d{2}:\d{2}:\d{2})")
IP_RE = re.compile(r"(?<![\w.])(?:\d{1,3}\.){3}\d{1,3}(?![\w.])")
TEXT_SUFFIXES = {".log", ".txt"}

# Some forensic exports contain long command lines or accumulated source
# references. The default 128 KiB CSV field limit is too small for them.
csv.field_size_limit(64 * 1024 * 1024)


def normalize_datetime(value: str) -> str | None:
    candidate = value.strip().replace("Z", "+00:00")
    try:
        dt = datetime.fromisoformat(candidate)
    except ValueError:
        return None
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    return dt.isoformat()


def timestamp_from_text(line: str) -> str | None:
    match = ISO_RE.search(line)
    if match:
        return normalize_datetime(match.group(1))
    match = SYSLOG_RE.search(line)
    if match:
        dt = datetime.strptime(f"2026 {match.group(1)} {match.group(2)} {match.group(3)} +0300", "%Y %b %d %H:%M:%S %z")
        return dt.isoformat()
    return None


def infer_event_type(message: str) -> str:
    text = message.lower()
    mapping = [
        ("failed password", "authentication_failure"),
        ("event=failed_login", "authentication_failure"),
        ("accepted password", "authentication_success"),
        ("event=login_success", "authentication_success"),
        ("sensitive_file", "file_change"),
        ("http_server", "process_start"),
        ("benign_process_started", "process_start"),
        ("contain", "containment"),
        ("volatility", "memory_analysis"),
        ("disk", "disk_analysis"),
        ("backup", "recovery"),
    ]
    for marker, event_type in mapping:
        if marker in text:
            return event_type
    return "evidence_event"


def row_from_dict(item: dict, source: str) -> dict[str, str] | None:
    raw_dt = str(item.get("datetime") or item.get("timestamp") or item.get("time") or "")
    dt = normalize_datetime(raw_dt)
    if not dt:
        return None
    message = str(item.get("message") or item.get("description") or json.dumps(item, sort_keys=True))
    return {
        "datetime": dt,
        "timestamp_desc": str(item.get("timestamp_desc") or "Event time"),
        "message": message,
        "source": str(item.get("source") or source),
        "event_type": str(item.get("event_type") or infer_event_type(message)),
        "hostname": str(item.get("hostname") or item.get("host") or ""),
        "user": str(item.get("user") or ""),
        "ip": str(item.get("ip") or ""),
        "tag": str(item.get("tag") or "safe-simulation"),
    }


def collect(root: Path, output: Path) -> list[dict[str, str]]:
    rows: list[dict[str, str]] = []
    for path in sorted(root.rglob("*")):
        if not path.is_file() or path.resolve() == output.resolve():
            continue
        relative = str(path.relative_to(root))
        if path.suffix.lower() == ".jsonl":
            for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
                try:
                    item = json.loads(line)
                except json.JSONDecodeError:
                    continue
                row = row_from_dict(item, relative)
                if row:
                    rows.append(row)
        elif path.suffix.lower() == ".csv":
            try:
                with path.open(newline="", encoding="utf-8", errors="replace") as handle:
                    for item in csv.DictReader(handle):
                        row = row_from_dict(dict(item), relative)
                        if row:
                            rows.append(row)
            except (OSError, csv.Error):
                continue
        elif path.suffix.lower() in TEXT_SUFFIXES:
            for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
                dt = timestamp_from_text(line)
                if not dt:
                    continue
                ips = IP_RE.findall(line)
                rows.append(
                    {
                        "datetime": dt,
                        "timestamp_desc": "Log event time",
                        "message": line.strip(),
                        "source": relative,
                        "event_type": infer_event_type(line),
                        "hostname": "",
                        "user": "",
                        "ip": ips[0] if ips else "",
                        "tag": "safe-simulation" if "simulation" in line.lower() else "evidence",
                    }
                )
    unique: dict[tuple[str, str, str], dict[str, str]] = {}
    for row in rows:
        unique[(row["datetime"], row["message"], row["source"])] = row
    return sorted(unique.values(), key=lambda row: (row["datetime"], row["source"], row["message"]))


def main() -> int:
    parser = argparse.ArgumentParser(description="Build a Timesketch CSV from IR lab evidence.")
    parser.add_argument("input_root", type=Path)
    parser.add_argument("output_csv", type=Path)
    args = parser.parse_args()
    if not args.input_root.is_dir():
        parser.error(f"Input directory not found: {args.input_root}")
    args.output_csv.parent.mkdir(parents=True, exist_ok=True)
    rows = collect(args.input_root, args.output_csv)
    fields = ["datetime", "timestamp_desc", "message", "source", "event_type", "hostname", "user", "ip", "tag"]
    with args.output_csv.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields)
        writer.writeheader()
        writer.writerows(rows)
    print(f"Wrote {len(rows)} timeline events to {args.output_csv}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
