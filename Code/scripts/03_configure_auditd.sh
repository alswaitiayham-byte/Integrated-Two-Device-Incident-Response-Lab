#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

require_ubuntu
run_as_root env IR_AUTHORIZED_HOST=YES bash "$PROJECT_ROOT/lab/victim/setup_auditd.sh"

verification="$OUTPUT_DIR/auditd-verification.txt"
run_as_root bash -c 'printf "Audit service\n"; auditctl -s; printf "\nProject rules\n"; auditctl -l | grep -E "ir_sensitive|ir_evidence|identity_changes|privileged_exec"' \
  | tee "$verification"

for key in ir_sensitive ir_evidence identity_changes privileged_exec; do
  grep -q "$key" "$verification" || die "auditd rule is missing: $key"
done
sha256sum "$verification" > "$verification.sha256"
printf 'AUDITD CONFIGURATION RESULT: PASS\n'
