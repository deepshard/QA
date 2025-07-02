#!/bin/bash
# install_service.sh - Install QA Test Suite as a systemd service

# Check if running as root
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root (sudo)"
  exit 1
fi

echo "Installing QA Test Suite systemd service..."

# Copy service file to systemd directory
cp qa-test.service /etc/systemd/system/

# Reload systemd daemon to recognize new service
systemctl daemon-reload

# Enable the service to start on boot
systemctl enable qa-test.service

echo "✅ QA Test Service installed successfully!"
echo ""
echo "Service commands:"
echo "  Start now:    sudo systemctl start qa-test"
echo "  Stop:         sudo systemctl stop qa-test"
echo "  Check status: sudo systemctl status qa-test"
echo "  View logs:    sudo journalctl -u qa-test -f"
echo ""
echo "The service will automatically start on next boot."
echo "To start testing now, run: sudo systemctl start qa-test" 