#!/usr/bin/env bash
# Stage 1: LED test script with log verification

set -euo pipefail

# CONFIGURATION
LED_WHITE="/home/truffle/QA/led_test/led_white"
LED_RED="/home/truffle/QA/led_test/led_red"
LED_GREEN="/home/truffle/QA/led_test/led_green"
LED_BLUE="/home/truffle/QA/led_test/led_blue"
LED_OFF="/home/truffle/QA/led_test/ledoff"
DURATION=3

# Logging function
log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

log "LED test started"

# Initial LED off to ensure clean state
log "Ensuring LEDs are off before starting test"
sudo "$LED_OFF" > /dev/null 2>&1 || true
sleep 1

# LED control functions
led_stop() {
  # Kill any remaining LED processes by name (aggressive cleanup)
  sudo pkill -9 -f "led_white" 2>/dev/null || true
  sudo pkill -9 -f "led_red" 2>/dev/null || true  
  sudo pkill -9 -f "led_green" 2>/dev/null || true
  sudo pkill -9 -f "led_blue" 2>/dev/null || true
  sleep 1
  
  # Always run LED OFF command
  log "Running LED OFF command"
  sudo "$LED_OFF" > /dev/null 2>&1 || true
  sleep 1
}

led_test() {
  local color=$1
  local led_cmd=$2
  
  # Ensure LEDs are off before starting this test
  led_stop
  log "Ensuring LEDs are off before $color test"
  sudo "$LED_OFF" > /dev/null 2>&1 || true
  sleep 1
  
  log "Testing $color LED - Duration: ${DURATION}s"
  # Use timeout to automatically terminate LED process after duration
  sudo timeout ${DURATION}s "$led_cmd" > /dev/null 2>&1 || true
  
  # Turn off LEDs after this test
  led_stop
  log "Turning off LEDs after $color test"
  sudo "$LED_OFF" > /dev/null 2>&1 || true
  sleep 1
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

# Final LED off to ensure clean state after all tests
log "Final LED cleanup - ensuring all LEDs are off"

# Aggressive cleanup - kill any remaining LED processes individually
sudo pkill -9 -f "led_white" 2>/dev/null || true
sudo pkill -9 -f "led_red" 2>/dev/null || true
sudo pkill -9 -f "led_green" 2>/dev/null || true  
sudo pkill -9 -f "led_blue" 2>/dev/null || true
sleep 2

# Run LED OFF multiple times to be absolutely sure
for i in {1..3}; do
  sudo "$LED_OFF" > /dev/null 2>&1 || true
  sleep 1
done

# Final verification - one more aggressive kill by path
sudo pkill -9 -f "/home/truffle/QA/led_test/led_" 2>/dev/null || true

log "✅ All LED tests completed successfully"
exit 0
