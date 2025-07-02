#!/bin/bash
# preflash.sh - Install all required packages for QA testing

# Check if running as root
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root (sudo)"
  exit 1
fi

echo "Installing required packages..."

# Update package list
apt-get update

# Install system packages
apt-get install -y \
  gdisk \
  openssh-server \
  avahi-daemon \
  sshpass \
  smartmontools \
  python3-pip \
  stress \
  screen

# Enable services
systemctl enable --now ssh avahi-daemon

# Install Python packages
pip3 install -U jetson-stats requests

# Create necessary directories
mkdir -p /home/truffle/qa_logs

echo "Package installation complete!"
