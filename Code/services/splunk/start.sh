#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=../../lib/common.sh
source "$SCRIPT_DIR/../../lib/common.sh"

require_command docker
run_as_root docker info >/dev/null 2>&1 || die "Docker Engine is not available."

if run_as_root docker ps --format '{{.Names}}' | grep -Eqi 'timesketch|opensearch|postgres.*timesketch'; then
  die "Timesketch appears to be running. Stop it before starting Splunk on this 16 GB host."
fi

cat <<'EOF'
Splunk is optional commercial software. Before continuing, read the current terms:
  https://www.splunk.com/en_us/legal/splunk-general-terms.html
  https://github.com/splunk/docker-splunk

This project cannot accept legal terms on your behalf.
EOF
read -r -p 'After reading and agreeing, type I AGREE exactly: ' agreement
[[ "$agreement" == 'I AGREE' ]] || die "Splunk start cancelled; terms were not accepted."

read_strong_password() {
  local first second
  while true; do
    read -r -s -p 'Create a NEW Splunk admin password (12+ mixed characters): ' first
    printf '\n'
    read -r -s -p 'Repeat the password: ' second
    printf '\n'
    if [[ "$first" != "$second" ]]; then
      warn "Passwords do not match."
      continue
    fi
    if (( ${#first} < 12 )) || \
       [[ ! "$first" =~ [[:upper:]] ]] || \
       [[ ! "$first" =~ [[:lower:]] ]] || \
       [[ ! "$first" =~ [[:digit:]] ]] || \
       [[ ! "$first" =~ [^[:alnum:]] ]]; then
      warn "Use at least 12 characters with upper/lower case, a digit, and a symbol."
      continue
    fi
    if [[ ! "$first" =~ ^[A-Za-z0-9@%+=:,._-]+$ ]]; then
      warn "For safe Docker env parsing, use letters, digits, and these symbols only: @ % + = : , . _ -"
      continue
    fi
    SPLUNK_PASSWORD=$first
    break
  done
}

read_strong_password
env_file=$(mktemp -t ayham-splunk-env.XXXXXX)
cleanup_env_file() {
  shred -u "$env_file" 2>/dev/null || true
}
trap cleanup_env_file EXIT
chmod 0600 "$env_file"
{
  printf 'SPLUNK_PASSWORD=%s\n' "$SPLUNK_PASSWORD"
  printf 'SPLUNK_IMAGE=%s\n' "$SPLUNK_IMAGE"
  printf 'SPLUNK_START_ARGS=--accept-license\n'
  printf 'SPLUNK_GENERAL_TERMS=--accept-sgt-current-at-splunk-com\n'
} > "$env_file"
unset SPLUNK_PASSWORD

run_as_root docker compose --env-file "$env_file" -f "$SCRIPT_DIR/docker-compose.yml" up -d
cleanup_env_file
trap - EXIT

log "Splunk is starting. First startup can take several minutes."
for attempt in {1..40}; do
  health=$(run_as_root docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' ayham-ir-splunk 2>/dev/null || true)
  printf '  attempt %02d/40: %s\n' "$attempt" "${health:-not-created}"
  [[ "$health" == healthy ]] && break
  [[ "$health" == exited || "$health" == dead ]] && break
  sleep 15
done

health=$(run_as_root docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' ayham-ir-splunk 2>/dev/null || true)
if [[ "$health" != healthy ]]; then
  run_as_root docker logs --tail 80 ayham-ir-splunk 2>&1 || true
  die "Splunk did not become healthy. Review the logs above."
fi

printf 'SPLUNK RESULT: PASS\n'
printf 'Open on Ubuntu: http://127.0.0.1:18000\n'
printf 'Username: admin\n'
printf 'App: Integrated IR Course Project\n'
