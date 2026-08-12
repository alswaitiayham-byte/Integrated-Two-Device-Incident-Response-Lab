#!/usr/bin/env bash
set -euo pipefail

COMMON_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
PROJECT_ROOT=$(cd -- "$COMMON_DIR/.." && pwd)
# shellcheck source=../config/project.conf
source "$PROJECT_ROOT/config/project.conf"

TOOLS_DIR="$PROJECT_ROOT/.tools"
OUTPUT_DIR="$PROJECT_ROOT/output"
LOCAL_EVIDENCE_DIR="$PROJECT_ROOT/evidence"
EVIDENCE_ROOT="$EVIDENCE_MOUNT/$EVIDENCE_DIR_NAME"
RUN_LOG_DIR="$OUTPUT_DIR/logs"

export PROJECT_ROOT TOOLS_DIR OUTPUT_DIR LOCAL_EVIDENCE_DIR EVIDENCE_ROOT RUN_LOG_DIR

timestamp_utc() {
  date -u +%Y%m%dT%H%M%SZ
}

log() {
  printf '[%s] %s\n' "$(date --iso-8601=seconds)" "$*"
}

warn() {
  printf '[WARNING] %s\n' "$*" >&2
}

die() {
  printf '[ERROR] %s\n' "$*" >&2
  exit 1
}

ensure_project_dirs() {
  mkdir -p "$TOOLS_DIR" "$OUTPUT_DIR" "$RUN_LOG_DIR" "$LOCAL_EVIDENCE_DIR"
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "Required command is missing: $1"
}

require_ubuntu() {
  [[ -r /etc/os-release ]] || die "Cannot identify the operating system."
  # shellcheck disable=SC1091
  source /etc/os-release
  [[ ${ID:-} == ubuntu ]] || die "This automation is supported on Ubuntu only. Detected: ${ID:-unknown}"
}

ubuntu_server_ip() {
  ip -4 route get 1.1.1.1 2>/dev/null | awk '{
    for (i=1; i<=NF; i++) {
      if ($i == "src") { print $(i+1); exit }
    }
  }'
}

ubuntu_lan_cidr() {
  local device ip_addr
  device=$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{
    for (i=1; i<=NF; i++) {
      if ($i == "dev") { print $(i+1); exit }
    }
  }')
  [[ -n "$device" ]] || return 1
  ip_addr=$(ip -4 -o addr show dev "$device" scope global 2>/dev/null | awk 'NR==1 {print $4}')
  [[ -n "$ip_addr" ]] || return 1
  python3 - "$ip_addr" <<'PY'
import ipaddress
import sys

print(ipaddress.ip_interface(sys.argv[1]).network)
PY
}

evidence_target() {
  if mountpoint -q "$EVIDENCE_MOUNT" 2>/dev/null && [[ -w "$EVIDENCE_MOUNT" ]]; then
    mkdir -p "$EVIDENCE_ROOT"/{evidence,hashes,backups,exports,cases}
    printf '%s\n' "$EVIDENCE_ROOT"
  else
    mkdir -p "$LOCAL_EVIDENCE_DIR"/{evidence,hashes,backups,exports,cases}
    printf '%s\n' "$LOCAL_EVIDENCE_DIR"
  fi
}

sha256_verify() {
  local file=$1 expected=$2 actual
  [[ -f "$file" ]] || return 1
  actual=$(sha256sum "$file" | awk '{print $1}')
  [[ "$actual" == "$expected" ]]
}

download_verified() {
  local url=$1 destination=$2 expected_hash=$3
  local temporary
  require_command curl
  if sha256_verify "$destination" "$expected_hash"; then
    log "Verified cached download: $destination"
    return 0
  fi
  temporary=$(mktemp "${destination}.partial.XXXXXX")
  trap 'rm -f "$temporary"' RETURN
  log "Downloading $(basename "$destination")"
  curl -fL --retry 3 --connect-timeout 20 --output "$temporary" "$url"
  sha256_verify "$temporary" "$expected_hash" || die "SHA-256 verification failed for $url"
  chmod 0755 "$temporary"
  mv -f "$temporary" "$destination"
  trap - RETURN
  log "SHA-256 verified: $destination"
}

record_runtime_baseline() {
  local destination=$1
  mkdir -p "$(dirname "$destination")"
  {
    printf 'Project: %s\nStudent: %s (%s)\nUTC: %s\n\n' \
      "$PROJECT_TITLE" "$STUDENT_NAME" "$STUDENT_ID" "$(date -u --iso-8601=seconds)"
    hostnamectl 2>/dev/null || hostname
    printf '\nOS release\n'
    sed -n '1,30p' /etc/os-release
    printf '\nKernel\n'
    uname -a
    printf '\nClock\n'
    timedatectl 2>/dev/null || true
    printf '\nNetwork (global addresses)\n'
    ip -4 -br address show scope global
    printf '\nRoutes\n'
    ip -4 route
    printf '\nMemory\n'
    free -h
    printf '\nStorage\n'
    df -hT
    printf '\nEvidence mount\n'
    findmnt "$EVIDENCE_MOUNT" 2>/dev/null || true
  } > "$destination"
}

run_as_root() {
  if [[ ${EUID} -eq 0 ]]; then
    "$@"
  else
    sudo "$@"
  fi
}
