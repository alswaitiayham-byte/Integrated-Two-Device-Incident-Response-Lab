#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

ensure_project_dirs
failures=0

check() {
  local label=$1
  shift
  if "$@" >/dev/null 2>&1; then
    printf 'PASS  %s\n' "$label"
  else
    printf 'FAIL  %s\n' "$label"
    failures=$((failures + 1))
  fi
}

optional() {
  local label=$1
  shift
  if "$@" >/dev/null 2>&1; then
    printf 'READY %s\n' "$label"
  else
    printf 'OPTIONAL-NOT-RUN %s\n' "$label"
  fi
}

container_running() {
  local pattern=$1
  run_as_root docker ps --format '{{.Names}}' 2>/dev/null | grep -Eq "$pattern"
}

is_ubuntu() {
  # shellcheck disable=SC1091
  source /etc/os-release
  [[ ${ID:-} == ubuntu ]]
}

has_root_space() {
  local available_kb
  available_kb=$(df -Pk / | awk 'NR==2 {print $4}')
  (( available_kb >= 10 * 1024 * 1024 ))
}

ten_skills_verified() {
  [[ $(grep -c '^OK' "$OUTPUT_DIR/selected-skills-verification.txt" 2>/dev/null || true) -eq 10 ]]
}

status_file="$OUTPUT_DIR/project-status.txt"
{
  printf 'Project status - %s\n' "$(date --iso-8601=seconds)"
  printf 'Ubuntu IP: %s\n' "$(ubuntu_server_ip 2>/dev/null || printf 'not-detected')"
  printf 'Evidence root: %s\n\n' "$(evidence_target)"

  check 'Ubuntu operating system' is_ubuntu
  check 'At least 10 GiB root free' has_root_space
  check 'auditd service active' run_as_root systemctl is-active auditd
  check 'Velociraptor server active' run_as_root systemctl is-active velociraptor_server.service
  check 'Velociraptor frontend TCP 8000' nc -z 127.0.0.1 "$VELOCIRAPTOR_FRONTEND_PORT"
  check 'Velociraptor GUI TCP 8889' nc -z 127.0.0.1 "$VELOCIRAPTOR_GUI_PORT"
  check 'Ten skills verified' ten_skills_verified
  check 'Windows endpoint bundle created' test -s "$OUTPUT_DIR/windows-client/SHA256SUMS"
  check 'Volatility 3 installed' test -x "$TOOLS_DIR/volatility3-venv/bin/vol"
  optional 'Docker Engine' run_as_root docker info
  optional 'Splunk container' container_running '^ayham-ir-splunk$'
  optional 'Timesketch containers' container_running 'timesketch|opensearch|timesketch.*postgres'

  printf '\nVelociraptor GUI (Ubuntu only): https://127.0.0.1:%s/\n' "$VELOCIRAPTOR_GUI_PORT"
  printf 'Windows client connects to: https://%s:%s/\n' "$(ubuntu_server_ip 2>/dev/null || printf 'UNKNOWN')" "$VELOCIRAPTOR_FRONTEND_PORT"
} | tee "$status_file"

sha256sum "$status_file" > "$status_file.sha256"
if (( failures > 0 )); then
  die "$failures required project checks failed. Review $status_file"
fi
printf 'PROJECT STATUS: READY\n'
