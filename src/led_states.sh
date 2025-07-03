LED_WHITE="/home/truffle/QA/led_test/led_white"
LED_RED="/home/truffle/QA/led_test/led_red"
LED_GREEN="/home/truffle/QA/led_test/led_green"
LED_BLUE="/home/truffle/QA/led_test/led_blue"
LED_OFF="/home/truffle/QA/led_test/ledoff"
LED_STATES="/home/truffle/QA/led_test/led_state_test"



SCRIPTS_LOG_DIR="/home/truffle/qa_logs"




# UTILITIES
# Terminal colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Pretty logging function with dual output to terminal and log file
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


# Cleanup handler for script termination
cleanup() {
  warning "Cleaning up..."
  led_off
  
  # Log file is already in the correct directory, no need to copy
  log "Log saved to $LOGFILE"
  exit 0
}
trap cleanup EXIT INT TERM
