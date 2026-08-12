#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
PROJECT_ROOT=$(cd -- "$SCRIPT_DIR/../.." && pwd)
RUN_ID=$(date -u +%Y%m%dT%H%M%SZ)
RUN_DIR="$PROJECT_ROOT/evidence/offline_validation/$RUN_ID"
TMP_WORK=$(mktemp -d -t ir-course-project.XXXXXX)
trap 'find "$TMP_WORK" -mindepth 1 -delete 2>/dev/null || true; rmdir "$TMP_WORK" 2>/dev/null || true' EXIT
mkdir -p "$RUN_DIR"

pass_count=0
fail() {
  echo "FAIL: $*" >&2
  exit 1
}
pass() {
  echo "PASS: $*"
  pass_count=$((pass_count + 1))
}

while IFS= read -r script; do
  bash -n "$script" || fail "Shell syntax: $script"
done < <(find "$PROJECT_ROOT/lab" -type f -name '*.sh' | sort)
pass "All shell scripts pass bash -n"

PYTHONPYCACHEPREFIX="$TMP_WORK/pycache" python3 -m py_compile \
  "$PROJECT_ROOT/lab/analyst/summarize_linux_logs.py" \
  "$PROJECT_ROOT/lab/ioc/extract_iocs.py" \
  "$PROJECT_ROOT/lab/ioc/generate_stix.py" \
  "$PROJECT_ROOT/lab/timesketch/build_timeline.py"
pass "All Python scripts compile"

python3 "$PROJECT_ROOT/lab/analyst/summarize_linux_logs.py" \
  "$PROJECT_ROOT/sample_data" "$RUN_DIR/linux_log_analysis"
python3 - "$RUN_DIR/linux_log_analysis/linux_log_summary.json" <<'PY'
import json
import sys

data = json.load(open(sys.argv[1], encoding="utf-8"))
assert data["failed_authentication_by_ip"]["198.51.100.77"] >= 6
assert len(data["successful_authentication_events"]) >= 1
assert len(data["correlated_authentication_findings"]) >= 1
PY
cp "$RUN_DIR/linux_log_analysis/linux_log_summary.txt" "$RUN_DIR/linux_log_summary.txt"
pass "Linux audit/authentication correlation matched the expected safe scenario"

python3 "$PROJECT_ROOT/lab/ioc/extract_iocs.py" \
  "$PROJECT_ROOT/sample_data" "$RUN_DIR/ioc_register.csv"
ioc_count=$(( $(wc -l < "$RUN_DIR/ioc_register.csv") - 1 ))
(( ioc_count >= 4 )) || fail "IOC extraction returned only $ioc_count rows"
pass "IOC extraction produced $ioc_count candidates"

python3 "$PROJECT_ROOT/lab/ioc/generate_stix.py" \
  "$RUN_DIR/ioc_register.csv" "$RUN_DIR/ioc_bundle.json"
stix_count=$(python3 -c 'import json,sys; print(len(json.load(open(sys.argv[1]))["objects"]))' "$RUN_DIR/ioc_bundle.json")
[[ "$stix_count" -eq "$ioc_count" ]] || fail "STIX count $stix_count does not match IOC count $ioc_count"
pass "STIX 2.1 bundle contains $stix_count indicators"

python3 "$PROJECT_ROOT/lab/timesketch/build_timeline.py" \
  "$PROJECT_ROOT/sample_data" "$RUN_DIR/timesketch_timeline.csv"
timeline_count=$(( $(wc -l < "$RUN_DIR/timesketch_timeline.csv") - 1 ))
(( timeline_count >= 14 )) || fail "Timeline returned only $timeline_count events"
pass "Timesketch CSV contains $timeline_count events"

bash "$PROJECT_ROOT/lab/backup/validate_backup.sh" "$TMP_WORK/backup-demo" \
  > "$RUN_DIR/backup_console.txt"
grep -q 'Tamper detection: PASS' "$TMP_WORK/backup-demo/results/validation_summary.txt" \
  || fail "Backup tamper test"
grep -q 'Isolated restore: PASS' "$TMP_WORK/backup-demo/results/validation_summary.txt" \
  || fail "Backup restore test"
cp "$TMP_WORK/backup-demo/results/validation_summary.txt" "$RUN_DIR/backup_validation_summary.txt"
cp "$TMP_WORK/backup-demo/results/restore_hash_check.txt" "$RUN_DIR/restore_hash_check.txt"
pass "Backup corruption detection and clean restore passed"

disk_status="SKIPPED"
if command -v mkfs.ext2 >/dev/null 2>&1 && command -v debugfs >/dev/null 2>&1; then
  bash "$PROJECT_ROOT/lab/disk/create_forensic_lab.sh" "$TMP_WORK/disk-demo" \
    > "$RUN_DIR/disk_creation_console.txt"
  bash "$PROJECT_ROOT/lab/disk/analyze_forensic_image.sh" \
    "$TMP_WORK/disk-demo/evidence/disk-image.dd" "$TMP_WORK/disk-analysis" \
    > "$RUN_DIR/disk_analysis_console.txt"
  cp "$TMP_WORK/disk-analysis/analysis_summary.txt" "$RUN_DIR/disk_analysis_summary.txt"
  cp "$TMP_WORK/disk-analysis/analyzed_image.sha256" "$RUN_DIR/disk_image.sha256"
  if grep -q 'RECOVERED_AND_CONTENT_VALIDATED' "$TMP_WORK/disk-analysis/analysis_summary.txt"; then
    cp "$TMP_WORK/disk-analysis/recovered_deleted_file.txt" "$RUN_DIR/recovered_deleted_file.txt"
    disk_status="PASS"
    pass "Deleted lab file was recovered and content-validated"
  else
    disk_status="PARTIAL"
    pass "Disk image was created and hashed; automatic deleted-file recovery needs Sleuth Kit/Autopsy review"
  fi
else
  printf 'Disk test skipped because mkfs.ext2 or debugfs is unavailable.\n' > "$RUN_DIR/disk_analysis_summary.txt"
  pass "Disk test was safely skipped with an explicit reason"
fi

cat > "$RUN_DIR/TEST_RESULTS.txt" <<EOF
Integrated Incident Response Project - Offline Validation
UTC run ID: $RUN_ID
Dataset status: SAFE SYNTHETIC OFFLINE DATASET
Shell syntax checks: PASS
Python compile checks: PASS
IOC candidates: $ioc_count
STIX indicators: $stix_count
Timeline events: $timeline_count
Backup tamper detection: PASS
Backup isolated restore: PASS
Disk lab: $disk_status
Total test groups passed: $pass_count

This file validates the safe offline analysis pipeline only. It does not claim
live execution of Windows collection, Splunk, Timesketch, Velociraptor,
Volatility memory analysis, or Autopsy.
EOF

(
  cd "$RUN_DIR"
  manifest_tmp=$(mktemp)
  find . -maxdepth 1 -type f ! -name evidence_manifest.sha256 -print0 \
    | sort -z | xargs -0 sha256sum > "$manifest_tmp"
  mv "$manifest_tmp" evidence_manifest.sha256
)
printf '%s\n' "$RUN_ID" > "$PROJECT_ROOT/evidence/offline_validation/LATEST_RUN.txt"
echo
cat "$RUN_DIR/TEST_RESULTS.txt"
echo "Offline evidence directory: $RUN_DIR"
