#!/usr/bin/env bash
# health_check.sh — Complete system health check script
# Includes: LED test, WiFi hotspot test, NVME health check, and GPU/CPU burn test

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
LOGFILE="$HOME/healthcheck_$(date +%Y%m%d_%H%M%S).log"
LOG_DIR="$HOME/$(hostname)_log"

# Log files for individual tests
HOTSPOT_LOG_FILE="${SCRIPTS_LOG_DIR}/stage2_hotspot_logs.txt"
NVME_LOG_FILE="${SCRIPTS_LOG_DIR}/stage2_nvme.log"
GPU_LOG_FILE="${SCRIPTS_LOG_DIR}/stage2_burn.log"

# Remote machine configuration
REMOTE_USER="truffle"
REMOTE_HOST="truffle.local"
REMOTE_BASE_DIR="/home/truffle/abd_work/truffle_QA"

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
  
  log "Transferring $source_file to ${REMOTE_USER}@${REMOTE_HOST}:${dest_file}"
  
  # Try with SSH keys first
  if scp -o BatchMode=yes -o ConnectTimeout=5 "$source_file" "${REMOTE_USER}@${REMOTE_HOST}:${dest_file}" 2>/dev/null; then
    success "File transferred successfully using SSH key"
  else
    log "SSH key transfer failed, trying with password..."
    # Check if sshpass is installed, if not try to install it
    if ! command -v sshpass &> /dev/null; then
      log "Installing sshpass..."
      sudo apt-get update -y && sudo apt-get install -y sshpass
    fi
    
    # Try with sshpass
    if command -v sshpass &> /dev/null && sshpass -p "$SSH_PASSWORD" scp "$source_file" "${REMOTE_USER}@${REMOTE_HOST}:${dest_file}"; then
      success "File transferred successfully using password"
    else
      fail "Failed to transfer file $source_file"
      led_red
      sleep 10
      return 1
    fi
  fi
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
mkdir -p "$LOG_DIR"
mkdir -p "$SCRIPTS_LOG_DIR"

# Cleanup handler for script termination
cleanup() {
  warning "Cleaning up..."
  led_off
  
  # Copy the log to the log directory
  cp "$LOGFILE" "$LOG_DIR/"
  log "Log saved to $LOG_DIR/$(basename "$LOGFILE")"
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
# Try with SSH key first
if ssh -o BatchMode=yes -o ConnectTimeout=5 "${REMOTE_USER}@${REMOTE_HOST}" "mkdir -p \"${REMOTE_DIR}\"" 2>/dev/null; then
  success "Remote directory created using SSH key"
else
  log "SSH key authentication failed, trying with password..."
  # Check if sshpass is installed
  if ! command -v sshpass &> /dev/null; then
    log "Installing sshpass..."
    sudo apt-get update -y && sudo apt-get install -y sshpass
  fi
  
  # Try with sshpass
  if command -v sshpass &> /dev/null && sshpass -p "$SSH_PASSWORD" ssh "${REMOTE_USER}@${REMOTE_HOST}" "mkdir -p \"${REMOTE_DIR}\""; then
    success "Remote directory created using password"
  else
    fail "Failed to create remote directory"
    led_red
    sleep 10
    # Continue anyway as other parts of the script might work
  fi
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
phase_start "LED Test"
log "Testing all LED states"
led_states
led_off
success "LED test completed"
phase_end "LED Test"

###############################
# PHASE 2: HOTSPOT TEST
###############################
phase_start "WiFi Hotspot Test"
# Indicator that hotspot test is starting
led_white
sleep 2
led_off

log "Starting WiFi hotspot test"

# Clear the hotspot log file
> "$HOTSPOT_LOG_FILE"

# Run hotspot script, capture ALL output to both main log and test-specific log file
log "Running hotspot test, logging to $HOTSPOT_LOG_FILE"
if "$HOTSPOT_SCRIPT" > >(tee -a "$HOTSPOT_LOG_FILE") 2> >(tee -a "$HOTSPOT_LOG_FILE" >&2); then
  success "Hotspot test completed successfully" | tee -a "$HOTSPOT_LOG_FILE"
  led_green
  sleep 3
else
  HOTSPOT_EXIT_CODE=$?
  fail "Hotspot test failed with exit code $HOTSPOT_EXIT_CODE" | tee -a "$HOTSPOT_LOG_FILE"
  led_red
  sleep 3
fi

# Transfer hotspot log to remote
log "Transferring hotspot log to remote"
scp_to_remote "$HOTSPOT_LOG_FILE" "${REMOTE_DIR}/$(basename "$HOTSPOT_LOG_FILE")"

led_off
phase_end "WiFi Hotspot Test"

###############################
# PHASE 3: NVME HEALTH CHECK
###############################
phase_start "NVME Health Check"
# Indicator that NVME test is starting
led_white
sleep 2
led_off

log "Starting NVME health check"

# Clear the NVME log file
> "$NVME_LOG_FILE"

# Run NVME health check script, capture all output to test-specific log file
log "Running NVME health check, logging to $NVME_LOG_FILE"
if sudo "$NVME_HEALTH_SCRIPT" > >(tee -a "$NVME_LOG_FILE") 2> >(tee -a "$NVME_LOG_FILE" >&2); then
  success "NVME health check completed successfully" | tee -a "$NVME_LOG_FILE"
  led_green
  sleep 3
else
  NVME_EXIT_CODE=$?
  fail "NVME health check failed with exit code $NVME_EXIT_CODE" | tee -a "$NVME_LOG_FILE"
  led_red
  sleep 3
fi

# Transfer NVME log to remote
log "Transferring NVME log to remote"
scp_to_remote "$NVME_LOG_FILE" "${REMOTE_DIR}/$(basename "$NVME_LOG_FILE")"

led_off
phase_end "NVME Health Check"

###############################
# PHASE 4: GPU/CPU BURN TEST
###############################
phase_start "GPU/CPU burn"
# Indicator that GPU test is starting
led_white
sleep 2
led_off

log "Starting GPU/CPU burn test"

# Clear the GPU log file
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

# Run GPU/CPU burn test, capture all output to test-specific log file
log "Running GPU/CPU burn test, logging to $GPU_LOG_FILE"

# Remove timestamp from the test.py CSV output by modifying the command
# This ensures we always write to the same filename
if sudo python3 "$GPU_BURN_SCRIPT" --stage-one 0.1 --stage-two 0.1 > >(tee -a "$GPU_LOG_FILE") 2> >(tee -a "$GPU_LOG_FILE" >&2); then
  success "GPU/CPU burn test completed successfully" | tee -a "$GPU_LOG_FILE"
  led_green
  sleep 3
else
  GPU_EXIT_CODE=$?
  fail "GPU/CPU burn test failed with exit code $GPU_EXIT_CODE" | tee -a "$GPU_LOG_FILE"
  led_red
  sleep 3
fi

# Kill the CSV transfer background process if it's still running
if kill -0 $CSV_TRANSFER_PID 2>/dev/null; then
  kill $CSV_TRANSFER_PID
  wait $CSV_TRANSFER_PID 2>/dev/null || true
fi
led_off
# Final transfer of GPU log and CSV
log "Transferring final GPU log and data to remote"
scp_to_remote "$GPU_LOG_FILE" "${REMOTE_DIR}/$(basename "$GPU_LOG_FILE")"
if [ -f "$GPU_CSV_PATH" ]; then
  # Final copy with .final suffix
  scp_to_remote "$GPU_CSV_PATH" "${GPU_CSV_REMOTE}.final"
fi

led_off
phase_end "GPU/CPU burn"

# All tests complete
log "All tests completed"
success "Health check complete!"

# Copy the main log to the log directory and remote
cp "$LOGFILE" "$LOG_DIR/"
log "Log saved to $LOG_DIR/$(basename "$LOGFILE")"
scp_to_remote "$LOGFILE" "${REMOTE_DIR}/stage2_main_$(date +%Y%m%d_%H%M%S).log"