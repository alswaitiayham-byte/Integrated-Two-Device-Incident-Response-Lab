#!/usr/bin/env bash
set -euo pipefail

ACTION=${1:-status}
TABLE_NAME=ayham_ir_safe_containment
IOC_SOURCE=198.51.100.77
IOC_CALLBACK=203.0.113.50

if [[ ${EUID} -ne 0 ]]; then
  echo "Run with sudo on the authorized Ubuntu lab host." >&2
  exit 1
fi
if ! command -v nft >/dev/null 2>&1; then
  echo "nftables is required. This script never flushes or replaces existing firewall rules." >&2
  exit 1
fi

show_plan() {
  cat <<EOF
Safe containment plan
- Block only RFC 5737 simulation source: $IOC_SOURCE
- Block only RFC 5737 simulation callback: $IOC_CALLBACK
- Preserve loopback, LAN, gateway, DNS, Velociraptor, and Internet connectivity
- Use a uniquely named nftables table that can be removed atomically
EOF
}

case "$ACTION" in
  plan)
    show_plan
    ;;
  contain)
    show_plan
    if nft list table inet "$TABLE_NAME" >/dev/null 2>&1; then
      echo "Project containment table already exists."
      nft list table inet "$TABLE_NAME"
      exit 0
    fi
    nft add table inet "$TABLE_NAME"
    cleanup_failed_table() {
      nft delete table inet "$TABLE_NAME" >/dev/null 2>&1 || true
    }
    trap cleanup_failed_table ERR
    nft "add chain inet $TABLE_NAME input { type filter hook input priority -5; policy accept; }"
    nft "add chain inet $TABLE_NAME output { type filter hook output priority -5; policy accept; }"
    nft "add rule inet $TABLE_NAME input ip saddr { $IOC_SOURCE, $IOC_CALLBACK } counter drop comment \"Ayham IR safe simulated IOCs\""
    nft "add rule inet $TABLE_NAME output ip daddr { $IOC_SOURCE, $IOC_CALLBACK } counter drop comment \"Ayham IR safe simulated IOCs\""
    trap - ERR
    logger -p authpriv.notice -t ir-containment \
      "SAFE-SIMULATION targeted IOC containment enabled: $IOC_SOURCE,$IOC_CALLBACK"
    echo "Targeted safe containment enabled. Normal connectivity was not isolated."
    nft list table inet "$TABLE_NAME"
    ;;
  release)
    if nft list table inet "$TABLE_NAME" >/dev/null 2>&1; then
      nft delete table inet "$TABLE_NAME"
      logger -p authpriv.notice -t ir-containment \
        "SAFE-SIMULATION targeted IOC containment released"
      echo "Project containment table released."
    else
      echo "No project containment table exists."
    fi
    ;;
  status)
    nft list table inet "$TABLE_NAME" 2>/dev/null || echo "Project containment is not active."
    ;;
  *)
    echo "Usage: sudo $0 {plan|contain|release|status}" >&2
    exit 1
    ;;
esac
