#!/bin/bash

# Check if running as root
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root (sudo)"
  exit 1
fi

# Variable to track if reboot is needed
REBOOT_NEEDED=false

# Check and enable SPI if not enabled
if ! grep -q "^dtparam=spi=on" /boot/config.txt; then
  echo "SPI not enabled. Enabling now..."
  sed -i 's/^#dtparam=spi=on/dtparam=spi=on/' /boot/config.txt 2>/dev/null || \
  echo "dtparam=spi=on" >> /boot/config.txt
  REBOOT_NEEDED=true
  echo "SPI enabled. Reboot will be required."
else
  echo "SPI already enabled."
fi

# Check current power mode
CURRENT_MODE=$(nvpmodel -q | grep "Current Mode" | awk '{print $4}')
if [ "$CURRENT_MODE" != "0" ]; then
  echo "Current power mode is not MAXN. Setting to MAXN..."
  # Send "yes" to the reboot prompt
  echo "yes" | nvpmodel -m 0
  REBOOT_NEEDED=true
  echo "Power mode set to MAXN. Reboot will be required."
else
  echo "Power mode is already MAXN."
fi

# Reboot if needed
if [ "$REBOOT_NEEDED" = true ]; then
  echo "Rebooting system in 5 seconds..."
  sleep 5
  reboot
else
  echo "No changes needed. Both SPI and MAXN are already enabled."
fi
