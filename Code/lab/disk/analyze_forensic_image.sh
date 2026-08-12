#!/usr/bin/env bash
set -euo pipefail

IMAGE=${1:-}
OUTPUT_DIR=${2:-./disk_analysis}
if [[ -z "$IMAGE" || ! -f "$IMAGE" ]]; then
  echo "Usage: $0 /path/to/disk-image.dd [analysis-directory]" >&2
  exit 1
fi
mkdir -p "$OUTPUT_DIR"

sha256sum "$IMAGE" > "$OUTPUT_DIR/analyzed_image.sha256"
stat "$IMAGE" > "$OUTPUT_DIR/analyzed_image.stat"

if command -v fsstat >/dev/null 2>&1; then
  fsstat "$IMAGE" > "$OUTPUT_DIR/fsstat.txt" 2>&1 || true
fi
if command -v fls >/dev/null 2>&1; then
  fls -r -p "$IMAGE" > "$OUTPUT_DIR/fls_all_files.txt" 2>&1 || true
  fls -r -d -p "$IMAGE" > "$OUTPUT_DIR/fls_deleted_files.txt" 2>&1 || true
fi

if command -v debugfs >/dev/null 2>&1; then
  debugfs -R 'ls -l -p /evidence' "$IMAGE" > "$OUTPUT_DIR/debugfs_directory.txt" 2>&1 || true
  debugfs -R 'lsdel' "$IMAGE" > "$OUTPUT_DIR/debugfs_deleted_inodes.txt" 2>&1 || true
  deleted_inode=$(awk '/^[[:space:]]*[0-9]+[[:space:]]/ {print $1; exit}' "$OUTPUT_DIR/debugfs_deleted_inodes.txt" || true)
  if [[ "$deleted_inode" =~ ^[0-9]+$ ]]; then
    debugfs -R "dump <${deleted_inode}> $OUTPUT_DIR/recovered_deleted_file.txt" "$IMAGE" \
      > "$OUTPUT_DIR/debugfs_recovery.txt" 2>&1 || true
  fi
fi

result="NOT_RECOVERED"
if [[ -f "$OUTPUT_DIR/recovered_deleted_file.txt" ]]; then
  sha256sum "$OUTPUT_DIR/recovered_deleted_file.txt" > "$OUTPUT_DIR/recovered_deleted_file.sha256"
  if grep -q 'IR-DELETED-2026' "$OUTPUT_DIR/recovered_deleted_file.txt"; then
    result="RECOVERED_AND_CONTENT_VALIDATED"
  else
    result="RECOVERED_BUT_CONTENT_NOT_VALIDATED"
  fi
fi

cat > "$OUTPUT_DIR/analysis_summary.txt" <<EOF
Disk Forensics Analysis Summary
Image: $IMAGE
UTC analysis time: $(date -u --iso-8601=seconds)
Image SHA-256: $(awk '{print $1}' "$OUTPUT_DIR/analyzed_image.sha256")
Deleted-file result: $result
Autopsy step: Add the image as Raw Single / Disk Image or VM File and enable integrity, file-type, keyword, and recent-activity modules.
EOF

(
  cd "$OUTPUT_DIR"
  manifest_tmp=$(mktemp)
  find . -maxdepth 1 -type f ! -name analysis_manifest.sha256 -print0 \
    | sort -z | xargs -0 sha256sum > "$manifest_tmp"
  mv "$manifest_tmp" analysis_manifest.sha256
)
cat "$OUTPUT_DIR/analysis_summary.txt"
