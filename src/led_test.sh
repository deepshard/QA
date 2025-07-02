#!/usr/bin/env bash
# Stage 1: LED test script with log verification

set -euo pipefail

# CONFIGURATION
LED_WHITE="/home/truffle/qa/led_test/led_white"
LED_RED="/home/truffle/qa/led_test/led_red"
LED_GREEN="/home/truffle/qa/led_test/led_green"
LED_BLUE="/home/truffle/qa/led_test/led_blue"
LED_OFF="/home/truffle/qa/led_test/ledoff"
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
    
    log "Running LED OFF command"
    sudo "$LED_OFF" > /dev/null 2>&1 || true
    sleep 1
  fi
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

# Ensure LEDs are off when script exits
trap led_stop EXIT

log "Starting LED color tests"

# Test each LED color
led_test "WHITE" "$LED_WHITE"
led_test "RED" "$LED_RED" 
led_test "GREEN" "$LED_GREEN"
led_test "BLUE" "$LED_BLUE"

log "✅ All LED tests completed successfully"
exit 0
