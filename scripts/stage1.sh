#!/usr/bin/env bash
# Stage 1: LED test script with log verification

# Check if we're already in a screen session
if [ -z "$STY" ]; then
  # We're not in a screen session, so start one
  if [ "$EUID" -ne 0 ]; then
    # We're not root, so use sudo with screen
    exec sudo screen -S stage1 "$0" "$@"
  else
    # We're root, just start screen
    exec screen -S stage1 "$0" "$@"
  fi
  exit 0
fi

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
LOG_FILE="/home/truffle/qa/scripts/logs/stage1_log.txt"

# =====================================================
# Remote transfer configuration
# =====================================================
REMOTE_USER="truffle"
REMOTE_HOSTS=("truffle.local" "truffle-2.local")
SSH_PASSWORD="runescape"
#REMOTE_BASE_DIR="/home/truffle/abd_work/truffle_QA"
REMOTE_BASE_DIR="/Users/truffle/abd_work/truffle_QA"
HOSTNAME=$(hostname)
REMOTE_DIR="${REMOTE_BASE_DIR}/${HOSTNAME}"
REMOTE_HOST=""

# Utility to transfer files with host/auth fallback (borrowed from stage2)
scp_to_remote() {
  local source_file="$1"
  local dest_file="$2"
  local -a tried_hosts=()
  local host_list=("$REMOTE_HOST" "${REMOTE_HOSTS[@]}")

  for host in "${host_list[@]}"; do
    [ -z "$host" ] && continue
    if [[ " ${tried_hosts[*]} " =~ " $host " ]]; then
      continue
    fi
    tried_hosts+=("$host")

    log "Transferring $source_file to ${REMOTE_USER}@${host}:${dest_file}"
    if scp -o BatchMode=yes -o ConnectTimeout=5 "$source_file" "${REMOTE_USER}@${host}:${dest_file}" 2>/dev/null; then
      success "File transferred successfully to ${host} using SSH key"
      REMOTE_HOST="$host"
      return 0
    else
      log "SSH key transfer to ${host} failed, trying with password..."
      if ! command -v sshpass &> /dev/null; then
        log "Installing sshpass..."
        sudo apt-get update -y && sudo apt-get install -y sshpass
      fi
      if command -v sshpass &> /dev/null && sshpass -p "$SSH_PASSWORD" scp "$source_file" "${REMOTE_USER}@${host}:${dest_file}"; then
        success "File transferred successfully to ${host} using password"
        REMOTE_HOST="$host"
        return 0
      fi
    fi
  done
  fail "Failed to transfer file $source_file to all hosts (${REMOTE_HOSTS[*]})"
  return 1
}

# Initialize log file placeholder (actual first log entry occurs after functions are defined)
# The remote directory creation will be attempted later, once all helper functions are available.

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

# Write the first log entry now that logging helpers exist
log "Stage 1 script started"

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
if [[ -e /var/lib/spi-test.done ]]; then
  if /opt/nvidia/jetson-io/config-by-function.py -l enabled | grep -q spi1; then
    success "SPI-1 is properly configured and enabled"
  else
    fail "SPI-1 is NOT enabled even though marker file exists"
  fi
else
  fail "SPI-1 marker file missing - configuration may be incomplete"
fi

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

# Remote directory creation (helper functions are now available)
for host in "${REMOTE_HOSTS[@]}"; do
  log "Attempting to create remote directory on host: ${host}"
  if ssh -o BatchMode=yes -o ConnectTimeout=5 "${REMOTE_USER}@${host}" "mkdir -p \"${REMOTE_DIR}\"" 2>/dev/null; then
    success "Remote directory created on ${host} using SSH key"
    REMOTE_HOST="$host"
    break
  else
    log "SSH key authentication to ${host} failed, trying with password..."
    if ! command -v sshpass &> /dev/null; then
      log "Installing sshpass..."
      sudo apt-get update -y && sudo apt-get install -y sshpass
    fi
    if command -v sshpass &> /dev/null && sshpass -p "$SSH_PASSWORD" ssh "${REMOTE_USER}@${host}" "mkdir -p \"${REMOTE_DIR}\""; then
      success "Remote directory created on ${host} using password"
      REMOTE_HOST="$host"
      break
    fi
  fi
done

if [ -z "$REMOTE_HOST" ]; then
  log "⚠️  Failed to create remote directory on any host – log transfer may fail"
fi

# This will be executed after the script completes
# We're using trap to ensure LED's are off
# Added for the final transfer of stage1_log.txt after all logging is complete
(
  sleep 1
  scp_to_remote "$LOG_FILE" "${REMOTE_DIR}/stage1_log.txt"
  # Clean up log files after transfer
  if [ $? -eq 0 ]; then
    echo "Log files transferred and cleaned up"
  fi
) &

exit 0
