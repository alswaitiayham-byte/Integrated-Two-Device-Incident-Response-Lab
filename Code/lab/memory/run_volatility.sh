#!/usr/bin/env bash
set -euo pipefail

IMAGE=${1:-}
OUTPUT_DIR=${2:-./volatility_results}
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
PROJECT_ROOT=$(cd -- "$SCRIPT_DIR/../.." && pwd)

if [[ -z "$IMAGE" || ! -f "$IMAGE" ]]; then
  echo "Usage: $0 /path/to/windows-memory.raw [output-directory]" >&2
  exit 1
fi
mkdir -p "$OUTPUT_DIR"

if [[ -n "${VOLATILITY_BIN:-}" ]]; then
  read -r -a VOL_CMD <<< "$VOLATILITY_BIN"
elif [[ -x "$PROJECT_ROOT/.tools/volatility3-venv/bin/vol" ]]; then
  VOL_CMD=("$PROJECT_ROOT/.tools/volatility3-venv/bin/vol")
elif command -v vol >/dev/null 2>&1; then
  VOL_CMD=(vol)
elif command -v vol.py >/dev/null 2>&1; then
  VOL_CMD=(vol.py)
elif python3 -c 'import volatility3' >/dev/null 2>&1; then
  VOL_CMD=(python3 -m volatility3)
else
  echo "Volatility 3 was not found. Install it from the official project and rerun." >&2
  exit 1
fi

sha256sum "$IMAGE" > "$OUTPUT_DIR/memory_image.sha256"
stat "$IMAGE" > "$OUTPUT_DIR/memory_image.stat"
printf 'Command:' > "$OUTPUT_DIR/tool_command.txt"
printf ' %q' "${VOL_CMD[@]}" >> "$OUTPUT_DIR/tool_command.txt"
printf '\nUTC start: %s\n' "$(date -u --iso-8601=seconds)" >> "$OUTPUT_DIR/tool_command.txt"

plugins=(
  windows.info
  windows.pslist
  windows.pstree
  windows.cmdline
  windows.netscan
  windows.filescan
  windows.malfind
)

for plugin in "${plugins[@]}"; do
  safe_name=${plugin//./_}
  echo "Running $plugin"
  "${VOL_CMD[@]}" -f "$IMAGE" "$plugin" > "$OUTPUT_DIR/${safe_name}.txt" 2>&1 || \
    printf 'Plugin failed; review symbols, image format, and error above.\n' >> "$OUTPUT_DIR/${safe_name}.txt"
done

cat > "$OUTPUT_DIR/ANALYST_REVIEW.txt" <<'EOF'
Memory Forensics Manual Review

1. Confirm OS/build in windows.info.
2. Compare pslist and pstree for unusual parents, missing paths, or misleading names.
3. Review cmdline for the exact process purpose.
4. Link netscan PIDs back to pslist/pstree.
5. Treat malfind hits as leads. Correlate memory protections, bytes, process path,
   signature, network activity, and other evidence before making a malware claim.
6. Document false positives and contradictory evidence.
7. Verify memory_image.sha256 before and after analysis.
EOF

printf 'UTC completion: %s\n' "$(date -u --iso-8601=seconds)" >> "$OUTPUT_DIR/tool_command.txt"
(
  cd "$OUTPUT_DIR"
  manifest_tmp=$(mktemp)
  find . -maxdepth 1 -type f ! -name results_manifest.sha256 -print0 \
    | sort -z | xargs -0 sha256sum > "$manifest_tmp"
  mv "$manifest_tmp" results_manifest.sha256
)
echo "Volatility results saved to $OUTPUT_DIR"
