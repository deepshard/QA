#!/usr/bin/env bash
# Stage 1: LED test script with log verification

set -euo pipefail

# CONFIGURATION
LED_WHITE="/home/truffle/QA/led_test/led_white"
LED_RED="/home/truffle/QA/led_test/led_red"
LED_GREEN="/home/truffle/QA/led_test/led_green"
LED_BLUE="/home/truffle/QA/led_test/led_blue"
LED_OFF="/home/truffle/QA/led_test/ledoff"
LED_PID=""
DURATION=3

# Logging function
log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

log "LED test started"

# LED control functions
led_stop() {
  if [[ -n "$LED_PID" ]]; then
    log "Stopping LED process (PID: $LED_PID)"
    kill -9 $LED_PID >/dev/null 2>&1 || true
    wait $LED_PID 2>/dev/null || true
    LED_PID=""
  fi
  
  # Kill any remaining LED processes by name
  log "Killing any remaining LED processes"
  sudo pkill -f "led_white" >/dev/null 2>&1 || true
  sudo pkill -f "led_red" >/dev/null 2>&1 || true
  sudo pkill -f "led_green" >/dev/null 2>&1 || true
  sudo pkill -f "led_blue" >/dev/null 2>&1 || true
  sudo pkill -f "ledoff" >/dev/null 2>&1 || true
  sudo pkill -f "led_state_test" >/dev/null 2>&1 || true
  
  log "Running LED OFF command"
  sudo "$LED_OFF" > /dev/null 2>&1 || true
  sleep 1
}

led_test() {
  local color=$1
  local led_cmd=$2
  
  led_stop
  log "Testing $color LED - Duration: ${DURATION}s"
  sudo "$led_cmd" > /dev/null 2>&1 & 
  LED_PID=$!
  sleep $DURATION
  led_stop
  log "$color LED test completed"
}

# Comprehensive cleanup function
cleanup_all_leds() {
  log "=== FINAL CLEANUP: Terminating all LED processes ==="
  
  # Kill the tracked PID first
  if [[ -n "$LED_PID" ]]; then
    log "Killing tracked LED process (PID: $LED_PID)"
    kill -9 $LED_PID >/dev/null 2>&1 || true
    wait $LED_PID 2>/dev/null || true
    LED_PID=""
  fi
  
  # Kill all LED processes by name (more aggressive)
  log "Killing all LED processes by name..."
  sudo pkill -9 -f "led_white" >/dev/null 2>&1 || true
  sudo pkill -9 -f "led_red" >/dev/null 2>&1 || true
  sudo pkill -9 -f "led_green" >/dev/null 2>&1 || true
  sudo pkill -9 -f "led_blue" >/dev/null 2>&1 || true
  sudo pkill -9 -f "ledoff" >/dev/null 2>&1 || true
  sudo pkill -9 -f "led_state_test" >/dev/null 2>&1 || true
  
  # Give a moment for processes to terminate
  sleep 2
  
  # Final LED OFF command
  log "Final LED OFF command"
  sudo "$LED_OFF" > /dev/null 2>&1 || true
  sleep 1
  
  # Verify no LED processes remain
  remaining_procs=$(pgrep -f "led_" 2>/dev/null | wc -l)
  if [[ $remaining_procs -gt 0 ]]; then
    log "Warning: $remaining_procs LED processes may still be running"
    log "Remaining LED processes:"
    pgrep -fl "led_" 2>/dev/null || true
  else
    log "✅ All LED processes successfully terminated"
  fi
}

# Ensure LEDs are off when script exits
trap cleanup_all_leds EXIT

log "Starting LED color tests"

# Test each LED color
led_test "WHITE" "$LED_WHITE"
led_test "RED" "$LED_RED" 
led_test "GREEN" "$LED_GREEN"
led_test "BLUE" "$LED_BLUE"

log "✅ All LED tests completed successfully"
exit 0
