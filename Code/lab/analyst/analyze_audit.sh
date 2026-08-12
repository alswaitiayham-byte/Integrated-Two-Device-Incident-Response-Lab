#!/usr/bin/env bash
set -euo pipefail

OUTPUT_ROOT=${1:-./audit_analysis}
RUN_ID=$(date -u +%Y%m%dT%H%M%SZ)
OUTPUT_DIR="$OUTPUT_ROOT/$RUN_ID"
mkdir -p "$OUTPUT_DIR"

run_capture() {
  local file=$1
  shift
  {
    printf 'Command:'
    printf ' %q' "$@"
    printf '\nCollected: %s\n\n' "$(date --iso-8601=seconds)"
    "$@"
  } > "$OUTPUT_DIR/$file" 2>&1 || true
}

if command -v ausearch >/dev/null 2>&1; then
  run_capture ir_sensitive.txt ausearch -k ir_sensitive -i
  run_capture ir_evidence.txt ausearch -k ir_evidence -i
  run_capture identity_changes.txt ausearch -k identity_changes -i
  run_capture privileged_exec.txt ausearch -k privileged_exec -i
else
  printf 'ausearch is not installed.\n' > "$OUTPUT_DIR/ausearch_missing.txt"
fi

if command -v aureport >/dev/null 2>&1; then
  run_capture audit_summary.txt aureport --summary -i
  run_capture auth_summary.txt aureport --auth -i
  run_capture executable_summary.txt aureport --executable -i
fi

if [[ -r /var/log/ir-lab-simulation.log ]]; then
  cp --preserve=timestamps /var/log/ir-lab-simulation.log "$OUTPUT_DIR/"
fi
if [[ -r /var/log/auth.log ]]; then
  grep -E 'SAFE-SIMULATION|Failed password|Accepted password' /var/log/auth.log \
    > "$OUTPUT_DIR/auth_relevant.log" || true
elif command -v journalctl >/dev/null 2>&1; then
  journalctl --since '2 hours ago' -t sshd > "$OUTPUT_DIR/auth_relevant.log" || true
fi

(
  cd "$OUTPUT_DIR"
  manifest_tmp=$(mktemp)
  find . -maxdepth 1 -type f ! -name collection_manifest.sha256 -print0 \
    | sort -z | xargs -0 sha256sum > "$manifest_tmp"
  mv "$manifest_tmp" collection_manifest.sha256
)

echo "Audit analysis saved to $OUTPUT_DIR"
echo "Review the raw records before accepting any automated interpretation."
