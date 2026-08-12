#!/usr/bin/env python3
"""Extract observable IPs, domains, and SHA-256 hashes from lab evidence.

The script deliberately separates observation from maliciousness. Reserved
documentation addresses and lab values are labelled as simulations.
"""

from __future__ import annotations

import argparse
import csv
import ipaddress
import re
from datetime import datetime
from pathlib import Path

IP_RE = re.compile(r"(?<![\w.])(?:\d{1,3}\.){3}\d{1,3}(?![\w.])")
DOMAIN_RE = re.compile(
    r"(?<![A-Za-z0-9_-])(?:[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?\.)+"
    r"[A-Za-z]{2,63}(?![A-Za-z0-9_-])"
)
SHA256_RE = re.compile(r"(?<![A-Fa-f0-9])[A-Fa-f0-9]{64}(?![A-Fa-f0-9])")
ISO_RE = re.compile(r"\b(20\d{2}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:?\d{2})?)")
SYSLOG_RE = re.compile(r"^(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\s+(\d{1,2})\s+(\d{2}:\d{2}:\d{2})")

DOC_NETWORKS = [
    ipaddress.ip_network("192.0.2.0/24"),
    ipaddress.ip_network("198.51.100.0/24"),
    ipaddress.ip_network("203.0.113.0/24"),
]
SKIP_TLDS = {
    "log", "txt", "csv", "json", "jsonl", "raw", "img", "conf", "xml",
    "sh", "md", "vql", "yaml", "yml", "exe", "dll", "sys", "server",
}
TEXT_SUFFIXES = {".log", ".txt", ".csv", ".json", ".jsonl", ".conf", ".xml", ".vql", ".md", ".spl"}
MAX_SOURCE_REFERENCES = 50


def timestamp_from_line(line: str) -> str:
    match = ISO_RE.search(line)
    if match:
        value = match.group(1).replace("Z", "+00:00")
        try:
            return datetime.fromisoformat(value).isoformat()
        except ValueError:
            return match.group(1)
    match = SYSLOG_RE.search(line)
    if match:
        try:
            dt = datetime.strptime(f"2026 {match.group(1)} {match.group(2)} {match.group(3)} +0300", "%Y %b %d %H:%M:%S %z")
            return dt.isoformat()
        except ValueError:
            return ""
    return ""


def classify(kind: str, value: str) -> tuple[str, int, str]:
    if kind == "ipv4":
        address = ipaddress.ip_address(value)
        if any(address in network for network in DOC_NETWORKS):
            return "simulation-documentation", 100, "RFC 5737 address; never treat as a real attacker"
        if address.is_loopback or address.is_private or address.is_link_local:
            return "lab-internal", 90, "Internal or loopback observable; context required"
        return "needs-review", 60, "Public observable; validate ownership and source evidence"
    if kind == "domain":
        lowered = value.lower()
        if lowered.endswith((".example", ".test", ".invalid", ".localhost")):
            return "simulation-documentation", 100, "Reserved example/test domain"
        return "needs-review", 60, "Observed domain; enrichment and context required"
    return "lab-observable", 90, "Observed SHA-256; verify which file produced it"


def valid_domain(value: str) -> bool:
    lowered = value.lower().rstrip(".")
    if lowered.split(".")[-1] in SKIP_TLDS:
        return False
    if lowered in {"localhost.localdomain"}:
        return False
    return True


def collect(input_root: Path, output_file: Path) -> list[dict[str, str | int]]:
    records: dict[tuple[str, str], dict[str, str | int]] = {}
    for path in sorted(input_root.rglob("*")):
        if not path.is_file() or path.resolve() == output_file.resolve():
            continue
        if path.suffix.lower() not in TEXT_SUFFIXES:
            continue
        try:
            lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
        except OSError:
            continue
        for line_number, line in enumerate(lines, start=1):
            observed_at = timestamp_from_line(line)
            candidates: list[tuple[str, str]] = []
            for raw in IP_RE.findall(line):
                try:
                    ipaddress.ip_address(raw)
                except ValueError:
                    continue
                candidates.append(("ipv4", raw))
            for raw in DOMAIN_RE.findall(line):
                if valid_domain(raw):
                    candidates.append(("domain", raw.lower().rstrip(".")))
            for raw in SHA256_RE.findall(line):
                candidates.append(("sha256", raw.lower()))
            for kind, value in candidates:
                key = (kind, value)
                classification, confidence, note = classify(kind, value)
                source = f"{path.relative_to(input_root)}:{line_number}"
                if key not in records:
                    records[key] = {
                        "type": kind,
                        "value": value,
                        "first_seen": observed_at,
                        "source": source,
                        "classification": classification,
                        "confidence": confidence,
                        "analyst_note": note,
                    }
                else:
                    previous = str(records[key]["source"])
                    previous_sources = previous.split("; ")
                    if source not in previous_sources:
                        if len(previous_sources) < MAX_SOURCE_REFERENCES:
                            records[key]["source"] = f"{previous}; {source}"
                        elif not previous.endswith("additional occurrences omitted"):
                            records[key]["source"] = f"{previous}; additional occurrences omitted"
                    if not records[key]["first_seen"] and observed_at:
                        records[key]["first_seen"] = observed_at
    return sorted(records.values(), key=lambda row: (str(row["type"]), str(row["value"])))


def main() -> int:
    parser = argparse.ArgumentParser(description="Extract and classify IOCs/observables from lab evidence.")
    parser.add_argument("input_root", type=Path)
    parser.add_argument("output_csv", type=Path)
    args = parser.parse_args()
    if not args.input_root.is_dir():
        parser.error(f"Input directory not found: {args.input_root}")
    args.output_csv.parent.mkdir(parents=True, exist_ok=True)
    rows = collect(args.input_root, args.output_csv)
    fieldnames = ["type", "value", "first_seen", "source", "classification", "confidence", "analyst_note"]
    with args.output_csv.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)
    print(f"Wrote {len(rows)} reviewed-observable candidates to {args.output_csv}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
