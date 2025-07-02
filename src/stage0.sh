#!/bin/bash
# Create logs directory in /home/truffle/qa/scripts/logs
mkdir -p "/home/truffle/qa/scripts/logs"

# Log file setup
LOG_FILE="/home/truffle/qa/scripts/logs/stage0_log.txt"
# Clear any existing log file
> "$LOG_FILE"

# Log function
log() {
  echo "$1"
  echo "$1" >> "$LOG_FILE"
}

# Verification function
verify() {
  if [ $? -eq 0 ]; then
    log "✅ Verification passed: $1"
    return 0
  else
    log "❌ Verification failed: $1"
    return 1
  fi
}

# Start logging
log "Stage 0 started"

# Check if running as root
if [ "$EUID" -ne 0 ]; then
  log "Please run as root (sudo)"
  exit 1
fi

# Variable to track if reboot is needed
REBOOT_NEEDED=false







