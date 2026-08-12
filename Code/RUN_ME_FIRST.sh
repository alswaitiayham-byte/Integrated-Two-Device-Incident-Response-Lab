#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

ensure_project_dirs

usage() {
  cat <<'EOF'
Ayham Incident Response Project - two physical devices

Usage:
  ./RUN_ME_FIRST.sh setup       Install and configure Ubuntu + Windows bundle
  ./RUN_ME_FIRST.sh demo        Run the safe Ubuntu incident-response case
  ./RUN_ME_FIRST.sh status      Verify services, ports, storage, and tools
  ./RUN_ME_FIRST.sh splunk      Start optional Splunk lab (explicit terms acceptance)
  ./RUN_ME_FIRST.sh timesketch  Install/start optional Timesketch lab
  ./RUN_ME_FIRST.sh finalize    Create final evidence manifests and export
  ./RUN_ME_FIRST.sh validate    Run offline automated validation tests
  ./RUN_ME_FIRST.sh help        Show this help

Run setup first. Splunk and Timesketch are intentionally optional and must not
run at the same time on the 16 GB Ubuntu laptop.
EOF
}

run_step() {
  local script=$1
  shift
  log "Running $(basename "$script")"
  bash "$script" "$@"
}

setup_project() {
  require_ubuntu
  local log_file
  log_file="$RUN_LOG_DIR/setup-$(timestamp_utc).log"
  log "Full setup log: $log_file"
  {
    run_step "$PROJECT_ROOT/scripts/00_preflight.sh"
    run_step "$PROJECT_ROOT/scripts/01_install_dependencies.sh"
    run_step "$PROJECT_ROOT/scripts/02_verify_skills.sh"
    run_step "$PROJECT_ROOT/scripts/03_configure_auditd.sh"
    run_step "$PROJECT_ROOT/scripts/04_setup_velociraptor.sh"
    run_step "$PROJECT_ROOT/scripts/05_prepare_windows_bundle.sh"
    run_step "$PROJECT_ROOT/scripts/08_status.sh"
  } 2>&1 | tee "$log_file"
  log "SETUP RESULT: PASS"
  printf '\nNext: copy output/windows-client to Windows and follow README_WINDOWS.txt\n'
}

command_name=${1:-setup}
case "$command_name" in
  setup) setup_project ;;
  demo) run_step "$PROJECT_ROOT/scripts/06_run_safe_case.sh" ;;
  status) run_step "$PROJECT_ROOT/scripts/08_status.sh" ;;
  splunk) bash "$PROJECT_ROOT/services/splunk/start.sh" ;;
  timesketch) bash "$PROJECT_ROOT/services/timesketch/setup-and-start.sh" ;;
  finalize) run_step "$PROJECT_ROOT/scripts/07_finalize_evidence.sh" ;;
  validate) bash "$PROJECT_ROOT/lab/tests/run_all_offline.sh" ;;
  help|-h|--help) usage ;;
  *) usage >&2; exit 2 ;;
esac
