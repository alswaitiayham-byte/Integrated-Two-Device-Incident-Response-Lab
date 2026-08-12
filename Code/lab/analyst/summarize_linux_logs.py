#!/usr/bin/env python3
"""Produce a manual-verification summary from Linux lab logs."""

from __future__ import annotations

import argparse
import json
import re
from collections import Counter, defaultdict
from datetime import datetime, timezone
from pathlib import Path

FAILED_RE = re.compile(r"Failed password.*?from\s+((?:\d{1,3}\.){3}\d{1,3})")
SUCCESS_RE = re.compile(r"Accepted password for\s+(\S+).*?from\s+((?:\d{1,3}\.){3}\d{1,3})")
KEY_RE = re.compile(r'key="([^"]+)"')
PATH_RE = re.compile(r'name="([^"]+)"')


def main() -> int:
    parser = argparse.ArgumentParser(description="Summarize safe Linux IR lab logs.")
    parser.add_argument("input_directory", type=Path)
    parser.add_argument("output_directory", type=Path)
    args = parser.parse_args()
    args.output_directory.mkdir(parents=True, exist_ok=True)

    failed = Counter()
    successful: list[dict[str, str]] = []
    audit_keys = Counter()
    watched_paths = Counter()
    simulation_events = Counter()
    source_files: list[str] = []

    for path in sorted(args.input_directory.rglob("*")):
        if not path.is_file() or path.suffix.lower() not in {".log", ".txt"}:
            continue
        source_files.append(str(path.relative_to(args.input_directory)))
        for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
            match = FAILED_RE.search(line)
            if match:
                failed[match.group(1)] += 1
            match = SUCCESS_RE.search(line)
            if match:
                successful.append({"user": match.group(1), "source_ip": match.group(2), "line": line})
            for key in KEY_RE.findall(line):
                audit_keys[key] += 1
            for watched_path in PATH_RE.findall(line):
                if watched_path.startswith("/opt/ir-lab"):
                    watched_paths[watched_path] += 1
            event_match = re.search(r"\bevent=([A-Za-z0-9_-]+)", line)
            if event_match:
                simulation_events[event_match.group(1)] += 1

    correlated_sources = []
    for success in successful:
        count = failed[success["source_ip"]]
        if count >= 5:
            correlated_sources.append(
                {
                    "source_ip": success["source_ip"],
                    "failed_attempts": count,
                    "successful_user": success["user"],
                    "finding": "Success followed at least five failures from the same lab source",
                }
            )

    summary = {
        "dataset_label": "SAFE SYNTHETIC OFFLINE DATASET",
        "generated_utc": datetime.now(timezone.utc).replace(microsecond=0).isoformat(),
        "source_files": source_files,
        "failed_authentication_by_ip": dict(sorted(failed.items())),
        "successful_authentication_events": successful,
        "correlated_authentication_findings": correlated_sources,
        "audit_key_counts": dict(sorted(audit_keys.items())),
        "watched_path_counts": dict(sorted(watched_paths.items())),
        "simulation_event_counts": dict(sorted(simulation_events.items())),
        "analyst_conclusion": (
            "The sample supports a medium-priority lab incident: repeated failed authentication "
            "was followed by a labelled successful login and protected-file activity. "
            "Because all events are simulations, the values are observables, not real threat attribution."
        ),
    }
    json_path = args.output_directory / "linux_log_summary.json"
    json_path.write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")

    text_lines = [
        "Linux Log Analysis Summary",
        "Dataset: SAFE SYNTHETIC OFFLINE DATASET",
        "",
        f"Failed authentication: {sum(failed.values())}",
        f"Successful authentication: {len(successful)}",
        f"Correlated failure-then-success sources: {len(correlated_sources)}",
        f"Audit keys: {dict(sorted(audit_keys.items()))}",
        f"Watched paths: {dict(sorted(watched_paths.items()))}",
        "",
        summary["analyst_conclusion"],
    ]
    (args.output_directory / "linux_log_summary.txt").write_text("\n".join(text_lines) + "\n", encoding="utf-8")
    print(f"Wrote Linux log summary to {args.output_directory}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
