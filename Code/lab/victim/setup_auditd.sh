#!/usr/bin/env bash
set -euo pipefail

if [[ ${EUID} -ne 0 ]]; then
  echo "Run this script with sudo on the authorized Ubuntu lab host." >&2
  exit 1
fi

if ! command -v auditctl >/dev/null 2>&1; then
  if [[ "${IR_SKIP_INSTALL:-0}" == "1" ]]; then
    echo "auditd is missing and IR_SKIP_INSTALL=1." >&2
    exit 1
  fi
  if command -v apt-get >/dev/null 2>&1; then
    apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get install -y auditd audispd-plugins
  else
    echo "Install auditd using the operating system package manager, then rerun." >&2
    exit 1
  fi
fi

install -d -m 0755 /opt/ir-lab/sensitive /opt/ir-lab/web /opt/ir-lab/evidence
install -d -m 0755 /etc/audit/rules.d

tee /etc/audit/rules.d/ir-project.rules >/dev/null <<'RULES'
## Incident Response course lab - defensive monitoring only
-w /opt/ir-lab/sensitive -p wa -k ir_sensitive
-w /opt/ir-lab/evidence -p wa -k ir_evidence
-w /etc/passwd -p wa -k identity_changes
-w /etc/shadow -p wa -k identity_changes
-a always,exit -F arch=b64 -S execve -F euid=0 -k privileged_exec
-a always,exit -F arch=b32 -S execve -F euid=0 -k privileged_exec
RULES

if command -v systemctl >/dev/null 2>&1; then
  systemctl enable --now auditd || true
fi

if command -v augenrules >/dev/null 2>&1; then
  augenrules --load
else
  auditctl -R /etc/audit/rules.d/ir-project.rules
fi

echo "auditd status"
auditctl -s
echo
echo "Loaded project rules"
auditctl -l | grep -E 'ir_sensitive|ir_evidence|identity_changes|privileged_exec' || true
echo
echo "Audit preparation complete. Take a screenshot of this output."
