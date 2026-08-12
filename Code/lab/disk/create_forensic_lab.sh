#!/usr/bin/env bash
set -euo pipefail

BASE=${1:-}
if [[ -z "$BASE" ]]; then
  echo "Usage: $0 /new/path/for/ir-disk-lab" >&2
  exit 1
fi
case "$BASE" in
  /|/home|/root|"$HOME") echo "Refusing broad target: $BASE" >&2; exit 1 ;;
esac
if [[ -e "$BASE" ]] && [[ -n "$(find "$BASE" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null)" ]]; then
  echo "Target must be new or empty: $BASE" >&2
  exit 1
fi
for tool in dd mkfs.ext2 debugfs sha256sum; do
  command -v "$tool" >/dev/null 2>&1 || { echo "Missing required tool: $tool" >&2; exit 1; }
done

mkdir -p "$BASE/source_files" "$BASE/evidence"
SOURCE_IMAGE="$BASE/lab-source.img"
EVIDENCE_IMAGE="$BASE/evidence/disk-image.dd"

printf 'Quarterly planning notes - harmless IR lab file.\n' > "$BASE/source_files/normal.txt"
printf 'SAFE-SIMULATION deleted evidence token: IR-DELETED-2026\n' > "$BASE/source_files/deleted-secret.txt"
printf '198.51.100.77 and 203.0.113.50 are documentation-only addresses.\n' > "$BASE/source_files/ioc-note.txt"
sha256sum "$BASE/source_files/deleted-secret.txt" > "$BASE/evidence/deleted_file_original.sha256"

dd if=/dev/zero of="$SOURCE_IMAGE" bs=1M count=64 status=none
mkfs.ext2 -F -L IR_FORENSIC_LAB "$SOURCE_IMAGE" >/dev/null
debugfs -w -R 'mkdir /evidence' "$SOURCE_IMAGE" >/dev/null 2>&1
debugfs -w -R "write $BASE/source_files/normal.txt /evidence/normal.txt" "$SOURCE_IMAGE" >/dev/null 2>&1
debugfs -w -R "write $BASE/source_files/deleted-secret.txt /evidence/deleted-secret.txt" "$SOURCE_IMAGE" >/dev/null 2>&1
debugfs -w -R "write $BASE/source_files/ioc-note.txt /evidence/ioc-note.txt" "$SOURCE_IMAGE" >/dev/null 2>&1
debugfs -w -R 'rm /evidence/deleted-secret.txt' "$SOURCE_IMAGE" >/dev/null 2>&1

sha256sum "$SOURCE_IMAGE" > "$BASE/evidence/source_image.sha256"
dd if="$SOURCE_IMAGE" of="$EVIDENCE_IMAGE" bs=4M conv=noerror,sync status=none
sha256sum "$EVIDENCE_IMAGE" > "$BASE/evidence/evidence_image.sha256"

source_hash=$(awk '{print $1}' "$BASE/evidence/source_image.sha256")
evidence_hash=$(awk '{print $1}' "$BASE/evidence/evidence_image.sha256")
if [[ "$source_hash" != "$evidence_hash" ]]; then
  echo "Imaging verification failed: hashes differ." >&2
  exit 1
fi

cat > "$BASE/evidence/chain_of_custody.txt" <<EOF
Case ID: IR-DISK-LAB
Evidence: 64 MiB ext2 lab image
Acquisition method: dd bs=4M conv=noerror,sync
Source SHA-256: $source_hash
Image SHA-256: $evidence_hash
Acquired (UTC): $(date -u --iso-8601=seconds)
Purpose: Safe deleted-file recovery demonstration
EOF

echo "Forensic image created and verified: $EVIDENCE_IMAGE"
