#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

ensure_project_dirs
server_ip=${IR_SERVER_IP:-$(ubuntu_server_ip)}
[[ -n "$server_ip" ]] || die "Could not determine the Ubuntu LAN IP."

server_config="/etc/velociraptor/server.config.yaml"
run_as_root test -s "$server_config" || die "Run ./RUN_ME_FIRST.sh setup to configure Velociraptor first."

# The official Debian package name differs slightly between Velociraptor
# releases/build environments. Accept the verified executable locations used
# by the package instead of assuming only /usr/local/bin/velociraptor.bin.
installed_binary=""
for candidate in \
  /usr/local/bin/velociraptor.bin \
  /usr/local/bin/velociraptor \
  /usr/bin/velociraptor.bin \
  /usr/bin/velociraptor; do
  if run_as_root test -x "$candidate"; then
    installed_binary=$candidate
    break
  fi
done
if [[ -z "$installed_binary" ]]; then
  installed_binary=$(run_as_root find /usr/local/bin /usr/bin -maxdepth 1 \
    -type f -name 'velociraptor*' -perm /111 -print -quit 2>/dev/null || true)
fi
[[ -n "$installed_binary" ]] || die "Installed Velociraptor binary was not found."
log "Using installed Velociraptor binary: $installed_binary"

windows_name="velociraptor-v${VELOCIRAPTOR_VERSION}-windows-amd64.exe"
windows_url="https://github.com/Velocidex/velociraptor/releases/download/v${VELOCIRAPTOR_VERSION}/${windows_name}"
windows_binary="$TOOLS_DIR/$windows_name"
download_verified "$windows_url" "$windows_binary" "$VELOCIRAPTOR_WINDOWS_SHA256"

bundle="$OUTPUT_DIR/windows-client"
temporary_config=$(mktemp -t ayham-client-config.XXXXXX)
cleanup_config() {
  shred -u "$temporary_config" 2>/dev/null || rm -f "$temporary_config"
}
trap cleanup_config EXIT
umask 077
run_as_root "$installed_binary" --config "$server_config" config client > "$temporary_config"
grep -q "https://${server_ip}:${VELOCIRAPTOR_FRONTEND_PORT}/" "$temporary_config" \
  || die "Client configuration does not contain the expected Ubuntu IP."

mkdir -p "$bundle"
# Clear only the generated bundle contents. The fixed project-owned path and
# mindepth guard prevent an accidental broad deletion if configuration changes.
find "$bundle" -mindepth 1 -delete
install -m 0755 "$windows_binary" "$bundle/$windows_name"
install -m 0600 "$temporary_config" "$bundle/client.config.yaml"
install -m 0644 "$PROJECT_ROOT/windows/Install-VelociraptorClient.ps1" "$bundle/"
install -m 0644 "$PROJECT_ROOT/windows/Generate-SafeIncident.ps1" "$bundle/"
install -m 0644 "$PROJECT_ROOT/windows/Collect-VolatileEvidence.ps1" "$bundle/"
install -m 0644 "$PROJECT_ROOT/windows/Contain-SafeIncident.ps1" "$bundle/"
install -m 0644 "$PROJECT_ROOT/windows/Rollback-Containment.ps1" "$bundle/"
install -m 0644 "$PROJECT_ROOT/windows/Acquire-Memory.ps1" "$bundle/"
install -m 0644 "$PROJECT_ROOT/windows/Run-Windows-Demo.ps1" "$bundle/"
install -m 0644 "$PROJECT_ROOT/windows/README_WINDOWS.txt" "$bundle/"

{
  printf 'VELOCIRAPTOR_SERVER_IP=%s\n' "$server_ip"
  printf 'VELOCIRAPTOR_FRONTEND_PORT=%s\n' "$VELOCIRAPTOR_FRONTEND_PORT"
  printf 'VELOCIRAPTOR_VERSION=%s\n' "$VELOCIRAPTOR_VERSION"
  printf 'GENERATED_UTC=%s\n' "$(date -u --iso-8601=seconds)"
} > "$bundle/server-info.env"

(
  cd "$bundle"
  manifest_tmp=$(mktemp)
  find . -maxdepth 1 -type f ! -name SHA256SUMS -print0 \
    | sort -z | xargs -0 sha256sum > "$manifest_tmp"
  mv "$manifest_tmp" SHA256SUMS
)

cleanup_config
trap - EXIT
printf 'Windows bundle: %s\n' "$bundle"
printf 'Copy this entire folder to the authorized Windows 11 computer.\n'
printf 'WINDOWS BUNDLE RESULT: PASS\n'
