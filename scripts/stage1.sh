#!/usr/bin/env bash
# Stage 1: LED test script with log verification
set -euo pipefail

# Create logs directory in /home/truffle/qa/scripts/logs
mkdir -p "/home/truffle/qa/scripts/logs"

# CONFIGURATION
LED_WHITE="/home/truffle/qa/led_test/led_white"
LED_RED="/home/truffle/qa/led_test/led_red"
LED_GREEN="/home/truffle/qa/led_test/led_green"
LED_BLUE="/home/truffle/qa/led_test/led_blue"
LED_OFF="/home/truffle/qa/led_test/ledoff"
LED_PID=""

# Set absolute paths for log files
LOG_FILE="$(pwd)/logs/stage1_log.txt"

# Clear any existing log file
> "$LOG_FILE"

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
log "Stage 1 script started"

# PHASE: VERIFY STAGE 0 CHANGES
###############################
phase_start "Stage 0 Verification"

# Check the current power mode
CURRENT_MODE=$(nvpmodel -q | grep -v "NV Power Mode" | xargs)
if [ "$CURRENT_MODE" = "0" ]; then
  success "Power mode is confirmed to be MAXN (Mode 0)"
else
  fail "Power mode is not MAXN. Current mode: $CURRENT_MODE"
fi

# Check if SPI is enabled
if grep -q "^dtparam=spi=on" /boot/config.txt; then
  success "SPI is confirmed to be enabled"
else
  fail "SPI is not enabled in /boot/config.txt"
fi
#need to test the rootfs flash if APP name duplication happens with custom root size, it doent happen when root size isnt added
# # Verify EMMC partition label
# PARTITION_LABEL=$(sgdisk -p /dev/mmcblk0 | grep "APP_EMMC" | awk '{print $7}')
# if [ "$PARTITION_LABEL" = "APP_EMMC" ]; then
#   success "EMMC partition is correctly labeled as APP_EMMC"
# else
#   fail "EMMC partition is not correctly labeled (Expected: APP_EMMC, Got: $PARTITION_LABEL)"
# fi

# # Double check with lsblk
# LSBLK_VERIFY=$(lsblk -o NAME,PARTLABEL /dev/mmcblk0 | grep "APP_EMMC")
# if [ -n "$LSBLK_VERIFY" ]; then
#   success "EMMC partition label verified with lsblk"
# else
#   fail "EMMC partition label verification with lsblk failed"
# fi

# Verify hostname format
HOSTNAME=$(hostname)
if [[ "$HOSTNAME" =~ ^truffle-[0-9]{4}$ ]]; then
  success "Hostname is correctly formatted: $HOSTNAME"
else
  fail "Hostname is not in correct format: $HOSTNAME"
fi

# Verify Git configuration
GIT_EMAIL=$(git config --global user.email)
GIT_NAME=$(git config --global user.name)
if [ "$GIT_EMAIL" = "muhammad@deepshard.org" ]; then
  success "Git email is correctly configured"
else
  fail "Git email is not correctly configured (Expected: muhammad@deepshard.org, Got: $GIT_EMAIL)"
fi
if [ "$GIT_NAME" = "Abdullah" ]; then
  success "Git name is correctly configured"
else
  fail "Git name is not correctly configured (Expected: Abdullah, Got: $GIT_NAME)"
fi

# Verify QA repository
QA_DIR="/home/truffle/qa"
if [ -d "$QA_DIR/.git" ]; then
  success "QA repository exists at $QA_DIR"
  
  # Verify remote URL
  REMOTE_URL=$(cd "$QA_DIR" && git remote get-url origin)
  if [ "$REMOTE_URL" = "git@github.com:deepshard/QA.git" ]; then
    success "QA repository has correct remote URL"
  else
    fail "QA repository has incorrect remote URL (Expected: git@github.com:deepshard/QA.git, Got: $REMOTE_URL)"
  fi
else
  fail "QA repository not found at $QA_DIR"
fi

# Verify SSH and Avahi services
if systemctl is-active --quiet ssh; then
  success "SSH service is running"
else
  fail "SSH service is not running"
fi

if systemctl is-active --quiet avahi-daemon; then
  success "Avahi daemon is running"
else
  fail "Avahi daemon is not running"
fi

phase_end "Stage 0 Verification"

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



# Copy stage1 log - Do this last to ensure complete logs
log "Completing stage1 log for transfer"
phase_end "Log Transfer"

# Final copy of stage1 log
log "Stage 1 check completed successfully"

# This will be executed after the script completes
# We're using trap to ensure LED's are off
# Added for the final transfer of stage1_log.txt after all logging is complete
(
  sleep 1
  scp "$LOG_FILE" "${TARGET_USER}@${TARGET_IP}:${TARGET_DIR}/stage1_log.txt" 2>/dev/null
  # Clean up log files after transfer
  if [ $? -eq 0 ]; then
    echo "Log files transferred and cleaned up"
  fi
) &

exit 0
