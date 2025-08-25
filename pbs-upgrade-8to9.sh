#!/usr/bin/env bash
# Proxmox Backup Server Upgrade 8 -> 9 (bookworm -> trixie)
# Interactive, resumable script with review pauses where noted.

set -u
STATE_FILE="/var/tmp/pbs-upgrade-8to9.state"
LOG_FILE="/var/tmp/pbs-upgrade-8to9.log"

# --- helpers ---------------------------------------------------------------
need_root() {
  if [[ $EUID -ne 0 ]]; then
    echo "Please run as root (sudo -i)."
    exit 1
  fi
}

log() { printf "%(%Y-%m-%d %H:%M:%S)T  %s\n" -1 "$*" | tee -a "$LOG_FILE"; }
pause_review() {
  echo
  read -r -p "Pause to review output. Press Enter to continue... " _
}
ask_run() {
  local prompt="$1"
  echo
  read -r -p "$prompt [y/N]: " ans
  [[ "${ans,,}" == "y" || "${ans,,}" == "yes" ]]
}
save_state() { echo "$1" > "$STATE_FILE"; sync; }
load_state()  { [[ -f "$STATE_FILE" ]] && cat "$STATE_FILE" || echo "1"; }

# On Ctrl-C, save current step so we can resume later
trap 'log "Interrupted. Progress saved at step $CUR_STEP."; save_state "$CUR_STEP"; exit 130' INT

# --- steps -----------------------------------------------------------------
step_1() {
  if ask_run "Step 1: Make backup of /etc/proxmox-backup?"; then
    log "Running Step 1"
    tar czf "pbs3-etc-backup-$(date -I).tar.gz" -C "/etc" "proxmox-backup" | tee -a "$LOG_FILE"
    log "Step 1 complete."
  else
    log "Step 1 skipped."
  fi
}

step_2() {
  if ask_run "Step 2: Verify root mount disk space (need >=10GB)?"; then
    log "Running Step 2"
    df -h / | tee -a "$LOG_FILE"
    pause_review
    log "Step 2 complete."
  else
    log "Step 2 skipped."
  fi
}

step_3() {
  if ask_run "Step 3: Run upgrade checker script (pbs3to4 --full)?"; then
    log "Running Step 3"
    pbs3to4 --full | tee -a "$LOG_FILE"
    pause_review
    log "Step 3 complete."
  else
    log "Step 3 skipped."
  fi
}

step_4() {
  if ask_run "Step 4: Make sure all v8 updates are applied (apt update/dist-upgrade/versions)?"; then
    log "Running Step 4"
    apt update | tee -a "$LOG_FILE"
    apt dist-upgrade | tee -a "$LOG_FILE"
    proxmox-backup-manager versions | tee -a "$LOG_FILE"
    pause_review
    log "Step 4 complete."
  else
    log "Step 4 skipped."
  fi
}

step_5() {
  if ask_run "Step 5: Run upgrade checker again (pbs3to4 --full)?"; then
    log "Running Step 5"
    pbs3to4 --full | tee -a "$LOG_FILE"
    pause_review
    log "Step 5 complete."
  else
    log "Step 5 skipped."
  fi
}

step_6() {
  if ask_run "Step 6: Update APT repositories to trixie and PBS 9 sources?"; then
    log "Running Step 6"
    # Upgrade base Debian repo to trixie
    sed -i 's/bookworm/trixie/g' /etc/apt/sources.list
    # Clear any legacy PBS install list file (as implied by the provided steps)
    : > /etc/apt/sources.list.d/pbs-install-repo.list
    # Configure Proxmox sources (no-subscription)
    cat > /etc/apt/sources.list.d/proxmox.sources << 'EOF'
Types: deb
URIs: http://download.proxmox.com/debian/pbs
Suites: trixie
Components: pbs-no-subscription
Signed-By: /usr/share/keyrings/proxmox-archive-keyring.gpg
EOF
    apt update | tee -a "$LOG_FILE"
    apt policy | tee -a "$LOG_FILE"
    log "Step 6 complete."
  else
    log "Step 6 skipped."
  fi
}

step_6b() {
  if ask_run "Step 6 (again): Run upgrade checker again (pbs3to4 --full)?"; then
    log "Running Step 6 (checker again)"
    pbs3to4 --full | tee -a "$LOG_FILE"
    pause_review
    log "Step 6 (checker) complete."
  else
    log "Step 6 (checker) skipped."
  fi
}

step_7() {
  if ask_run "Step 7: Upgrade PBS 8 to 9 (apt update && apt dist-upgrade -y)?"; then
    log "Running Step 7"
    apt update | tee -a "$LOG_FILE"
    apt dist-upgrade -y | tee -a "$LOG_FILE"
    log "Step 7 complete."
  else
    log "Step 7 skipped."
  fi
}

step_8() {
  if ask_run "Step 8: Run upgrade checker again (pbs3to4 --full)?"; then
    log "Running Step 8"
    pbs3to4 --full | tee -a "$LOG_FILE"
    pause_review
    log "Step 8 complete."
  else
    log "Step 8 skipped."
  fi
}

step_9() {
  if ask_run "Step 9: Reboot server now? (script will save progress and you can rerun to resume)"; then
    log "Running Step 9"
    # Save next step number before reboot so we resume at Step 10
    save_state "10"
    log "Rebooting..."
    systemctl reboot
    # In case reboot fails:
    exit 0
  else
    log "Step 9 skipped."
  fi
}

step_10() {
  if ask_run "Step 10: Check service status (proxmox-backup-proxy & proxmox-backup)?"; then
    log "Running Step 10"
    systemctl status proxmox-backup-proxy.service proxmox-backup.service | tee -a "$LOG_FILE"
    pause_review
    log "Step 10 complete."
  else
    log "Step 10 skipped."
  fi
}

step_11() {
  if ask_run "Step 11: Modernize repository services (apt modernize-sources)?"; then
    log "Running Step 11"
    apt modernize-sources | tee -a "$LOG_FILE"
    log "Step 11 complete."
  else
    log "Step 11 skipped."
  fi
}

step_12() {
  if ask_run "Step 12: Remove enterprise repository file (/etc/apt/sources.list.d/pbs-enterprise.sources)?"; then
    log "Running Step 12"
    rm -f /etc/apt/sources.list.d/pbs-enterprise.sources
    log "Step 12 complete."
  else
    log "Step 12 skipped."
  fi
}

step_13() {
  if ask_run "Step 13: Update repos (apt update; apt policy; apt update)?"; then
    log "Running Step 13"
    apt update | tee -a "$LOG_FILE"
    apt policy | tee -a "$LOG_FILE"
    apt update | tee -a "$LOG_FILE"
    log "Step 13 complete."
  else
    log "Step 13 skipped."
  fi
}

run_step() {
  local n="$1"
  CUR_STEP="$n"
  save_state "$CUR_STEP"
  case "$n" in
    1) step_1 ;;
    2) step_2 ;;
    3) step_3 ;;
    4) step_4 ;;
    5) step_5 ;;
    6) step_6 ;;
    7) step_7 ;;  # keep numbering flow; run 6b explicitly in loop below
    8) step_8 ;;
    9) step_9 ;;
    10) step_10 ;;
    11) step_11 ;;
    12) step_12 ;;
    13) step_13 ;;
    *) return 1 ;;
  esac
  return 0
}

# --- main ------------------------------------------------------------------
need_root
log "=== PBS Upgrade 8 -> 9 interactive runner starting ==="
START_STEP="$(load_state)"

# If the last saved step is "10" it means we saved before reboot.
if [[ "$START_STEP" =~ ^[0-9]+$ ]]; then
  log "Resuming at step $START_STEP (change by editing $STATE_FILE)."
else
  START_STEP="1"
  save_state "$START_STEP"
fi

# We need to insert the "Step 6 (checker again)" after step 6 and before step 7.
# We'll explicitly call step_6b when step==6 finished.
for (( s=START_STEP; s<=13; s++ )); do
  run_step "$s" || { log "Unknown step $s"; exit 1; }
  # Inject 6b right after 6
  if [[ "$s" -eq 6 ]]; then
    CUR_STEP="6b"
    save_state "7"   # next numeric step is 7 after 6b
    step_6b
  fi
  next=$(( s + 1 ))
  save_state "$next"
done

log "All steps completed. You can review the log at: $LOG_FILE"
rm -f "$STATE_FILE"
exit 0
