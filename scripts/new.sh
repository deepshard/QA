#!/usr/bin/env bash
# health_check.sh — Complete system health check script
# Includes: MAXN verification, WiFi hotspot test, and GPU/LED burnin

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
HOTSPOT_DURATION=60 # seconds
LOGFILE="$HOME/healthcheck_$(date +%Y%m%d_%H%M%S).log"

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
  sleep 30
  led_stop
}

led_off() { 
  led_stop
}

# Cleanup handler for script termination
cleanup() {
  warning "Cleaning up..."
  led_off
  exit 0
}
trap cleanup EXIT INT TERM

# Get last-4 of serial for hostname/SSID
log "Getting device serial number"
serial=$(tr -d '\0' </proc/device-tree/serial-number)
last4=${serial: -4}
log "Device serial ends with: $last4"

# Save current Wi-Fi connection
log "Checking current WiFi connection"
WIFI_IFACE=$(nmcli -t -f DEVICE,TYPE device status | awk -F: '$2=="wifi"{print $1; exit}')
if [[ -z "$WIFI_IFACE" ]]; then
  warning "No WiFi interface found"
  CURRENT_CONN=""
else
  CURRENT_CONN=$(nmcli -t -f NAME,DEVICE connection show --active | awk -F: -v dev="$WIFI_IFACE" '$2==dev{print $1}')
  if [[ -n "$CURRENT_CONN" ]]; then
    log "Current active WiFi: $CURRENT_CONN on $WIFI_IFACE"
  else
    log "WiFi interface $WIFI_IFACE found but no active connection"
  fi
fi

###############################
# PHASE 1: MAX-N POWER MODE
###############################
phase_start "Max-N Power Mode"
led_white
led_red
led_blue
led_green
led_states
sleep 2
# Blink white to mark phase start
led_white
led_off

# Try setting MAXN up to 3 times
for attempt in 1 2 3; do
  log "Attempt $attempt: Setting MAXN power mode"
  sudo nvpmodel -m 0
  
  # Check power mode
  mode=$(sudo nvpmodel -q 2>&1 | awk -F': ' '/NV Power Mode/{print $2}')
  if [[ "$mode" == "MAXN" ]]; then
    success "MAXN power mode engaged"
    # Lock clocks to max
    sudo jetson_clocks
    success "Jetson clocks applied"
    led_green
    break
  else
    fail "Failed to set MAXN (found: $mode)"
    led_red
  fi
  
  # After last attempt, exit with error
  if [[ $attempt -eq 3 ]]; then
    fail "ERROR: Could not enter MAXN after 3 tries"
    exit 1
  fi
done

phase_end "Max-N Power Mode"



phase_start "GPU/CPU burn"
led_white
sleep 2
led_off

led_white
sleep 2
led_off

sudo python3 "$GPU_BURN_SCRIPT" --stage-one 2 --stage-two 2

led_off
sleep 2
led_white
phase_end "GPU/CPU burn"

echo "starting nvme health"
led_blue
led_green
sudo "$NVME_HEALTH_SCRIPT"
led_off
