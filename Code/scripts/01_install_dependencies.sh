#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

require_ubuntu
ensure_project_dirs

packages=(
  auditd
  audispd-plugins
  ca-certificates
  curl
  e2fsprogs
  git
  gnupg
  jq
  lsof
  netcat-openbsd
  nftables
  python3
  python3-pip
  python3-venv
  rsync
  sleuthkit
  unzip
  zip
)

log "Refreshing Ubuntu package metadata"
run_as_root apt-get update
log "Installing defensive/forensic dependencies"
run_as_root env DEBIAN_FRONTEND=noninteractive apt-get install -y "${packages[@]}"

if ! command -v docker >/dev/null 2>&1; then
  warn "Docker is not installed. Base IR setup will continue; optional Splunk/Timesketch will require Docker Engine."
else
  docker --version
  docker compose version
fi

vol_venv="$TOOLS_DIR/volatility3-venv"
if [[ ! -x "$vol_venv/bin/vol" ]]; then
  python3 -m venv "$vol_venv"
  "$vol_venv/bin/python" -m pip install --disable-pip-version-check --upgrade pip
  "$vol_venv/bin/python" -m pip install --disable-pip-version-check "volatility3==$VOLATILITY3_VERSION"
fi
"$vol_venv/bin/vol" --help >/dev/null
"$vol_venv/bin/python" -c 'import importlib.metadata; print("Volatility 3", importlib.metadata.version("volatility3"))'

printf 'Dependency installation: PASS\n'
