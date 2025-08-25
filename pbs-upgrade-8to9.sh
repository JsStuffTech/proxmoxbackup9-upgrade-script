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
    df -h / | tee -a
