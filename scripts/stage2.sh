#!/usr/bin/env bash
# health_check.sh — Complete system health check script
# Includes: LED test, WiFi hotspot test, NVME health check, and GPU/CPU burn test

# Check if we're already in a screen session
if [ -z "$STY" ]; then
  # We're not in a screen session, so start one
  if [ "$EUID" -ne 0 ]; then
    # We're not root, so use sudo with screen
    exec sudo screen -S stage2 "$0" "$@"
  else
    # We're root, just start screen
    exec screen -S stage2 "$0" "$@"
  fi
  exit 0
fi

set -euo pipefail

# Create logs directory in /home/truffle/qa/scripts/logs
mkdir -p "/home/truffle/qa/scripts/logs"

# CONFIGURATION
LED_WHITE="/home/truffle/qa/led_test/led_white"
LED_RED="/home/truffle/qa/led_test/led_red"
LED_GREEN="/home/truffle/qa/led_test/led_green"
LED_BLUE="/home/truffle/qa/led_test/led_blue"
LED_OFF="/home/truffle/qa/led_test/ledoff"
LED_STATES="/home/truffle/qa/led_test/led_state_test"
GPU_BURN_SCRIPT="/home/truffle/qa/THERMALTEST/test.py"
NVME_HEALTH_SCRIPT="/home/truffle/qa/scripts/nvme_health_check.sh"
HOTSPOT_SCRIPT="/home/truffle/qa/scripts/launch_hotspot.sh"
HOTSPOT_DURATION=60 # seconds

# SSH Configuration
SSH_PASSWORD="runescape"

# Log configuration
SCRIPTS_LOG_DIR="/home/truffle/qa/scripts/logs"
LOGFILE="$SCRIPTS_LOG_DIR/healthcheck_$(date +%Y%m%d_%H%M%S).log"


# Log files for individual tests
HOTSPOT_LOG_FILE="${SCRIPTS_LOG_DIR}/stage2_hotspot_logs.txt"
NVME_LOG_FILE="${SCRIPTS_LOG_DIR}/stage2_nvme_log.txt"
GPU_LOG_FILE="${SCRIPTS_LOG_DIR}/stage2_burn_log.txt"

# Remote machine configuration
REMOTE_USER="truffle"

# List of possible mDNS hostnames to try (in order of preference)
REMOTE_HOSTS=("truffle.local" "truffle-2.local")
# Active hostname – will be updated dynamically once a working host is found
REMOTE_HOST="${REMOTE_HOSTS[0]}"
REMOTE_BASE_DIR="/Users/truffle/abd_work/truffle_QA"
#REMOTE_BASE_DIR="/home/truffle/abd_work/truffle_QA"

# Get hostname for remote directory
HOSTNAME=$(hostname)
REMOTE_DIR="${REMOTE_BASE_DIR}/${HOSTNAME}"

# UTILITIES
# Terminal colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Pretty logging function with dual output to terminal and log file
log() {
  local timestamp=$(date '+%F %T')
  echo -e "${CYAN}[${timestamp}]${NC} $*" | tee -a "$LOGFILE"
}

success() {
  echo -e "${GREEN}${BOLD}✓ $*${NC}" | tee -a "$LOGFILE"
}

fail() {
  echo -e "${RED}${BOLD}✗ $*${NC}" | tee -a "$LOGFILE"
}

warning() {
  echo -e "${YELLOW}${BOLD}! $*${NC}" | tee -a "$LOGFILE"
}

phase_start() {
  echo -e "\n${CYAN}${BOLD}=== PHASE: $* ===${NC}" | tee -a "$LOGFILE"
}

phase_end() {
  echo -e "${CYAN}${BOLD}=== DONE: $* ===${NC}\n" | tee -a "$LOGFILE"
}

# SCP function to transfer files to the remote machine
scp_to_remote() {
  local source_file="$1"
  local dest_file="$2"

  # Keep track of hosts already attempted during this call
  local -a tried_hosts=()

  # Prefer the last known working host first, then fall back to the full list
  local host_list=("$REMOTE_HOST" "${REMOTE_HOSTS[@]}")

  for host in "${host_list[@]}"; do
    # Skip empty or duplicate entries
    if [ -z "$host" ]; then
      continue
    fi
    if [[ " ${tried_hosts[*]} " =~ " $host " ]]; then
      continue
    fi
    tried_hosts+=("$host")

    log "Transferring $source_file to ${REMOTE_USER}@${host}:${dest_file}"
    # Try key-based auth first
    if scp -o BatchMode=yes -o ConnectTimeout=5 "$source_file" "${REMOTE_USER}@${host}:${dest_file}" 2>/dev/null; then
      success "File transferred successfully to ${host} using SSH key"
      REMOTE_HOST="$host"
      return 0
    else
      log "SSH key transfer to ${host} failed, trying with password..."
      # Ensure sshpass is available
      if ! command -v sshpass &> /dev/null; then
        log "Installing sshpass..."
        sudo apt-get update -y && sudo apt-get install -y sshpass
      fi

      if command -v sshpass &> /dev/null && sshpass -p "$SSH_PASSWORD" scp "$source_file" "${REMOTE_USER}@${host}:${dest_file}"; then
        success "File transferred successfully to ${host} using password"
        REMOTE_HOST="$host"
        return 0
      fi
    fi
  done

  # If we reach here, every host failed
  fail "Failed to transfer file $source_file to all hosts (${REMOTE_HOSTS[*]})"
  led_red
  sleep 10
  return 1
}

# LED functions with proper kill and cleanup
LED_PID=""
led_stop() {
  if [[ -n "$LED_PID" ]]; then
    log "Stopping LED process (PID: $LED_PID)"
    kill -9 $LED_PID >/dev/null 2>&1 || true
    wait $LED_PID 2>/dev/null || true
    LED_PID=""
    
    log "Running LED OFF command"
    sudo "$LED_OFF" || true
    sleep 1
  fi
}

led_white() { 
  led_stop
  log "Starting LED White Program"
  sudo "$LED_WHITE" & 
  LED_PID=$!
  sleep 5
  led_stop
}

led_blue() {
  led_stop
  log "Leds are blue"
  sudo "$LED_BLUE" &
  LED_PID=$!
  sleep 5
  led_stop
}

led_red() { 
  led_stop
  log "Starting LED Red Program"
  sudo "$LED_RED" & 
  LED_PID=$!
  sleep 5
  led_stop
}

led_green() { 
  led_stop
  log "Starting LED Green Program"
  sudo "$LED_GREEN" & 
  LED_PID=$!
  sleep 5
  led_stop
}

led_states() {
  led_stop
  log "Leds are showing all orb states"
  sudo "$LED_STATES" &
  LED_PID=$!
  sleep 10
  led_stop
}

led_off() { 
  led_stop
}

# Create log directories if they don't exist

mkdir -p "$SCRIPTS_LOG_DIR"

# Cleanup handler for script termination
cleanup() {
  warning "Cleaning up..."
  led_off
  
  # Log file is already in the correct directory, no need to copy
  log "Log saved to $LOGFILE"
  exit 0
}
trap cleanup EXIT INT TERM

# Get last-4 of serial for hostname/SSID
log "Getting device serial number"
serial=$(tr -d '\0' </proc/device-tree/serial-number)
last4=${serial: -4}
log "Device serial ends with: $last4"

# Setup remote directory and transfer existing logs
log "Setting up remote directory and transferring existing logs"

REMOTE_HOST=""  # Reset – will capture the first host that works
for host in "${REMOTE_HOSTS[@]}"; do
  log "Attempting to create remote directory on host: ${host}"
  if ssh -o BatchMode=yes -o ConnectTimeout=5 "${REMOTE_USER}@${host}" "mkdir -p \"${REMOTE_DIR}\"" 2>/dev/null; then
    success "Remote directory created on ${host} using SSH key"
    REMOTE_HOST="$host"
    break
  else
    log "SSH key authentication to ${host} failed, trying with password..."
    if ! command -v sshpass &> /dev/null; then
      log "Installing sshpass..."
      sudo apt-get update -y && sudo apt-get install -y sshpass
    fi
    if command -v sshpass &> /dev/null && sshpass -p "$SSH_PASSWORD" ssh "${REMOTE_USER}@${host}" "mkdir -p \"${REMOTE_DIR}\""; then
      success "Remote directory created on ${host} using password"
      REMOTE_HOST="$host"
      break
    fi
  fi
done

if [ -z "$REMOTE_HOST" ]; then
  fail "Failed to create remote directory on all hosts (${REMOTE_HOSTS[*]})"
  led_red
  sleep 10
  # Continue anyway; other parts of the script might still work
fi

# Transfer any existing log files
if [ -d "$SCRIPTS_LOG_DIR" ] && [ "$(ls -A "$SCRIPTS_LOG_DIR" 2>/dev/null)" ]; then
  log "Transferring existing log files to remote host"
  for file in "$SCRIPTS_LOG_DIR"/*; do
    scp_to_remote "$file" "${REMOTE_DIR}/$(basename "$file")"
  done
else
  log "No existing log files to transfer"
fi

###############################
# PHASE 1: LED TEST
###############################
# phase_start "LED Test"
# log "Testing all LED states"
# led_states
# led_off
# success "LED test completed"
# phase_end "LED Test"

#commenting out since hotspot is now in firstboot sceipt so if it doesnt work well know before qa
###############################
# PHASE 2: HOTSPOT TEST
###############################
# phase_start "WiFi Hotspot Test"
# # Indicator that hotspot test is starting
# led_white
# sleep 2
# led_off

# log "Starting WiFi hotspot test"

# # Clear the hotspot log file
# > "$HOTSPOT_LOG_FILE"

# # Run hotspot script, capture ALL output to both main log and test-specific log file
# log "Running hotspot test, logging to $HOTSPOT_LOG_FILE"
# if "$HOTSPOT_SCRIPT" > >(tee -a "$HOTSPOT_LOG_FILE") 2> >(tee -a "$HOTSPOT_LOG_FILE" >&2); then
#   success "Hotspot test completed successfully" | tee -a "$HOTSPOT_LOG_FILE"
#   led_green
#   sleep 3
# else
#   HOTSPOT_EXIT_CODE=$?
#   fail "Hotspot test failed with exit code $HOTSPOT_EXIT_CODE" | tee -a "$HOTSPOT_LOG_FILE"
#   led_red
#   sleep 3
# fi

# # Transfer hotspot log to remote
# log "Transferring hotspot log to remote"
# scp_to_remote "$HOTSPOT_LOG_FILE" "${REMOTE_DIR}/$(basename "$HOTSPOT_LOG_FILE")"

# led_off
# phase_end "WiFi Hotspot Test"

###############################
# PHASE 3-4: CONCURRENT NVME HEALTH CHECK AND GPU/CPU BURN TEST
###############################
phase_start "Concurrent NVME Health Check and GPU/CPU Burn Test"
# Indicator that tests are starting
led_white
sleep 2
led_off

log "Starting NVME health check and GPU/CPU burn test concurrently"

# Clear the log files
> "$NVME_LOG_FILE"
> "$GPU_LOG_FILE"

# CSV produced by test.py
GPU_CSV_PATH="/home/truffle/qa/scripts/logs/stage2_burn_log.csv"
# Always overwrite the same remote target so the latest data is easy to find
GPU_CSV_REMOTE="${REMOTE_DIR}/stage2_burn_log.csv"

# Start a background process to send CSV data every minute
MAIN_PID=$$
(
  while kill -0 "$MAIN_PID" 2>/dev/null; do
    if [ -f "$GPU_CSV_PATH" ]; then
      scp_to_remote "$GPU_CSV_PATH" "$GPU_CSV_REMOTE"
      log "Transferred GPU CSV at $(date)" >> "$GPU_LOG_FILE"
    fi
    sleep 60
  done
) &
CSV_TRANSFER_PID=$!

# Run NVME health check script in background
log "Running NVME health check in background, logging to $NVME_LOG_FILE"
(
  if sudo "$NVME_HEALTH_SCRIPT" --extended > >(tee -a "$NVME_LOG_FILE") 2> >(tee -a "$NVME_LOG_FILE" >&2); then
    success "NVME health check completed successfully" | tee -a "$NVME_LOG_FILE"
  else
    NVME_EXIT_CODE=$?
    fail "NVME health check failed with exit code $NVME_EXIT_CODE" | tee -a "$NVME_LOG_FILE"
  fi
) &
NVME_PID=$!

# Run GPU/CPU burn test in background
log "Running GPU/CPU burn test in background, logging to $GPU_LOG_FILE"
(
  if sudo python3 "$GPU_BURN_SCRIPT" --stage-one 1 --stage-two 1 > >(tee -a "$GPU_LOG_FILE") 2> >(tee -a "$GPU_LOG_FILE" >&2); then
    success "GPU/CPU burn test completed successfully" | tee -a "$GPU_LOG_FILE"
  else
    GPU_EXIT_CODE=$?
    fail "GPU/CPU burn test failed with exit code $GPU_EXIT_CODE" | tee -a "$GPU_LOG_FILE"
  fi
) &
GPU_PID=$!

# Wait for both tests to complete
log "Waiting for concurrent tests to complete..."
wait $NVME_PID
NVME_STATUS=$?
wait $GPU_PID
GPU_STATUS=$?

# Kill the CSV transfer background process if it's still running
if kill -0 $CSV_TRANSFER_PID 2>/dev/null; then
  kill $CSV_TRANSFER_PID
  wait $CSV_TRANSFER_PID 2>/dev/null || true
fi

# Set LED based on test results
if [ $NVME_STATUS -eq 0 ] && [ $GPU_STATUS -eq 0 ]; then
  led_green
  sleep 3
else
  led_red
  sleep 3
fi

# Transfer logs to remote
log "Transferring logs to remote"
scp_to_remote "$NVME_LOG_FILE" "${REMOTE_DIR}/$(basename "$NVME_LOG_FILE")"
scp_to_remote "$GPU_LOG_FILE" "${REMOTE_DIR}/$(basename "$GPU_LOG_FILE")"
if [ -f "$GPU_CSV_PATH" ]; then
  # Final copy with .final suffix
  scp_to_remote "$GPU_CSV_PATH" "${GPU_CSV_REMOTE}.final"
fi

led_off
phase_end "Concurrent NVME Health Check and GPU/CPU Burn Test"

########################################################
#the end of phases 3-4, dont ji=udge i write these so i can comment them out without fru=ying my brain looking for stuff
########################################################



# All tests complete
log "All tests completed"
success "Health check complete!"

# Log file is already in the correct directory, no need to copy
log "Log saved to $LOGFILE"
scp_to_remote "$LOGFILE" "${REMOTE_DIR}/stage2_main_$(date +%Y%m%d_%H%M%S).log"

# Fallback: if the transfer to the primary host failed, try the secondary host explicitly
if [ $? -ne 0 ]; then
  warning "Primary log transfer failed, retrying with secondary host truffle-2.local"
  original_host="$REMOTE_HOST"
  REMOTE_HOST="truffle-2.local"

  # Ensure the remote directory exists on the secondary host
  if ! ssh -o BatchMode=yes -o ConnectTimeout=5 "${REMOTE_USER}@${REMOTE_HOST}" "mkdir -p \"${REMOTE_DIR}\"" 2>/dev/null; then
    if command -v sshpass &> /dev/null; then
      sshpass -p "$SSH_PASSWORD" ssh "${REMOTE_USER}@${REMOTE_HOST}" "mkdir -p \"${REMOTE_DIR}\""
    fi
  fi

  # Retry the copy
  scp_to_remote "$LOGFILE" "${REMOTE_DIR}/stage2_main_$(date +%Y%m%d_%H%M%S).log"
  REMOTE_HOST="$original_host"
fi
