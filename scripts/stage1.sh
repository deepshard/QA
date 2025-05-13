#!/usr/bin/env bash
# Stage 0: LED test script
set -euo pipefail

# CONFIGURATION
LED_WHITE="/home/truffle/qa/led_test/led_white"
LED_RED="/home/truffle/qa/led_test/led_red"
LED_GREEN="/home/truffle/qa/led_test/led_green"
LED_BLUE="/home/truffle/qa/led_test/led_blue"
LED_OFF="/home/truffle/qa/led_test/ledoff"
LED_PID=""
LOG_FILE="/tmp/stage0_led_test_$(date '+%Y%m%d_%H%M%S').log"

# Logging and phase tracking functions
log() {
  local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $*"
  echo "$msg"
  echo "$msg" >> "$LOG_FILE"
}

phase_start() {
  log "==========================================="
  log "STARTING PHASE: $*"
  log "==========================================="
}

phase_end() {
  log "----------------------------------------"
  log "COMPLETED PHASE: $*"
  log "----------------------------------------"
}

success() {
  log "✅ SUCCESS: $*"
}

fail() {
  log "❌ ERROR: $*"
}

# LED control functions
led_stop() {
  if [[ -n "$LED_PID" ]]; then
    log "Stopping LED process (PID: $LED_PID)"
    kill -9 $LED_PID >/dev/null 2>&1 || true
    wait $LED_PID 2>/dev/null || true
    LED_PID=""
    
    log "Running LED OFF command"
    sudo "$LED_OFF" > /dev/null 2>> "$LOG_FILE" || true
    sleep 1
  fi
}

led_white() { 
  led_stop
  log "Starting LED White Program"
  sudo "$LED_WHITE" > /dev/null 2>> "$LOG_FILE" & 
  LED_PID=$!
  sleep 3
}

led_blue() {
  led_stop
  log "Starting LED Blue Program"
  sudo "$LED_BLUE" > /dev/null 2>> "$LOG_FILE" &
  LED_PID=$!
  sleep 3
}

led_red() { 
  led_stop
  log "Starting LED Red Program"
  sudo "$LED_RED" > /dev/null 2>> "$LOG_FILE" & 
  LED_PID=$!
  sleep 3
}

led_green() { 
  led_stop
  log "Starting LED Green Program"
  sudo "$LED_GREEN" > /dev/null 2>> "$LOG_FILE" & 
  LED_PID=$!
  sleep 3
}

led_off() { 
  led_stop
}

# Ensure LEDs are off when script exits
trap led_off EXIT

# Initialize log file
log "LED test script started"
log "Output from LED programs will be logged to $LOG_FILE"

# PHASE: LED TEST
###############################
phase_start "LED Test"
log "Testing all LED states"

log "Testing WHITE LED"
led_white
led_off

log "Testing RED LED"
led_red
led_off

log "Testing GREEN LED"
led_green
led_off

log "Testing BLUE LED"
led_blue
led_off

success "LED test completed"
phase_end "LED Test"

log "Stage 0 check completed successfully"
