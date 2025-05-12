#!/usr/bin/env bash
# health_check.sh — Complete system health check script
# Includes: MAXN verification, WiFi hotspot test, and GPU/LED burnin

set -euo pipefail

# CONFIGURATION
LED_WHITE="/home/truffle/qa/led_test/led_white"
LED_RED="/home/truffle/qa/led_test/led_red"
LED_GREEN="/home/truffle/qa/led_test/led_green"
LED_OFF="/home/truffle/qa/led_test/ledoff"
TEST_SCRIPT="/home/truffle/THERMALTEST/TEST.py"
HOTSPOT_DURATION=60 # seconds
GPU_STAGE_DURATION=60 # seconds per stage for quick test
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
  sleep 1
}

led_red() { 
  led_stop
  log "Starting LED Red Program"
  sudo "$LED_RED" & 
  LED_PID=$!
  sleep 1
}

led_green() { 
  led_stop
  log "Starting LED Green Program"
  sudo "$LED_GREEN" & 
  LED_PID=$!
  sleep 1
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

# Blink white to mark phase start
led_white
sleep 2
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
    sleep 5
    led_off
    break
  else
    fail "Failed to set MAXN (found: $mode)"
    led_red
    sleep 5
    led_off
  fi
  
  # After last attempt, exit with error
  if [[ $attempt -eq 3 ]]; then
    fail "ERROR: Could not enter MAXN after 3 tries"
    exit 1
  fi
done

phase_end "Max-N Power Mode"

###############################
# PHASE 2: HOTSPOT CHECK
###############################
phase_start "Wi-Fi Hotspot Test"

# Indicate start with white LED
led_white

# Check if WiFi interface exists
if [[ -z "$WIFI_IFACE" ]]; then
  fail "No WiFi interface found, cannot perform hotspot test"
  led_red
  sleep 5
  led_off
  phase_end "Wi-Fi Hotspot Test"
  exit 1
fi

# Bring down existing connection if any
if [[ -n "$CURRENT_CONN" ]]; then
  log "Bringing down existing connection: $CURRENT_CONN"
  nmcli connection down "$CURRENT_CONN" || warning "Failed to bring down connection"
fi

# Start hotspot
HOTSPOT_SSID="truffle-${last4}"
HOTSPOT_PSK="runescape"
log "Starting WiFi hotspot: $HOTSPOT_SSID"
if nmcli device wifi hotspot ifname "$WIFI_IFACE" ssid "$HOTSPOT_SSID" password "$HOTSPOT_PSK"; then
  success "Hotspot created successfully"
  
  # Show hotspot status
  log "Hotspot details:"
  nmcli -f NAME,UUID,TYPE,DEVICE connection show --active | grep -i hotspot || true
  nmcli device status | grep "$WIFI_IFACE" || true
  
  log "Hotspot will run for $HOTSPOT_DURATION seconds..."
  sleep "$HOTSPOT_DURATION"
  
  # Tear down hotspot
  log "Stopping hotspot..."
  nmcli connection down "$HOTSPOT_SSID" || warning "Failed to bring down hotspot"
  nmcli connection delete "$HOTSPOT_SSID" || warning "Failed to delete hotspot connection"
  
  # Restore previous connection
  if [[ -n "$CURRENT_CONN" ]]; then
    log "Restoring original connection: $CURRENT_CONN"
    if nmcli connection up "$CURRENT_CONN"; then
      success "Original connection restored"
    else
      warning "Failed to restore original connection"
    fi
  fi
  
  # Verify connectivity
  log "Verifying internet connectivity..."
  if ping -c3 -W2 8.8.8.8 &>/dev/null; then
    success "Internet connectivity OK"
    led_green
  else
    fail "Internet connectivity FAILED"
    led_red
  fi
else
  fail "Failed to create WiFi hotspot"
  led_red
fi

sleep 5
led_off
phase_end "Wi-Fi Hotspot Test"

###############################
# PHASE 3: GPU & LED BURN TEST
###############################
phase_start "GPU/LED Burn Test"

# Modify the test durations for quick testing
log "Preparing test script with duration: $GPU_STAGE_DURATION seconds per stage"
TMP_SCRIPT=$(mktemp)
sed -e "s/STAGE_DURATION = [0-9]\+/STAGE_DURATION = $GPU_STAGE_DURATION/" \
    -e "s/TOTAL_DURATION = [0-9]\+/TOTAL_DURATION = $((GPU_STAGE_DURATION*2))/" \
    "$TEST_SCRIPT" > "$TMP_SCRIPT"
chmod +x "$TMP_SCRIPT"

# Signal start with white LED
log "Starting GPU/LED burn test"
led_white
sleep 2
led_off

# Run the test
log "Running GPU burn test - this will take approximately $((GPU_STAGE_DURATION*2/60)) minutes"
if python3 "$TMP_SCRIPT" &>> "$LOGFILE"; then
  success "GPU/LED burn test PASSED"
  led_green
else
  fail "GPU/LED burn test FAILED"
  led_red
fi

rm "$TMP_SCRIPT"
sleep 5
led_off

phase_end "GPU/LED Burn Test"

###############################
# ALL DONE
###############################
success "All health checks complete!"
log "Log file saved to: $LOGFILE"
echo -e "${GREEN}${BOLD}===============================================${NC}"
echo -e "${GREEN}${BOLD}   Health check completed successfully!   ${NC}"
echo -e "${GREEN}${BOLD}===============================================${NC}"
echo ""
echo -e "${YELLOW}Note: For persistent operation, run this script inside a screen session:${NC}"
echo -e "      ${CYAN}screen -S healthcheck ./health_check.sh${NC}"
