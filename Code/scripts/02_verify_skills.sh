#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

ensure_project_dirs
require_command git

skills=(
  implementing-velociraptor-for-ir-collection
  analyzing-security-logs-with-splunk
  analyzing-linux-audit-logs-for-intrusion
  collecting-volatile-evidence-from-compromised-host
  containing-active-breach
  conducting-memory-forensics-with-volatility
  performing-disk-forensics-investigation
  collecting-indicators-of-compromise
  building-incident-timeline-with-timesketch
  validating-backup-integrity-for-recovery
)

primary_repo="$HOME/incident-response-project/skills-catalog"
dedicated_repo="$HOME/incident-response-project/skills-catalog-${SKILLS_COMMIT:0:8}"
skills_repo=""

if [[ -d "$primary_repo/.git" ]] && \
   [[ $(git -C "$primary_repo" rev-parse HEAD 2>/dev/null || true) == "$SKILLS_COMMIT" ]] && \
   [[ -z $(git -C "$primary_repo" status --porcelain) ]]; then
  skills_repo="$primary_repo"
elif [[ -d "$dedicated_repo/.git" ]]; then
  [[ -z $(git -C "$dedicated_repo" status --porcelain) ]] \
    || die "Dedicated skills checkout contains local changes; refusing to trust or overwrite it: $dedicated_repo"
  skills_repo="$dedicated_repo"
else
  mkdir -p "$(dirname "$dedicated_repo")"
  git clone --filter=blob:none "$SKILLS_REPO_URL" "$dedicated_repo"
  skills_repo="$dedicated_repo"
fi

[[ -z $(git -C "$skills_repo" status --porcelain) ]] \
  || die "Skills checkout is not clean: $skills_repo"

if [[ $(git -C "$skills_repo" rev-parse HEAD 2>/dev/null || true) != "$SKILLS_COMMIT" ]]; then
  if [[ -n $(git -C "$skills_repo" status --porcelain) ]]; then
    die "Dedicated skills checkout contains local changes; refusing to overwrite: $skills_repo"
  fi
  git -C "$skills_repo" fetch --depth 1 origin "$SKILLS_COMMIT"
  git -C "$skills_repo" checkout --detach "$SKILLS_COMMIT"
fi

verification="$OUTPUT_DIR/selected-skills-verification.txt"
{
  printf 'Repository: %s\n' "$SKILLS_REPO_URL"
  printf 'Requested commit: %s\n' "$SKILLS_COMMIT"
  printf 'Checked-out commit: %s\n\n' "$(git -C "$skills_repo" rev-parse HEAD)"
  printf 'Selected Incident Response skills:\n'
  for skill in "${skills[@]}"; do
    if [[ -f "$skills_repo/skills/$skill/SKILL.md" ]]; then
      printf 'OK      %s\n' "$skill"
    else
      printf 'MISSING %s\n' "$skill"
    fi
  done
} | tee "$verification"

if grep -q '^MISSING' "$verification"; then
  die "One or more required skills are missing at the pinned commit."
fi

printf '%s\n' "$skills_repo" > "$OUTPUT_DIR/skills-repository-path.txt"
sha256sum "$verification" > "$verification.sha256"
printf 'SKILLS VERIFICATION RESULT: PASS\n'
