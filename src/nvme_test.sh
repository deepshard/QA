#!/usr/bin/env bash
# nvme_health_check.sh — Comprehensive NVMe health & performance verifier
set -euo pipefail

# ---------- Configuration ----------
DEV_BLOCK=$(nvme list | awk '$1 ~ /nvme.*n1/ {print $1;exit}')
DEV_CHAR=${DEV_BLOCK%n1}
TMPDIR=$(mktemp -d /tmp/nvme_health.XXXX)
TEST_TYPE="short"    # Use -e or --extended for extended test
TEST_MB=256         # Increased per-chunk size
CHUNKS=16           # Increased number of chunks
WARN_TEMP=70        # Warning temperature threshold (Celsius)
WARN_USED=80        # Warning percentage used threshold
MIN_SPEED=500       # Minimum MB/s write speed expected

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -e|--extended) TEST_TYPE="extended"; shift ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

# ---------- Functions ----------
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

warn() {
    log "⚠️  WARNING: $*"
}

fail() {
    log "❌ FAILED: $*"
    exit 1
}

# Cleanup on exit
cleanup() {
    local exit_code=$?
    rm -rf "$TMPDIR"
    if [ $exit_code -eq 0 ]; then
        log "✅ NVMe health check completed successfully"
    else
        log "❌ NVMe health check failed with code $exit_code"
    fi
    exit $exit_code
}
trap cleanup EXIT

log "Starting NVMe health check"

# ---------- Preflight Checks ----------
if [[ $EUID -ne 0 ]]; then
    log "Error: Please run as root"
    exit 1
fi

# Check required tools
for cmd in nvme smartctl dd sha256sum fstrim; do
    if ! command -v "$cmd" &>/dev/null; then
        fail "Required tool missing: $cmd"
    fi
done

if [[ -z "$DEV_BLOCK" ]]; then
    fail "No NVMe device found"
fi

log "Found NVMe device: $DEV_BLOCK"

# ---------- SMART Data Collection ----------
log "Collecting initial SMART data..."
smart_data=$(nvme smart-log "$DEV_CHAR")

# Extract and check critical values
temperature=$(echo "$smart_data" | awk '/Temperature:/ {print $3+0}')
used_percent=$(echo "$smart_data" | awk '/Percentage Used:/ {print $3+0}')
media_errors=$(echo "$smart_data" | awk '/Media and Data Integrity Errors:/ {print $6+0}')
power_cycles=$(echo "$smart_data" | awk '/Power Cycles:/ {print $3+0}')
unsafe_shutdowns=$(echo "$smart_data" | awk '/Unsafe Shutdowns:/ {print $3+0}')

# Check thresholds (only if values are non-empty)
if [ -n "$temperature" ] && [ "$temperature" -gt "$WARN_TEMP" ]; then
    warn "Temperature ${temperature}°C exceeds warning threshold"
fi

if [ -n "$used_percent" ] && [ "$used_percent" -gt "$WARN_USED" ]; then
    warn "Drive usage ${used_percent}% exceeds warning threshold"
fi

if [ -n "$media_errors" ] && [ "$media_errors" -gt 0 ]; then
    fail "Drive has $media_errors media errors"
fi

# Log all values, with N/A for empty ones
log "Drive Status:"
log "  - Temperature: ${temperature:-N/A}°C"
log "  - Used: ${used_percent:-N/A}%"
log "  - Power Cycles: ${power_cycles:-N/A}"
log "  - Unsafe Shutdowns: ${unsafe_shutdowns:-N/A}"

# ---------- Self Test ----------
if [ "$TEST_TYPE" = "extended" ]; then
    log "Starting extended NVMe self-test (may take 30+ minutes)..."
    test_code=2
else
    log "Starting short NVMe self-test (~2 minutes)..."
    test_code=1
fi

nvme device-self-test "$DEV_CHAR" -s "$test_code"

# Monitor progress
log "Monitoring self-test progress..."
while true; do
    sleep 5
    status=$(nvme self-test-log "$DEV_CHAR")
    op=$(echo "$status" | awk '/Current operation/ {print $NF}')
    progress=$(echo "$status" | awk '/Current Completion/ {print $NF}')
    
    if [ "$op" = "0" ]; then
        break
    fi
    log "  Progress: $progress%"
done

# Check self-test results
result=$(nvme self-test-log "$DEV_CHAR" | awk '/Operation Result/ {print $NF; exit}')
if [ "$result" != "0" ]; then
    fail "Self-test failed with result code $result"
fi
log "Self-test completed successfully"

# ---------- Performance Test ----------
log "Testing drive performance with $((CHUNKS*TEST_MB)) MiB random data..."
total_time_start=$(date +%s.%N)
total_bytes=0

for i in $(seq 1 "$CHUNKS"); do
    blk="$TMPDIR/blk$i"
    
    # Write test
    write_start=$(date +%s.%N)
    dd if=/dev/urandom of="$blk" bs=1M count="$TEST_MB" status=none
    write_end=$(date +%s.%N)
    write_time=$(echo "$write_end - $write_start" | bc)
    write_speed=$(echo "scale=2; $TEST_MB / $write_time" | bc)
    
    # Verify data
    sha256sum "$blk" | sha256sum -c - || fail "Data verification failed for chunk $i"
    
    total_bytes=$((total_bytes + TEST_MB*1024*1024))
    log "  ✓ Chunk $i verified (Write speed: ${write_speed} MB/s)"
    
    # Check if write speed is below threshold
    if (( $(echo "$write_speed < $MIN_SPEED" | bc -l) )); then
        warn "Write speed ${write_speed} MB/s below minimum threshold"
    fi
    
    rm -f "$blk"
done

# Calculate overall performance
total_time=$(echo "$(date +%s.%N) - $total_time_start" | bc)
avg_speed=$(echo "scale=2; ($total_bytes/1024/1024) / $total_time" | bc)
log "Average write speed: ${avg_speed} MB/s"

# ---------- TRIM Test ----------
if grep -q "0" "/sys/block/$(basename "$DEV_BLOCK")/queue/discard_granularity"; then
    log "TRIM not supported - skipping"
else
    log "Testing TRIM support..."
    fstrim -v / || warn "TRIM operation failed (non-fatal)"
fi

# ---------- Final SMART Check ----------
log "Collecting final SMART data..."
nvme smart-log "$DEV_CHAR"

log "✅ NVMe test completed successfully"

