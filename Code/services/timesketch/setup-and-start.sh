#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=../../lib/common.sh
source "$SCRIPT_DIR/../../lib/common.sh"

require_command curl
require_command docker
run_as_root docker info >/dev/null 2>&1 || die "Docker Engine is not available."

if run_as_root docker ps --format '{{.Names}}' | grep -qx 'ayham-ir-splunk'; then
  die "Splunk is running. Stop it first with services/splunk/stop.sh."
fi

available_kb=$(df -Pk / | awk 'NR==2 {print $4}')
(( available_kb >= 12 * 1024 * 1024 )) || die "Timesketch needs at least 12 GiB free on /."

cat <<EOF
Timesketch is an optional heavy service (OpenSearch, PostgreSQL, Redis, workers,
and web UI). This wrapper uses the official deployment helper pinned to release
$TIMESKETCH_RELEASE. Do not run it together with Splunk on this laptop.
EOF
read -r -p 'Type YES to install/start optional Timesketch: ' confirmation
[[ "$confirmation" == YES ]] || die "Timesketch start cancelled."

official_deploy_script="$TOOLS_DIR/deploy_timesketch-${TIMESKETCH_RELEASE}-official.sh"
deploy_script="$TOOLS_DIR/deploy_timesketch-${TIMESKETCH_RELEASE}-pinned.sh"
deploy_url="https://raw.githubusercontent.com/google/timesketch/${TIMESKETCH_RELEASE}/contrib/deploy_timesketch.sh"
download_verified "$deploy_url" "$official_deploy_script" "$TIMESKETCH_DEPLOY_SHA256"
sed "s#https://raw.githubusercontent.com/google/timesketch/master#https://raw.githubusercontent.com/google/timesketch/${TIMESKETCH_RELEASE}#g" \
  "$official_deploy_script" > "$deploy_script"
chmod 0755 "$deploy_script"
if grep -q 'google/timesketch/master' "$deploy_script"; then
  die "Could not pin all Timesketch helper downloads to release $TIMESKETCH_RELEASE."
fi
{
  printf '%s  %s\n' "$TIMESKETCH_DEPLOY_SHA256" "$official_deploy_script"
  sha256sum "$deploy_script"
} | tee "$OUTPUT_DIR/timesketch-deploy-scripts.sha256"

if [[ ! -f /opt/timesketch/docker-compose.yml && ! -f /opt/timesketch/docker-compose.yaml ]]; then
  log "Running the official Timesketch deployment helper without starting containers yet."
  if [[ ${EUID} -eq 0 ]]; then
    (cd /opt && printf 'n\n' | bash "$deploy_script" --skip-create-user)
  else
    printf 'n\n' | sudo bash -c 'cd /opt && bash "$1" --skip-create-user' _ "$deploy_script"
  fi
fi

[[ -d /opt/timesketch ]] || die "The official helper did not create /opt/timesketch."

compose_file="/opt/timesketch/docker-compose.yml"
[[ -f "$compose_file" ]] || compose_file="/opt/timesketch/docker-compose.yaml"
[[ -f "$compose_file" ]] || die "Timesketch compose file was not found."

# Keep the unauthenticated HTTP lab UI on Ubuntu loopback only.
run_as_root sed -i \
  's#- ${NGINX_HTTP_PORT}:80#- 127.0.0.1:${NGINX_HTTP_PORT}:80#; s#- ${NGINX_HTTPS_PORT}:443#- 127.0.0.1:${NGINX_HTTPS_PORT}:443#' \
  "$compose_file"
grep -q '127.0.0.1:${NGINX_HTTP_PORT}:80' "$compose_file" \
  || die "Timesketch HTTP port could not be restricted to loopback."
run_as_root sed -i \
  "s/^OPENSEARCH_MEM_USE_GB=.*/OPENSEARCH_MEM_USE_GB=${TIMESKETCH_OPENSEARCH_GB}/" \
  /opt/timesketch/config.env

if [[ ${EUID} -eq 0 ]]; then
  (cd /opt/timesketch && docker compose up -d)
else
  (cd /opt/timesketch && sudo docker compose up -d)
fi

log "Waiting for the Timesketch web service to become healthy."
for attempt in {1..60}; do
  health=$(run_as_root docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' timesketch-web 2>/dev/null || true)
  printf '  attempt %02d/60: %s\n' "$attempt" "${health:-not-created}"
  [[ "$health" == healthy ]] && break
  [[ "$health" == exited || "$health" == dead ]] && break
  sleep 5
done
health=$(run_as_root docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' timesketch-web 2>/dev/null || true)
[[ "$health" == healthy ]] || die "Timesketch did not become healthy. Review: sudo docker logs timesketch-web"

user_marker="/opt/timesketch/.ayham-ir-user-created"
if ! run_as_root test -f "$user_marker"; then
  read -r -p 'Timesketch username [ayham_ir]: ' timesketch_user
  timesketch_user=${timesketch_user:-ayham_ir}
  [[ "$timesketch_user" =~ ^[A-Za-z][A-Za-z0-9_.-]{2,31}$ ]] || die "Invalid Timesketch username."
  printf 'Create a NEW Timesketch password when prompted; input is hidden.\n'
  if [[ ${EUID} -eq 0 ]]; then
    (cd /opt/timesketch && docker compose exec timesketch-web tsctl create-user "$timesketch_user")
  else
    (cd /opt/timesketch && sudo docker compose exec timesketch-web tsctl create-user "$timesketch_user")
  fi
  printf '%s\n' "$timesketch_user" | run_as_root tee "$user_marker" >/dev/null
  run_as_root chmod 0600 "$user_marker"
fi

{
  printf 'Timesketch release: %s\n' "$TIMESKETCH_RELEASE"
  printf 'Started UTC: %s\n' "$(date -u --iso-8601=seconds)"
  printf 'Install directory: /opt/timesketch\n'
  printf 'Web exposure: 127.0.0.1 only\n'
  printf 'OpenSearch heap: %s GiB\n' "$TIMESKETCH_OPENSEARCH_GB"
  printf 'Timeline to import: %s\n' "$PROJECT_ROOT/output (or the latest case timesketch-timeline.csv)"
} | tee "$OUTPUT_DIR/timesketch-status.txt"

printf 'TIMESKETCH START REQUEST: COMPLETED\n'
printf 'Open on Ubuntu: http://127.0.0.1/\n'
printf 'Import the generated timesketch-timeline.csv from the latest case.\n'
