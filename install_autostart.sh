#!/usr/bin/env bash
# install_autostart.sh - Sets up health check to run on boot
set -euo pipefail

echo "=== Setting up health check autostart on boot ==="

# Define paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
HEALTH_CHECK_PATH="$SCRIPT_DIR/health_check.sh"
STARTUP_SCRIPT_PATH="/home/truffle/startup.sh"
SERVICE_FILE_PATH="/etc/systemd/system/health-check.service"

# Make sure the health check script exists
if [[ ! -f "$HEALTH_CHECK_PATH" ]]; then
    echo "ERROR: health_check.sh not found at $HEALTH_CHECK_PATH"
    echo "Please run this script from the directory containing health_check.sh"
    exit 1
fi

echo "1. Ensuring health_check.sh is executable"
chmod +x "$HEALTH_CHECK_PATH"

echo "2. Creating startup script at $STARTUP_SCRIPT_PATH"
cat > "$STARTUP_SCRIPT_PATH" << 'EOF'
#!/usr/bin/env bash
# startup.sh - Handles LED indicators during boot and launches health check
set -euo pipefail

# Paths to LED commands
LED_WHITE="/home/truffle/led_renderer_og/led_white"
LED_GREEN="/home/truffle/led_renderer_og/led_green"
LED_OFF="/home/truffle/led_renderer_og/ledoff"
HEALTH_CHECK="/home/truffle/qa/health_check.sh"

# Function to kill any running LED processes and turn LEDs off
kill_led_processes() {
    # Find any running LED processes and kill them
    for pid in $(pgrep -f "led_white|led_green|led_red" 2>/dev/null || true); do
        kill -9 $pid 2>/dev/null || true
    done
    # Run LED OFF command
    sudo "$LED_OFF" || true
    sleep 1
}

# Log to both console and system log
log() {
    echo "$@"
    logger -t "startup.sh" "$@"
}

# Start with WHITE LED to indicate system is booting
log "System starting up - turning on WHITE LED"
kill_led_processes
sudo "$LED_WHITE" &
WHITE_PID=$!

# Wait for NetworkManager to be fully ready (helps ensure network is up)
log "Waiting for NetworkManager to be fully ready..."
sleep 15

# Switch to GREEN LED to indicate health check is about to start
log "System ready - turning on GREEN LED to indicate health check will start soon"
kill -9 $WHITE_PID 2>/dev/null || true
kill_led_processes
sudo "$LED_GREEN" &
GREEN_PID=$!

# Wait 5 seconds with GREEN LED
log "Waiting 5 seconds before starting health check..."
sleep 5

# Turn off LED before starting health check
log "Turning off LEDs before starting health check"
kill -9 $GREEN_PID 2>/dev/null || true
kill_led_processes

# Start health check in a screen session for persistence
log "Starting health check script in screen session"
# Create detached screen session running the health check
sudo -u truffle bash -c "screen -dmS healthcheck bash -c 'cd /home/truffle/qa && ./health_check.sh; exec bash'"

log "Startup process complete"
EOF

echo "3. Making startup script executable"
chmod +x "$STARTUP_SCRIPT_PATH"

echo "4. Creating systemd service at $SERVICE_FILE_PATH"
cat > "$SERVICE_FILE_PATH" << 'EOF'
[Unit]
Description=Truffle Health Check Service
After=network.target NetworkManager.service
Wants=network.target NetworkManager.service

[Service]
Type=simple
User=truffle
Group=truffle
ExecStart=/home/truffle/startup.sh
StandardOutput=journal
StandardError=journal
Restart=no

[Install]
WantedBy=multi-user.target
EOF

echo "5. Reloading systemd daemon"
systemctl daemon-reload

echo "6. Enabling service to start on boot"
systemctl enable health-check.service

echo "7. Installing screen if not already installed"
if ! command -v screen &>/dev/null; then
    echo "Screen not found, installing..."
    apt-get update && apt-get install -y screen
fi

echo "=== Setup complete! ==="
echo "The health check will now run automatically on system boot."
echo "You can also start it manually with: systemctl start health-check"
echo "View logs with: journalctl -u health-check"
echo ""
echo "To test now without rebooting, run: systemctl start health-check"
