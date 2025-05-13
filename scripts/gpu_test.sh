#!/usr/bin/env bash
# GPU burn test script extracted from stage2.sh
set -euo pipefail

# Create logs directory
mkdir -p "/home/truffle/qa/scripts/logs"

# CONFIGURATION
LED_WHITE="/home/truffle/qa/led_test/led_white"
LED_RED="/home/truffle/qa/led_test/led_red"
LED_GREEN="/home/truffle/qa/led_test/led_green"
LED_OFF="/home/truffle/qa/led_test/ledoff"
GPU_BURN_SCRIPT="/home/truffle/qa/THERMALTEST/test.py"

# Log configuration
SCRIPTS_LOG_DIR="/home/truffle/qa/scripts/logs"
GPU_LOG_FILE="${SCRIPTS_LOG_DIR}/gpu_test_burn.log"
GPU_CSV_PATH="${SCRIPTS_LOG_DIR}/stage2_burn_log.csv"

# Terminal colors
GREEN='\033[0;32m'
RED='\033[0;31m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Utility functions
log() {
  local timestamp=$(date '+%F %T')
  echo -e "${CYAN}[${timestamp}]${NC} $*"
}

success() {
  echo -e "${GREEN}${BOLD}✓ $*${NC}"
}

fail() {
  echo -e "${RED}${BOLD}✗ $*${NC}"
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

led_off() { 
  led_stop
}

# Cleanup handler
cleanup() {
  log "Cleaning up..."
  led_off
  exit 0
}
trap cleanup EXIT INT TERM

# Start GPU Test
log "Starting GPU/CPU burn test"

# Clear the GPU log file
> "$GPU_LOG_FILE"

# Indicator that GPU test is starting
led_white
sleep 2
led_off

# Run GPU/CPU burn test
log "Running GPU/CPU burn test, logging to $GPU_LOG_FILE"

if sudo python3 "$GPU_BURN_SCRIPT" --stage-one 1 --stage-two 1 > >(tee -a "$GPU_LOG_FILE") 2> >(tee -a "$GPU_LOG_FILE" >&2); then
  success "GPU/CPU burn test completed successfully" | tee -a "$GPU_LOG_FILE"
  led_green
  sleep 3
else
  GPU_EXIT_CODE=$?
  fail "GPU/CPU burn test failed with exit code $GPU_EXIT_CODE" | tee -a "$GPU_LOG_FILE"
  led_red
  sleep 3
fi

led_off
log "Test completed. CSV data available at: $GPU_CSV_PATH"
