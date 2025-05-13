#!/usr/bin/env bash
# remove_autostart.sh - Removes health check and LED test autostart services
set -euo pipefail

echo "=== Removing autostart services ==="

# Define paths
HEALTH_CHECK_SERVICE_PATH="/etc/systemd/system/health-check.service"
STARTUP_SCRIPT_PATH="/home/truffle/startup.sh"
SPI_TEST_SERVICE_PATH="/etc/systemd/system/spi-test.service"
SPI_TEST_SCRIPT_PATH="/usr/local/sbin/spi-led-gpu-test.sh"
SPI_TEST_DONE_FILE="/var/lib/spi-test.done"

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "Please run as root (sudo)"
    exit 1
fi

# Function to log steps
log() {
    echo ">>> $1"
}

# Function to stop and remove a service
remove_service() {
    local service_name="$1"
    local service_file="$2"
    
    log "Processing $service_name..."
    # Stop the service if running
    systemctl stop "$service_name" 2>/dev/null || true
    # Disable the service
    systemctl disable "$service_name" 2>/dev/null || true
    # Remove the service file
    if [ -f "$service_file" ]; then
        log "Removing service file: $service_file"
        rm -f "$service_file"
    fi
}

# 1. Remove health-check service
remove_service "health-check.service" "$HEALTH_CHECK_SERVICE_PATH"

# 2. Remove spi-test service
remove_service "spi-test.service" "$SPI_TEST_SERVICE_PATH"

# 3. Remove related scripts and files
if [ -f "$STARTUP_SCRIPT_PATH" ]; then
    log "Removing startup script..."
    rm -f "$STARTUP_SCRIPT_PATH"
fi

if [ -f "$SPI_TEST_SCRIPT_PATH" ]; then
    log "Removing SPI test script..."
    rm -f "$SPI_TEST_SCRIPT_PATH"
fi

if [ -f "$SPI_TEST_DONE_FILE" ]; then
    log "Removing SPI test done file..."
    rm -f "$SPI_TEST_DONE_FILE"
fi

# 4. Kill any running LED or health check processes
log "Killing any running LED or health check processes..."
for pid in $(pgrep -f "led_white|led_green|led_red|health_check.sh|spi-led-gpu-test.sh" 2>/dev/null || true); do
    kill -9 $pid 2>/dev/null || true
done

# 5. Turn off LEDs for good measure
if [ -f "/home/truffle/qa/led_test/ledoff" ]; then
    log "Turning off LEDs..."
    sudo "/home/truffle/qa/led_test/ledoff"
fi

# 6. Reload systemd daemon
log "Reloading systemd daemon..."
systemctl daemon-reload

echo "=== Cleanup complete! ==="
echo "The following services have been removed:"
echo "  - health-check service"
echo "  - spi-test service (LED animation on boot)"
echo "You may need to reboot the system for all changes to take effect." 