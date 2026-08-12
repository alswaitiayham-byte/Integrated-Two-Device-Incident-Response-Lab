#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

ensure_project_dirs
require_command zip
evidence_base=$(evidence_target)
run_id=$(timestamp_utc)
manifest="$evidence_base/EVIDENCE_MANIFEST_${run_id}.sha256"
summary="$OUTPUT_DIR/FINAL_TECHNICAL_SUMMARY_${run_id}.md"
export_zip="$OUTPUT_DIR/SUBMISSION_EVIDENCE_${run_id}.zip"

(
  cd "$evidence_base"
  find . -type f \
    ! -name 'EVIDENCE_MANIFEST_*.sha256' \
    ! -name '*.raw' \
    ! -name '*.mem' \
    ! -name '*.dmp' \
    -print0 | sort -z | xargs -0 sha256sum > "$manifest"
)

latest_case="not run"
if [[ -r "$OUTPUT_DIR/latest-case-path.txt" ]]; then
  latest_case=$(<"$OUTPUT_DIR/latest-case-path.txt")
fi

cat > "$summary" <<EOF
# Final Technical Summary

- Project: $PROJECT_TITLE
- Student: $STUDENT_NAME ($STUDENT_ID)
- Domain: Incident Response
- Topology: Ubuntu analyst/server + authorized Windows 11 endpoint
- Finalized (UTC): $(date -u --iso-8601=seconds)
- Latest safe case: $latest_case
- Evidence root: $evidence_base
- Evidence manifest: $manifest

## Integrity

All normal-sized evidence files are listed in the SHA-256 manifest. Memory images
are deliberately excluded from the submission ZIP because they may contain private
data and can exceed several gigabytes; their separate acquisition hash must remain
beside the original image.

## Claim boundary

The automated Ubuntu case is a labelled safe simulation. Velociraptor, Splunk,
Timesketch, Windows collection, and Volatility results may only be described as
live results after their corresponding output or screenshot is actually captured.
EOF

(
  cd "$PROJECT_ROOT"
  zip -qr "$export_zip" \
    docs config lab/velociraptor lab/splunk output \
    -x 'output/windows-client/client.config.yaml' \
       'output/windows-client/*.exe' \
       'output/*.zip' \
       'output/logs/*' \
       '*/__pycache__/*' \
       '*.pyc'
)
sha256sum "$export_zip" > "$export_zip.sha256"

printf 'Evidence manifest: %s\n' "$manifest"
printf 'Technical summary: %s\n' "$summary"
printf 'Submission evidence ZIP: %s\n' "$export_zip"
printf 'FINALIZATION RESULT: PASS\n'
