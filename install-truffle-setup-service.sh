#!/bin/bash

# Install Truffle Setup Service
echo "Installing Truffle Setup Service..."

# Make sure stage0.sh is executable
chmod +x /home/truffle/QA/src/stage0.sh

# Copy service file to systemd directory
cp truffle-setup.service /etc/systemd/system/

# Reload systemd daemon
systemctl daemon-reload

# Enable the service to start on boot
systemctl enable truffle-setup.service

# Show service status
systemctl status truffle-setup.service

echo "✅ Truffle Setup Service installed and enabled!"
echo "The service will run stage0.sh on every boot to configure the system."
echo "You can manually start it with: sudo systemctl start truffle-setup.service"
echo "Check logs with: sudo journalctl -u truffle-setup.service" 