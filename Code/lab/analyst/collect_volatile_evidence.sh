#!/usr/bin/env bash
set -euo pipefail

OUTPUT_ROOT=${1:-./volatile_evidence}
CASE_ID=${CASE_ID:-IR-COURSE-LAB}
OPERATOR=${OPERATOR:-Ayham_Al-Swaiti}
RUN_ID=$(date -u +%Y%m%dT%H%M%SZ)
OUTPUT_DIR="$OUTPUT_ROOT/${CASE_ID}_${RUN_ID}"
mkdir -p "$OUTPUT_DIR"

capture() {
  local filename=$1
  shift
  {
    printf 'Case ID: %s\nOperator: %s\nHost: %s\nUTC collection time: %s\n' \
      "$CASE_ID" "$OPERATOR" "$(hostname)" "$(date -u --iso-8601=seconds)"
    printf 'Command:'
    printf ' %q' "$@"
    printf '\n\n'
    "$@"
  } > "$OUTPUT_DIR/$filename" 2>&1 || true
}

capture system_identity.txt sh -c 'hostnamectl 2>/dev/null || hostname; uname -a; uptime'
capture date_and_clock.txt sh -c 'date --iso-8601=seconds; date -u --iso-8601=seconds; timedatectl 2>/dev/null || true'
capture logged_in_users.txt sh -c 'who -a; w; last -n 40 2>/dev/null || true'
capture processes.txt ps auxwwf
if command -v pstree >/dev/null 2>&1; then capture process_tree.txt pstree -ap; fi
if command -v ss >/dev/null 2>&1; then capture network_connections.txt ss -plantue; else capture network_connections.txt netstat -plantue; fi
capture interfaces_and_routes.txt sh -c 'ip -details address; ip route; ip neigh'
if command -v lsof >/dev/null 2>&1; then capture open_files.txt lsof -nP; fi
capture mounts.txt sh -c 'mount; findmnt 2>/dev/null || true; df -hT'
capture kernel_modules.txt sh -c 'lsmod 2>/dev/null || true'
capture running_services.txt sh -c 'systemctl --no-pager --type=service --state=running 2>/dev/null || service --status-all 2>/dev/null || true'
capture scheduled_tasks.txt sh -c 'crontab -l 2>/dev/null || true; find /etc/cron* -maxdepth 2 -type f -ls 2>/dev/null || true'
capture recent_lab_files.txt sh -c 'find /opt/ir-lab -xdev -type f -printf "%TY-%Tm-%TdT%TH:%TM:%TS %m %u:%g %s %p\n" 2>/dev/null | sort || true'
if command -v journalctl >/dev/null 2>&1; then capture recent_journal.txt journalctl --since '2 hours ago' --no-pager; fi
if command -v auditctl >/dev/null 2>&1; then capture loaded_audit_rules.txt auditctl -l; fi

cat > "$OUTPUT_DIR/chain_of_custody.txt" <<EOF
Case ID: $CASE_ID
Evidence type: Live volatile host collection
Source host: $(hostname)
Operator: $OPERATOR
Collection started (UTC): $RUN_ID
Collection completed (UTC): $(date -u +%Y%m%dT%H%M%SZ)
Collection method: Included read-only Linux commands
Original location: $OUTPUT_DIR
Handling note: Copy to dedicated evidence storage and verify SHA-256 before analysis.
EOF

(
  cd "$OUTPUT_DIR"
  manifest_tmp=$(mktemp)
  find . -maxdepth 1 -type f ! -name collection_manifest.sha256 -print0 \
    | sort -z | xargs -0 sha256sum > "$manifest_tmp"
  mv "$manifest_tmp" collection_manifest.sha256
)

echo "Volatile evidence saved to $OUTPUT_DIR"
echo "Manifest: $OUTPUT_DIR/collection_manifest.sha256"
