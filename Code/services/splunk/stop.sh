#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=../../lib/common.sh
source "$SCRIPT_DIR/../../lib/common.sh"
require_command docker
run_as_root docker compose -f "$SCRIPT_DIR/docker-compose.yml" stop
printf 'Splunk stopped. Persistent project volumes were preserved.\n'
