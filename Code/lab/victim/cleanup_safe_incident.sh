#!/usr/bin/env bash
set -euo pipefail

if [[ ${EUID} -ne 0 ]]; then
  echo "Run with sudo." >&2
  exit 1
fi

LAB_ROOT=/opt/ir-lab
if [[ -f "$LAB_ROOT/http_server.pid" ]]; then
  pid=$(cat "$LAB_ROOT/http_server.pid")
  if [[ "$pid" =~ ^[0-9]+$ ]] && kill -0 "$pid" 2>/dev/null; then
    kill "$pid"
    echo "Stopped harmless HTTP process $pid."
  fi
  rm -f "$LAB_ROOT/http_server.pid"
fi

logger -p daemon.notice -t ir-lab "[SAFE-SIMULATION] cleanup completed"

if [[ "${IR_REMOVE_LAB_DATA:-NO}" == "YES" ]]; then
  if [[ "$LAB_ROOT" == "/opt/ir-lab" ]]; then
    find "$LAB_ROOT" -mindepth 1 -delete
    echo "Removed generated files under /opt/ir-lab. System audit logs were preserved."
  fi
else
  echo "Generated evidence was preserved under /opt/ir-lab."
fi
