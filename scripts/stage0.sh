#!/bin/bash
# Create logs directory in /home/truffle/qa/scripts/logs
mkdir -p "/home/truffle/qa/scripts/logs"

# Log file setup
LOG_FILE="/home/truffle/qa/scripts/logs/stage0_log.txt"
# Clear any existing log file
> "$LOG_FILE"

# Log function
log() {
  echo "$1"
  echo "$1" >> "$LOG_FILE"
}

# Verification function
verify() {
  if [ $? -eq 0 ]; then
    log "✅ Verification passed: $1"
    return 0
  else
    log "❌ Verification failed: $1"
    return 1
  fi
}

# Start logging
log "Stage 0 started"

# Check if running as root
if [ "$EUID" -ne 0 ]; then
  log "Please run as root (sudo)"
  exit 1
fi

# Variable to track if reboot is needed
REBOOT_NEEDED=false

########################################
# PHASE 1: Package Installation
########################################
log "Starting package installation phase"

# Check and install gdisk
if ! command -v gdisk &> /dev/null; then
  log "Installing gdisk..."
  apt-get update && apt-get install -y gdisk
  # Verify gdisk installation
  if command -v gdisk &> /dev/null; then
    verify "gdisk installation successful"
  else
    log "❌ Failed to install gdisk"
    exit 1
  fi
else
  log "gdisk is already installed"
fi

# Install SSH and Avahi
if ! systemctl is-active --quiet ssh || ! systemctl is-active --quiet avahi-daemon; then
  log "Installing and configuring SSH and Avahi..."
  apt-get update && apt-get install -y openssh-server avahi-daemon
  systemctl enable --now ssh avahi-daemon
  
  # Verify services are running
  if systemctl is-active --quiet ssh && systemctl is-active --quiet avahi-daemon; then
    verify "SSH and Avahi services are running"
  else
    log "❌ Failed to start SSH or Avahi services"
  fi
else
  log "SSH and Avahi are already installed and running"
fi

########################################
# PHASE 2: Hostname Setup
########################################
log "Starting hostname setup phase"

# Get last 4 digits of serial number and set hostname
SER=$(tr -cd '0-9' </proc/device-tree/serial-number)
LAST=${SER: -4}
NEW_HOSTNAME="truffle-${LAST}"
CURRENT_HOSTNAME=$(hostname)

if [ "$CURRENT_HOSTNAME" != "$NEW_HOSTNAME" ]; then
  log "Setting hostname to $NEW_HOSTNAME..."
  hostnamectl set-hostname "$NEW_HOSTNAME"
  echo "$NEW_HOSTNAME" > /etc/hostname
  sed -i "s/127\\.0\\.1\\.1.*/127.0.1.1\t$NEW_HOSTNAME/" /etc/hosts
  systemctl restart avahi-daemon
  
  # Verify hostname change
  VERIFY_HOSTNAME=$(hostname)
  if [ "$VERIFY_HOSTNAME" = "$NEW_HOSTNAME" ]; then
    verify "Hostname updated to $NEW_HOSTNAME"
  else
    log "❌ Hostname verification failed"
  fi
else
  log "Hostname is already correctly set"
fi

#add later
########################################
# PHASE 3: EMMC Partition Renaming
########################################
# log "Starting EMMC partition renaming phase"

# # Check current partition label
# CURRENT_LABEL=$(sgdisk -p /dev/mmcblk0 | grep "APP" | awk '{print $7}')
# if [ "$CURRENT_LABEL" != "APP_EMMC" ]; then
#   log "Changing partition label from APP to APP_EMMC..."
#   sgdisk --change-name=1:APP_EMMC /dev/mmcblk0
#   partprobe /dev/mmcblk0
  
#   # Verify partition rename
#   NEW_LABEL=$(sgdisk -p /dev/mmcblk0 | grep "APP_EMMC" | awk '{print $7}')
#   if [ "$NEW_LABEL" = "APP_EMMC" ]; then
#     verify "Partition successfully renamed to APP_EMMC"
#   else
#     log "❌ Partition rename verification failed"
#   fi
  
#   # Additional verification using lsblk
#   LSBLK_VERIFY=$(lsblk -o NAME,PARTLABEL /dev/mmcblk0 | grep "APP_EMMC")
#   if [ -n "$LSBLK_VERIFY" ]; then
#     verify "Partition label verified with lsblk"
#   else
#     log "❌ Partition label verification with lsblk failed"
#   fi
# else
#   log "Partition label is already APP_EMMC"
# fi

########################################
# PHASE 4: Git Configuration
########################################
log "Starting Git configuration phase"

# Configure Git globally if not already configured
CURRENT_GIT_EMAIL=$(git config --global user.email || echo "")
CURRENT_GIT_NAME=$(git config --global user.name || echo "")

if [ "$CURRENT_GIT_EMAIL" != "muhammad@deepshard.org" ] || [ "$CURRENT_GIT_NAME" != "Abdullah" ]; then
  log "Configuring Git globally..."
  git config --global user.email "muhammad@deepshard.org"
  git config --global user.name "Abdullah"
  
  # Verify Git configuration
  NEW_EMAIL=$(git config --global user.email)
  NEW_NAME=$(git config --global user.name)
  if [ "$NEW_EMAIL" = "muhammad@deepshard.org" ] && [ "$NEW_NAME" = "Abdullah" ]; then
    verify "Git configuration updated successfully"
  else
    log "❌ Git configuration verification failed"
  fi
else
  log "Git is already configured correctly"
fi

########################################
# PHASE 5: Repository Setup
########################################
log "Starting repository setup phase"

QA_DIR="/home/truffle/qa"
if [ ! -d "$QA_DIR/.git" ]; then
  log "Cloning QA repository..."
  # Remove existing qa directory if it exists
  rm -rf "$QA_DIR"
  
  # Ensure the parent directory exists and has correct permissions
  mkdir -p /home/truffle
  chown truffle:truffle /home/truffle
  
  # Clone the repository as the truffle user (simplified approach)
  su - truffle -c "git clone git@github.com:deepshard/QA.git $QA_DIR"
  
  # Check the clone result and directory ownership
  if [ $? -eq 0 ] && [ -d "$QA_DIR/.git" ]; then
    verify "QA repository cloned successfully"
    # Verify remote URL
    REMOTE_URL=$(su - truffle -c "cd $QA_DIR && git remote get-url origin")
    if [ "$REMOTE_URL" = "git@github.com:deepshard/QA.git" ]; then
      verify "Repository remote URL is correct"
    else
      log "❌ Repository remote URL verification failed"
    fi
  else
    log "❌ Repository clone failed"
  fi
else
  log "QA repository already exists"
fi
########################################
# PHASE 6: SPI Setup
########################################
log "Starting SPI setup phase"

# Check if SPI-1 is properly configured using marker file and actual state
if [[ -e /var/lib/spi-test.done ]]; then
    log "Marker file found – SPI‑1 should already be configured"
    if /opt/nvidia/jetson-io/config-by-function.py -l enabled | grep -q spi1; then
        log "SPI‑1 confirmed enabled"
        verify "SPI-1 is properly configured"
    else
        log "❌ ERROR: SPI‑1 NOT enabled even though marker exists"
        exit 1
    fi
else
    log "Marker file missing – treating this as first run"
    if /opt/nvidia/jetson-io/config-by-function.py -l enabled | grep -q spi1; then
        log "SPI‑1 already enabled → creating marker"
        touch /var/lib/spi-test.done
        verify "SPI-1 marker created"
    else
        log "SPI‑1 disabled → enabling it now"
        # Some boards need the 'dt' path first (it fails harmlessly on Orin)
        /opt/nvidia/jetson-io/config-by-function.py -o dt 1="spi1" || true
        /opt/nvidia/jetson-io/config-by-function.py -o dtbo spi1
        verify "SPI-1 configuration commands executed"

        log "Adding overlay to extlinux.conf"
        sed -i '/^LABEL .*/{
            :a; n; /^\s*$/b end; /^ *FDTOVERLAY /b end;
            /^ *APPEND /a\ \ \ FDTOVERLAY /boot/jetson-io-hdr40-user-custom.dtbo
            ba; :end
        }' /boot/extlinux/extlinux.conf
        verify "Added overlay to extlinux.conf"

        REBOOT_NEEDED=true
        log "SPI configuration complete - reboot will be required"
    fi
fi

########################################
# PHASE 7: SSH KEY SETUP
########################################
# Configuration for SSH setup
# REMOTE_USER="truffle"
# REMOTE_HOST="truffle.local"
# SSH_KEY_FILE="/root/.ssh/id_ed25519"

# log "Starting SSH key setup phase"

# # Ensure .ssh directory exists with correct permissions
# if [ ! -d "/root/.ssh" ]; then
#   log "Creating /root/.ssh directory"
#   mkdir -p /root/.ssh
#   chmod 700 /root/.ssh
# fi

# Generate key pair if it does not already exist
# if [ ! -f "$SSH_KEY_FILE" ]; then
#   log "SSH key not found. Generating new Ed25519 key pair at $SSH_KEY_FILE"
#   ssh-keygen -t ed25519 -f "$SSH_KEY_FILE" -N "" -q
#   if [ $? -eq 0 ]; then
#     log "SSH key generated successfully"
#   else
#     log "Failed to generate SSH key"
#   fi
# else
#   log "SSH key already exists. Skipping generation"
# fi

# # Add remote host to known_hosts to avoid prompts
# if ! ssh-keygen -F "$REMOTE_HOST" >/dev/null; then
#   log "Fetching and adding $REMOTE_HOST to known_hosts"
#   ssh-keyscan -H "$REMOTE_HOST" >> /root/.ssh/known_hosts 2>/dev/null || true
# fi

# # Copy public key to the remote machine for passwordless SSH
# log "Copying public key to $REMOTE_USER@$REMOTE_HOST"

# # Check if sshpass is installed
# if ! command -v sshpass &> /dev/null; then
#   log "sshpass not found. Attempting to install..."
#   apt-get update -y && apt-get install -y sshpass
# fi

# # Use sshpass to provide the password automatically
# if command -v sshpass &> /dev/null; then
#   # First test connection with password
#   if sshpass -p "runescape" ssh -o StrictHostKeyChecking=no "$REMOTE_USER@$REMOTE_HOST" 'echo "SSH connection successful"'; then
#     log "SSH connection successful with password"
    
#     # Now copy the key using password
#     if sshpass -p "runescape" ssh-copy-id -i "${SSH_KEY_FILE}.pub" -o StrictHostKeyChecking=no "$REMOTE_USER@$REMOTE_HOST"; then
#       log "Public key copied to remote host successfully"
#     else
#       log "Failed to copy public key with sshpass"
#     fi
#   else
#     log "Failed to connect with password. Trying alternative method..."
#     # Fall back to original method
#     SSH_COPY_CMD="cat ${SSH_KEY_FILE}.pub | ssh ${REMOTE_USER}@${REMOTE_HOST} 'mkdir -p ~/.ssh && chmod 700 ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys'"
#     eval $SSH_COPY_CMD
#   fi
# else
#   # Fall back to original method if sshpass installation failed
#   log "sshpass not available. You may be prompted for password."
#   SSH_COPY_CMD="cat ${SSH_KEY_FILE}.pub | ssh ${REMOTE_USER}@${REMOTE_HOST} 'mkdir -p ~/.ssh && chmod 700 ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys'"
#   eval $SSH_COPY_CMD
# fi

########################################
# PHASE 8: Additional Tools Installation
########################################
log "Starting additional tools installation phase"

# Install smartmontools for smartctl
if ! command -v smartctl &> /dev/null; then
  log "Installing smartmontools..."
  apt-get update && apt-get install -y smartmontools
  if command -v smartctl &> /dev/null; then
    verify "smartmontools installation successful"
  else
    log "❌ Failed to install smartmontools"
  fi
else
  log "smartmontools is already installed"
fi

# Create directory for NVME health logs
NVME_LOG_DIR="/var/log/nvme_health"
if [ ! -d "$NVME_LOG_DIR" ]; then
  log "Creating NVME health log directory..."
  mkdir -p "$NVME_LOG_DIR"
  chmod 755 "$NVME_LOG_DIR"
  verify "NVME health log directory created"
fi

# Install pip if not already installed
if ! command -v pip3 &> /dev/null; then
  log "Installing pip3..."
  apt-get update && apt-get install -y python3-pip
  verify "pip3 installation"
fi

# Install jtop Python package
log "Installing jtop Python package..."
pip3 install -U jetson-stats
if python3 -c "import jtop" &> /dev/null; then
  verify "jtop package installation successful"
else
  log "❌ Failed to install jtop package"
fi

########################################
# PHASE 9: Power Mode Setup
########################################
log "Starting power mode setup phase"

# Check current power mode and log it
CURRENT_MODE=$(nvpmodel -q | grep -v "NV Power Mode" | xargs)
log "Initial power mode: $CURRENT_MODE"

# Check current power mode
if [ "$CURRENT_MODE" != "0" ]; then
  log "Current power mode is not MAXN. Setting to MAXN..."
  log "Command: nvpmodel -m 0"
  
  # Send "yes" to the reboot prompt
  echo "yes" | nvpmodel -m 0
  
  REBOOT_NEEDED=true
  log "Power mode set to MAXN. Reboot will be required."
else
  log "Power mode is already MAXN."
fi

########################################
# FINAL PHASE: Reboot if needed
########################################
if [ "$REBOOT_NEEDED" = true ]; then
  log "Stage 0 completed. System changes require a reboot."
  log "Rebooting system in 5 seconds..."
  log "Rebooting in 3..."
  sleep 1
  log "Rebooting in 2..."
  sleep 1
  log "Rebooting in 1..."
  sleep 1
  reboot
else
  log "Stage 0 completed. No reboot required."
fi

