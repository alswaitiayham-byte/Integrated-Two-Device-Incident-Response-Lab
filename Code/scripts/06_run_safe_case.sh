#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

ensure_project_dirs
require_ubuntu

run_id=$(timestamp_utc)
evidence_base=$(evidence_target)
case_root="$evidence_base/cases/${CASE_ID}_${run_id}"
raw_dir="$case_root/01-raw"
analysis_dir="$case_root/02-analysis"
response_dir="$case_root/03-response"
recovery_dir="$case_root/04-recovery"
mkdir -p "$raw_dir" "$analysis_dir" "$response_dir" "$recovery_dir"

containment_enabled=0
cleanup_on_exit() {
  if (( containment_enabled == 1 )); then
    run_as_root bash "$PROJECT_ROOT/lab/analyst/contain_host.sh" release >/dev/null 2>&1 || true
  fi
  run_as_root bash "$PROJECT_ROOT/lab/victim/cleanup_safe_incident.sh" >/dev/null 2>&1 || true
}
trap cleanup_on_exit EXIT

log "Starting a labelled, non-malicious incident simulation."
run_as_root env IR_LAB_CONFIRM=YES bash "$PROJECT_ROOT/lab/victim/generate_safe_incident.sh" \
  | tee "$raw_dir/simulation-console.txt"

run_as_root env CASE_ID="$CASE_ID" OPERATOR="$OPERATOR_NAME" \
  bash "$PROJECT_ROOT/lab/analyst/collect_volatile_evidence.sh" "$raw_dir/volatile"
run_as_root bash "$PROJECT_ROOT/lab/analyst/analyze_audit.sh" "$raw_dir/audit"

run_as_root cp --preserve=timestamps /var/log/ir-lab-simulation.log "$raw_dir/ir-lab-simulation.log"
if run_as_root test -r /var/log/audit/audit.log; then
  run_as_root cp --preserve=timestamps /var/log/audit/audit.log "$raw_dir/audit.log"
fi

log "Applying narrow IOC-only containment rules. Internet and LAN connectivity remain available."
run_as_root bash "$PROJECT_ROOT/lab/analyst/contain_host.sh" contain \
  | tee "$response_dir/containment-enabled.txt"
containment_enabled=1
run_as_root bash "$PROJECT_ROOT/lab/analyst/contain_host.sh" status \
  > "$response_dir/containment-status.txt"
run_as_root bash "$PROJECT_ROOT/lab/analyst/contain_host.sh" release \
  | tee "$response_dir/containment-released.txt"
containment_enabled=0

if [[ ${EUID} -ne 0 ]]; then
  run_as_root chown -R "$(id -u):$(id -g)" "$case_root"
fi

python3 "$PROJECT_ROOT/lab/analyst/summarize_linux_logs.py" "$raw_dir" "$analysis_dir/linux-logs"
python3 "$PROJECT_ROOT/lab/ioc/extract_iocs.py" "$raw_dir" "$analysis_dir/ioc-register.csv"
python3 "$PROJECT_ROOT/lab/ioc/generate_stix.py" \
  "$analysis_dir/ioc-register.csv" "$analysis_dir/ioc-bundle.stix.json"
python3 "$PROJECT_ROOT/lab/timesketch/build_timeline.py" \
  "$case_root" "$analysis_dir/timesketch-timeline.csv"

bash "$PROJECT_ROOT/lab/disk/create_forensic_lab.sh" "$analysis_dir/disk-lab"
bash "$PROJECT_ROOT/lab/disk/analyze_forensic_image.sh" \
  "$analysis_dir/disk-lab/evidence/disk-image.dd" "$analysis_dir/disk-analysis"
bash "$PROJECT_ROOT/lab/backup/validate_backup.sh" "$recovery_dir/backup-validation"

run_as_root bash "$PROJECT_ROOT/lab/victim/cleanup_safe_incident.sh" \
  | tee "$response_dir/simulation-cleanup.txt"

cat > "$case_root/CASE_SUMMARY.txt" <<EOF
Two-Device Incident Response Course Project
Case ID: $CASE_ID
Student: $STUDENT_NAME ($STUDENT_ID)
Run ID: $run_id
Ubuntu host: $(hostname)
Ubuntu IP: $(ubuntu_server_ip)
Scenario: labelled safe authentication/file/process/IOC simulation
Real exploitation or malware: NONE
Volatile evidence: COLLECTED
Linux audit analysis: COMPLETED
IOC register and STIX 2.1: GENERATED
Targeted containment: APPLIED, VERIFIED, RELEASED
Forensic disk image and deleted-file recovery: COMPLETED
Timesketch-compatible timeline: GENERATED
Backup tamper detection and isolated restore: COMPLETED
Windows evidence: run the included Windows scripts and copy their output into this case.
EOF

(
  cd "$case_root"
  manifest_tmp=$(mktemp)
  find . -type f ! -name CASE_MANIFEST.sha256 -print0 \
    | sort -z | xargs -0 sha256sum > "$manifest_tmp"
  mv "$manifest_tmp" CASE_MANIFEST.sha256
  sha256sum -c CASE_MANIFEST.sha256 > CASE_MANIFEST_VERIFICATION.txt
)
printf '%s\n' "$case_root" > "$OUTPUT_DIR/latest-case-path.txt"
printf 'SAFE CASE RESULT: PASS\nCase directory: %s\n' "$case_root"
trap - EXIT
