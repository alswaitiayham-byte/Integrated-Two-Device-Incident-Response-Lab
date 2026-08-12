#!/usr/bin/env bash
set -euo pipefail

if [[ ${EUID} -ne 0 ]]; then
  echo "Run this script with sudo on the authorized Ubuntu lab host." >&2
  exit 1
fi

if [[ "${IR_LAB_CONFIRM:-}" != "YES" ]]; then
  echo "SAFE INCIDENT SIMULATION"
  echo "This script writes only under /opt/ir-lab, creates labelled local log events,"
  echo "and starts a harmless localhost HTTP service. It performs no exploitation."
  read -r -p "Type YES to confirm this is your authorized course-lab host: " answer
  [[ "$answer" == "YES" ]] || { echo "Cancelled."; exit 1; }
fi

LAB_ROOT=/opt/ir-lab
SIM_LOG=/var/log/ir-lab-simulation.log
EVENT_ID="IR-SIM-$(date -u +%Y%m%dT%H%M%SZ)"
DOC_SOURCE_IP=198.51.100.77
DOC_CALLBACK_IP=203.0.113.50

install -d -m 0755 "$LAB_ROOT/sensitive" "$LAB_ROOT/web" "$LAB_ROOT/evidence"
touch "$SIM_LOG"
chmod 0640 "$SIM_LOG"

record_event() {
  local message=$1
  printf '%s host=%s event_id=%s %s\n' "$(date --iso-8601=seconds)" "$(hostname)" "$EVENT_ID" "$message" | tee -a "$SIM_LOG"
}

record_event "[SAFE-SIMULATION] phase=start description=harmless_incident_generation"

for port in 44512 44518 44531 44544 44559 44572; do
  logger -p authpriv.warning -t sshd "[SAFE-SIMULATION] Failed password for invalid user admin from ${DOC_SOURCE_IP} port ${port} ssh2"
  record_event "[SAFE-SIMULATION] event=failed_login user=admin src_ip=${DOC_SOURCE_IP} src_port=${port}"
done

logger -p authpriv.notice -t sshd "[SAFE-SIMULATION] Accepted password for ir_demo from ${DOC_SOURCE_IP} port 44601 ssh2"
record_event "[SAFE-SIMULATION] event=login_success user=ir_demo src_ip=${DOC_SOURCE_IP} src_port=44601"

printf 'Synthetic customer record for IR lab only\n' > "$LAB_ROOT/sensitive/customer-demo.txt"
chmod 0600 "$LAB_ROOT/sensitive/customer-demo.txt"
printf 'Updated during safe simulation at %s\n' "$(date --iso-8601=seconds)" >> "$LAB_ROOT/sensitive/customer-demo.txt"
record_event "[SAFE-SIMULATION] event=sensitive_file_modified path=${LAB_ROOT}/sensitive/customer-demo.txt"

printf 'IR lab web service - no sensitive data\n' > "$LAB_ROOT/web/index.html"
if [[ -f "$LAB_ROOT/http_server.pid" ]] && kill -0 "$(cat "$LAB_ROOT/http_server.pid")" 2>/dev/null; then
  record_event "[SAFE-SIMULATION] event=local_service_already_running pid=$(cat "$LAB_ROOT/http_server.pid") port=8088"
else
  nohup python3 -m http.server 8088 --bind 127.0.0.1 --directory "$LAB_ROOT/web" \
    >"$LAB_ROOT/http_server.log" 2>&1 &
  echo $! > "$LAB_ROOT/http_server.pid"
  record_event "[SAFE-SIMULATION] event=benign_process_started process=python3-http-server pid=$! listen=127.0.0.1:8088"
fi

curl --max-time 3 --silent http://127.0.0.1:8088/ >/dev/null || true
record_event "[SAFE-SIMULATION] event=loopback_connection destination=127.0.0.1:8088"

cat > "$LAB_ROOT/evidence/suspicious-note.txt" <<NOTE
SAFE-SIMULATION ONLY
event_id=${EVENT_ID}
callback=${DOC_CALLBACK_IP}:443
This documentation-only address was not contacted.
NOTE
record_event "[SAFE-SIMULATION] event=ioc_marker_created value=${DOC_CALLBACK_IP}:443 network_contact=false"

sha256sum "$LAB_ROOT/evidence/suspicious-note.txt" | tee "$LAB_ROOT/evidence/suspicious-note.sha256"
record_event "[SAFE-SIMULATION] phase=end result=completed"

echo
echo "Simulation completed. Event ID: $EVENT_ID"
echo "Log: $SIM_LOG"
echo "Cleanup command: sudo bash cleanup_safe_incident.sh"
