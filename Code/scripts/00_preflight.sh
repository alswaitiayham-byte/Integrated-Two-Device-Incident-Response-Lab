#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

ensure_project_dirs
require_ubuntu
require_command ip
require_command df
require_command findmnt

package_audit=$(run_as_root dpkg --audit)
[[ -z "$package_audit" ]] || die "dpkg reports incomplete package state:\n$package_audit"
run_as_root apt-get check >/dev/null

server_ip=$(ubuntu_server_ip)
[[ -n "$server_ip" ]] || die "Could not determine the Ubuntu LAN IP. Connect Ubuntu to the LAN and retry."

available_kb=$(df -Pk / | awk 'NR==2 {print $4}')
(( available_kb >= 10 * 1024 * 1024 )) || die "At least 10 GiB free is required on /."

memory_kb=$(awk '/MemTotal/ {print $2}' /proc/meminfo)
(( memory_kb >= 7 * 1024 * 1024 )) || die "At least 8 GiB RAM is required."

evidence_mode="local fallback"
if mountpoint -q "$EVIDENCE_MOUNT" 2>/dev/null; then
  [[ -w "$EVIDENCE_MOUNT" ]] || die "$EVIDENCE_MOUNT is mounted but is not writable by $(id -un)."
  evidence_mode="dedicated mount"
else
  warn "$EVIDENCE_MOUNT is not mounted. Setup can continue, but evidence will use the project folder."
fi

baseline="$OUTPUT_DIR/ubuntu-preflight-$(timestamp_utc).txt"
record_runtime_baseline "$baseline"
sha256sum "$baseline" > "$baseline.sha256"

printf 'Ubuntu IP: %s\n' "$server_ip"
printf 'LAN CIDR: %s\n' "$(ubuntu_lan_cidr 2>/dev/null || printf 'not-detected')"
printf 'RAM: %s GiB\n' "$((memory_kb / 1024 / 1024))"
printf 'Free root storage: %s GiB\n' "$((available_kb / 1024 / 1024))"
printf 'Evidence mode: %s\n' "$evidence_mode"
printf 'Package database: healthy\n'
printf 'Baseline: %s\n' "$baseline"
printf 'PREFLIGHT RESULT: PASS\n'
