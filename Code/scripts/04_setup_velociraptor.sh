#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

require_ubuntu
ensure_project_dirs
require_command jq
require_command sha256sum

server_ip=${IR_SERVER_IP:-$(ubuntu_server_ip)}
[[ -n "$server_ip" ]] || die "Could not determine the Ubuntu LAN IP."
python3 - "$server_ip" <<'PY'
import ipaddress
import sys

address = ipaddress.ip_address(sys.argv[1])
private_lans = (
    ipaddress.ip_network("10.0.0.0/8"),
    ipaddress.ip_network("172.16.0.0/12"),
    ipaddress.ip_network("192.168.0.0/16"),
)
if address.version != 4 or not any(address in network for network in private_lans):
    raise SystemExit("Velociraptor must use an RFC 1918 private IPv4 address for this lab.")
PY

linux_name="velociraptor-v${VELOCIRAPTOR_VERSION}-linux-amd64"
linux_url="https://github.com/Velocidex/velociraptor/releases/download/v${VELOCIRAPTOR_VERSION}/${linux_name}"
existing_binary="$HOME/incident-response-project/01-velociraptor/setup/$linux_name"
managed_binary="$TOOLS_DIR/$linux_name"

if sha256_verify "$existing_binary" "$VELOCIRAPTOR_LINUX_SHA256"; then
  binary="$existing_binary"
  chmod 0755 "$binary"
  log "Reusing the previously verified Velociraptor binary."
else
  binary="$managed_binary"
  download_verified "$linux_url" "$binary" "$VELOCIRAPTOR_LINUX_SHA256"
fi

version_output=$($binary version)
grep -q "version: $VELOCIRAPTOR_VERSION" <<< "$version_output" || die "Unexpected Velociraptor version."
printf '%s\n' "$version_output" > "$OUTPUT_DIR/velociraptor-version.txt"
printf '%s  %s\n' "$VELOCIRAPTOR_LINUX_SHA256" "$binary" > "$OUTPUT_DIR/velociraptor-linux.sha256"

server_config="/etc/velociraptor/server.config.yaml"
managed_marker="/etc/velociraptor/.ayham-ir-managed"
admin_marker="/etc/velociraptor/.ayham-ir-admin-created"
service_name="velociraptor_server.service"

if run_as_root test -s "$server_config"; then
  if ! run_as_root test -f "$managed_marker"; then
    die "An existing unmanaged Velociraptor configuration was found at $server_config. It was not changed; back it up and review it before any replacement."
  fi
  log "Reusing the project-managed Velociraptor configuration."
else
  temporary_dir=$(mktemp -d -t ayham-velociraptor.XXXXXX)
  cleanup_sensitive() {
    find "$temporary_dir" -type f -exec shred -u {} + 2>/dev/null || true
    find "$temporary_dir" -depth -type d -empty -delete 2>/dev/null || true
  }
  trap cleanup_sensitive EXIT
  mkdir -p "$temporary_dir/package"
  chmod 0700 "$temporary_dir"
  umask 077

  jq -n \
    --arg url "https://${server_ip}:${VELOCIRAPTOR_FRONTEND_PORT}/" \
    --arg host "$server_ip" \
    --argjson frontend_port "$VELOCIRAPTOR_FRONTEND_PORT" \
    --argjson gui_port "$VELOCIRAPTOR_GUI_PORT" \
    --arg datastore "$VELOCIRAPTOR_DATASTORE" \
    '{
      Client: {
        server_urls: [$url],
        use_self_signed_ssl: true
      },
      Frontend: {
        hostname: $host,
        bind_address: "0.0.0.0",
        bind_port: $frontend_port,
        resources: {expected_clients: 10}
      },
      GUI: {
        bind_address: "127.0.0.1",
        bind_port: $gui_port,
        public_url: ("https://127.0.0.1:" + ($gui_port|tostring) + "/app/index.html")
      },
      Datastore: {
        implementation: "FileBaseDataStore",
        location: $datastore,
        filestore_directory: $datastore,
        compression: "zlib"
      }
    }' > "$temporary_dir/merge.json"

  "$binary" config generate --merge_file "$temporary_dir/merge.json" \
    > "$temporary_dir/server.config.yaml"
  grep -q "https://${server_ip}:${VELOCIRAPTOR_FRONTEND_PORT}/" "$temporary_dir/server.config.yaml" \
    || die "Generated configuration has the wrong frontend URL."

  log "Building the official Velociraptor Debian server package."
  "$binary" debian server \
    --config "$temporary_dir/server.config.yaml" \
    --binary "$binary" \
    --output "$temporary_dir/package"
  server_deb=$(find "$temporary_dir/package" -maxdepth 1 -type f -name '*.deb' -print -quit)
  [[ -n "$server_deb" ]] || die "Velociraptor did not create a Debian package."
  run_as_root dpkg -i "$server_deb"
  run_as_root install -d -m 0750 -o velociraptor -g velociraptor /etc/velociraptor
  run_as_root touch "$managed_marker"
  run_as_root chmod 0640 "$managed_marker"
  trap - EXIT
  cleanup_sensitive
fi

installed_binary="/usr/local/bin/velociraptor.bin"
if ! run_as_root test -x "$installed_binary"; then
  installed_binary=$(run_as_root find /usr/local/bin /usr/bin -maxdepth 1 -type f -name 'velociraptor*' -perm /111 -print 2>/dev/null | head -n 1)
fi
[[ -n "$installed_binary" ]] || die "Could not locate the installed Velociraptor server binary."

if ! run_as_root test -f "$admin_marker"; then
  admin_user=${IR_ADMIN_USER:-ayham_ir}
  [[ "$admin_user" =~ ^[A-Za-z][A-Za-z0-9_.-]{2,31}$ ]] || die "Invalid Velociraptor admin username: $admin_user"
  printf '\nCreate one Velociraptor administrator account: %s\n' "$admin_user"
  printf 'Enter a NEW password when prompted (12+ characters, mixed case, digit, symbol).\n'
  printf 'Do not reuse 123456789 or any password shown in a screenshot.\n\n'
  run_as_root systemctl stop "$service_name" 2>/dev/null || true
  if [[ ${EUID} -eq 0 ]]; then
    runuser -u velociraptor -- "$installed_binary" --config "$server_config" \
      user add --role administrator "$admin_user"
  else
    sudo -u velociraptor "$installed_binary" --config "$server_config" \
      user add --role administrator "$admin_user"
  fi
  printf '%s\n' "$admin_user" | run_as_root tee "$admin_marker" >/dev/null
  run_as_root chown velociraptor:velociraptor "$admin_marker"
  run_as_root chmod 0600 "$admin_marker"
fi

run_as_root systemctl daemon-reload
run_as_root systemctl enable --now "$service_name"
run_as_root systemctl restart "$service_name"

if command -v ufw >/dev/null 2>&1 && run_as_root ufw status | grep -q '^Status: active'; then
  lan_cidr=$(ubuntu_lan_cidr 2>/dev/null || true)
  [[ -n "$lan_cidr" ]] || die "UFW is active but the local LAN CIDR could not be detected."
  run_as_root ufw allow from "$lan_cidr" to any port "$VELOCIRAPTOR_FRONTEND_PORT" proto tcp \
    comment 'Ayham IR Velociraptor frontend'
fi

for _ in {1..20}; do
  if nc -z 127.0.0.1 "$VELOCIRAPTOR_GUI_PORT" 2>/dev/null && \
     nc -z 127.0.0.1 "$VELOCIRAPTOR_FRONTEND_PORT" 2>/dev/null; then
    break
  fi
  sleep 1
done
nc -z 127.0.0.1 "$VELOCIRAPTOR_GUI_PORT" || die "Velociraptor GUI is not listening on $VELOCIRAPTOR_GUI_PORT."
nc -z 127.0.0.1 "$VELOCIRAPTOR_FRONTEND_PORT" || die "Velociraptor frontend is not listening on $VELOCIRAPTOR_FRONTEND_PORT."

{
  printf 'Velociraptor version: %s\n' "$VELOCIRAPTOR_VERSION"
  printf 'Server IP: %s\n' "$server_ip"
  printf 'Client frontend: https://%s:%s/\n' "$server_ip" "$VELOCIRAPTOR_FRONTEND_PORT"
  printf 'Local GUI: https://127.0.0.1:%s/\n' "$VELOCIRAPTOR_GUI_PORT"
  printf 'GUI exposure: loopback only\n'
  printf 'Service: %s\n' "$(run_as_root systemctl is-active "$service_name")"
  printf 'Configuration: generated non-interactively; private keys not copied to project output\n'
} | tee "$OUTPUT_DIR/velociraptor-deployment-status.txt"
sha256sum "$OUTPUT_DIR/velociraptor-deployment-status.txt" \
  > "$OUTPUT_DIR/velociraptor-deployment-status.txt.sha256"

printf 'VELOCIRAPTOR SETUP RESULT: PASS\n'
