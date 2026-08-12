#!/usr/bin/env bash
set -euo pipefail

BASE=${1:-}
if [[ -z "$BASE" ]]; then
  echo "Usage: $0 /new/or/empty/path/for/backup-demo" >&2
  exit 1
fi
case "$BASE" in
  /|/home|/root|"$HOME") echo "Refusing broad target: $BASE" >&2; exit 1 ;;
esac
if [[ -e "$BASE" ]] && [[ -n "$(find "$BASE" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null)" ]]; then
  echo "Target must be new or empty: $BASE" >&2
  exit 1
fi

SOURCE="$BASE/source"
BACKUPS="$BASE/backups"
RESTORE="$BASE/isolated_restore"
RESULTS="$BASE/results"
mkdir -p "$SOURCE/config" "$SOURCE/data" "$BACKUPS" "$RESTORE" "$RESULTS"

printf 'mode=production-simulation\nowner=IR-course-lab\n' > "$SOURCE/config/app.conf"
printf 'record_id,status\n1001,active\n1002,review\n' > "$SOURCE/data/records.csv"
printf 'SAFE-SIMULATION recovery token: IR-BACKUP-2026\n' > "$SOURCE/data/recovery-token.txt"

(
  cd "$SOURCE"
  find . -type f -print0 | sort -z | xargs -0 sha256sum > "$RESULTS/baseline_manifest.sha256"
)

tar -czf "$BACKUPS/clean-backup.tar.gz" -C "$SOURCE" .
sha256sum "$BACKUPS/clean-backup.tar.gz" > "$RESULTS/clean_archive.sha256"
tar -tzf "$BACKUPS/clean-backup.tar.gz" > "$RESULTS/clean_archive_contents.txt"

cp "$BACKUPS/clean-backup.tar.gz" "$BACKUPS/corrupted-backup.tar.gz"
printf 'SAFE_INTENTIONAL_TAMPER' >> "$BACKUPS/corrupted-backup.tar.gz"
sha256sum "$BACKUPS/corrupted-backup.tar.gz" > "$RESULTS/corrupted_archive.sha256"

clean_hash=$(awk '{print $1}' "$RESULTS/clean_archive.sha256")
corrupt_hash=$(awk '{print $1}' "$RESULTS/corrupted_archive.sha256")
if [[ "$clean_hash" == "$corrupt_hash" ]]; then
  echo "Tamper test failed: hashes unexpectedly match." >&2
  exit 1
fi
printf 'PASS: intentional corruption changed SHA-256.\n' > "$RESULTS/tamper_detection.txt"

tar -xzf "$BACKUPS/clean-backup.tar.gz" -C "$RESTORE"
(
  cd "$RESTORE"
  sha256sum -c "$RESULTS/baseline_manifest.sha256"
) > "$RESULTS/restore_hash_check.txt" 2>&1
grep -q 'IR-BACKUP-2026' "$RESTORE/data/recovery-token.txt"

cat > "$RESULTS/validation_summary.txt" <<EOF
Backup Integrity and Recovery Validation
UTC time: $(date -u --iso-8601=seconds)
Clean archive SHA-256: $clean_hash
Corrupted copy SHA-256: $corrupt_hash
Tamper detection: PASS
Clean archive listing: PASS
Isolated restore: PASS
Restored-file manifest: PASS
Recovery token validation: PASS
EOF

cat "$RESULTS/validation_summary.txt"
