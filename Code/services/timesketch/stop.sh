#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=../../lib/common.sh
source "$SCRIPT_DIR/../../lib/common.sh"

if [[ ! -d /opt/timesketch ]]; then
  printf 'Timesketch is not installed at /opt/timesketch.\n'
  exit 0
fi
(cd /opt/timesketch && run_as_root docker compose stop)
printf 'Timesketch stopped. Persistent data was preserved.\n'
