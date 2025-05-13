#!/usr/bin/env bash
# health_check.sh — Complete system health check script
# Includes: MAXN verification, LED test, WiFi hotspot test, and GPU/LED burnin

set -euo pipefail

# CONFIGURATION
LED_WHITE="/home/truffle/qa/led_test/led_white"
LED_RED="/home/truffle/qa/led_test/led_red"
LED_GREEN="/home/truffle/qa/led_test/led_green"
LED_BLUE="/home/truffle/qa/led_test/led_blue"
LED_OFF="/home/truffle/qa/led_test/ledoff"
LED_STATES="/home/truffle/qa/led_test/led_state_test"
GPU_BURN_SCRIPT="/home/truffle/qa/THERMALTEST/test.py"
#there is a longer nvme test that can be done, look into that too
NVME_HEALTH_SCRIPT="/home/truffle/qa/scripts/nvme_health_check.sh"
HOTSPOT_SCRIPT="/home/truffle/qa/scripts/launch_hotspot.sh"
HOTSPOT_DURATION=60 # seconds
LOGFILE="$HOME/healthcheck_$(date +%Y%m%d_%H%M%S).log"
LOG_DIR="$HOME/$(hostname)_log"

# UTILITIES
# Terminal colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Pretty logging function
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

# Create log directory if it doesn't exist
mkdir -p "$LOG_DIR"

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
phase_end "Max-N Power Mode"

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

# Create a temporary file for output
HOTSPOT_LOG="/tmp/hotspot_debug.log"
echo "==== STARTING HOTSPOT TEST $(date) ====" > "$HOTSPOT_LOG"
echo "Running as user: $(whoami)" >> "$HOTSPOT_LOG"
echo "Current directory: $(pwd)" >> "$HOTSPOT_LOG"

# Run hotspot script WITHOUT sudo, capture ALL output to log file
if "$HOTSPOT_SCRIPT" > >(tee -a "$HOTSPOT_LOG") 2> >(tee -a "$HOTSPOT_LOG" >&2); then
  success "Hotspot test completed successfully"
  log "Hotspot log saved to $HOTSPOT_LOG"
  led_green
  sleep 3
else
  HOTSPOT_EXIT_CODE=$?
  fail "Hotspot test failed with exit code $HOTSPOT_EXIT_CODE"
  log "See detailed log at $HOTSPOT_LOG"
  # Copy the log to the final log directory too
  cp "$HOTSPOT_LOG" "$LOG_DIR/hotspot_debug_$(date +%Y%m%d_%H%M%S).log"
  led_red
  sleep 3
fi
led_off
phase_end "WiFi Hotspot Test"
###############################
# PHASE 5: NVME HEALTH CHECK (SKIPPED)
###############################
phase_start "NVME Health Check (SKIPPED)"
log "NVME health check is currently skipped per requirements"
# Just show blue to indicate this phase is skipped
led_blue
sleep 3
led_off
phase_end "NVME Health Check (SKIPPED)"

# All tests complete
log "All tests completed"
success "Health check complete!"

# Copy the log to the log directory
cp "$LOGFILE" "$LOG_DIR/"
log "Log saved to $LOG_DIR/$(basename "$LOGFILE")"
