

#!/usr/bin/env bash
set -euo pipefail

################################################################################
# Logging
################################################################################

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

verify() {
  if [ $? -eq 0 ]; then
    log "✅ Verification passed: $1"
    return 0
  else
    log "❌ Verification failed: $1"
    return 1
  fi
}

log "Starting stage0 script"

# Variable to track if reboot is needed
REBOOT_NEEDED=false

#FLAG=/var/lib/firstboot.done
#if [ -e "$FLAG" ]; then
#    echo "First-boot already completed, exiting."
#    exit 0
#fi

#set hostname truffle-xxxx
log "Step 1: Setting hostname based on device serial"
SERIAL=$(tr -d '\0' </proc/device-tree/serial-number)
HOST="truffle-${SERIAL: -4}"
hostnamectl set-hostname "$HOST"
nmcli general hostname "$HOST"
log "Hostname set to: $HOST"


##  connect to wifi 1
log "Step 2: Connectivity setup"
WIFI_IF=wlP1p1s0
PRIMARY_SSID="itsalltruffles"          
PRIMARY_PSK="itsalwaysbeentruffles"
SECONDARY_SSID="TP_LINK_AP_E732"
SECONDARY_PSK="95008158"
FALLBACK_NAME="fallback-hotspot"
FALLBACK_PSK="runescape"


# 2a.  Make sure hotspot profile exists (lowest priority –999)
nmcli -t -f NAME con show | grep -qx "$FALLBACK_NAME" && \
	        nmcli con delete "$FALLBACK_NAME"

nmcli con add type wifi ifname "$WIFI_IF" mode ap \
	        con-name "$FALLBACK_NAME" ssid "$(hostname)" \
		        wifi-sec.key-mgmt wpa-psk wifi-sec.psk "$FALLBACK_PSK" \
			        ipv4.method shared ipv6.method ignore \
				        connection.autoconnect no \
					        connection.autoconnect-priority -999


# 2b.  Try the client network with retries
CONNECTED=false
for attempt in {1..5}; do
    log "→ attempting to join $PRIMARY_SSID (attempt $attempt/5)"
    if nmcli --wait 15 device wifi connect "$PRIMARY_SSID" \
             password "$PRIMARY_PSK" ifname "$WIFI_IF"; then
        log "✓ connected to $PRIMARY_SSID on attempt $attempt"
        # Set autoconnect priority after successful connection
        nmcli con modify "$PRIMARY_SSID" connection.autoconnect-priority 0
        CONNECTED=true
        break
    else
        log "✗ attempt $attempt failed"
        if [ $attempt -lt 5 ]; then
            log "→ waiting 5 seconds before retry..."
            sleep 5
        fi
    fi
done

if [ "$CONNECTED" = false ]; then
    log "✗ all Wi-Fi attempts failed – starting hotspot"
    nmcli con up "$FALLBACK_NAME"
fi


################################################################################
# 3.  Avahi restart for new hostname
################################################################################
log "Step 3: Restarting Avahi daemon"
systemctl restart avahi-daemon

#no need to make this too complicatred, ill make the repo temporarily public
# log "Step 4: Updating QA repository"
# QA_DIR=/home/truffle/QA
# run_as_truffle() { sudo -u truffle -H bash -c "$*"; }

# # Fix git ownership issues first
# log "Fixing git safe directory configuration"
# run_as_truffle "git config --global --add safe.directory $QA_DIR" || true

# if [ -d "$QA_DIR/.git" ]; then
#     log "QA repository exists, updating to latest main branch"
#     # Ensure correct ownership
#     chown -R truffle:truffle "$QA_DIR"
    
#     # Always use main as source of truth - fetch latest and reset hard
#     if run_as_truffle "cd $QA_DIR && git fetch origin main --quiet && git checkout main --quiet && git reset --hard origin/main --quiet"; then
#         log "QA repository updated successfully to latest main"
#     else
#         log "Failed to update QA repository, trying to fix and retry..."
#         # Try to fix any remaining git issues
#         run_as_truffle "cd $QA_DIR && git config --local --add safe.directory $QA_DIR" || true
#         run_as_truffle "cd $QA_DIR && git checkout main" || true
#         run_as_truffle "cd $QA_DIR && git fetch origin main --quiet" || true
#         if run_as_truffle "cd $QA_DIR && git reset --hard origin/main --quiet"; then
#             log "QA repository updated successfully to latest main after fix"
#         else
#             log "Failed to update QA repository even after fixes"
#         fi
#     fi
# else
#     log "QA repository not found, cloning from GitHub"
#     # Ensure parent directory exists and has correct ownership
#     mkdir -p "$(dirname "$QA_DIR")"
#     chown truffle:truffle "$(dirname "$QA_DIR")"
#     run_as_truffle "git clone https://github.com/deepshard/QA.git $QA_DIR"
#     chown -R truffle:truffle "$QA_DIR"
#     log "QA repository cloned successfully"
# fi

#set max-n power mode
log "Step 5: Ensuring MAX-N power mode"
if ! nvpmodel -q | grep -q 'NV Power Mode: MAXN'; then
    if yes | nvpmodel -m 0; then
        log "MAX-N activated (reboot may be required)"
        REBOOT_NEEDED=true
    else
        log "nvpmodel failed non-fatally; continuing"
    fi
else
    log "Already in MAX-N, skipping"
fi

#rename emmc partition for jetson-io
log "Step 6: Starting EMMC partition renaming phase"
# Check current partition label
CURRENT_LABEL=$(sgdisk -p /dev/mmcblk0 | grep "APP" | awk '{print $7}')
if [ "$CURRENT_LABEL" != "APP_EMMC" ]; then
  log "Changing partition label from APP to APP_EMMC..."
  sgdisk --change-name=1:APP_EMMC /dev/mmcblk0
  partprobe /dev/mmcblk0
  
  # Verify partition rename
  NEW_LABEL=$(sgdisk -p /dev/mmcblk0 | grep "APP_EMMC" | awk '{print $7}')
  if [ "$NEW_LABEL" = "APP_EMMC" ]; then
    log "✅ Partition successfully renamed to APP_EMMC"
  else
    log "❌ Partition rename verification failed"
  fi
  
  # Additional verification using lsblk
  LSBLK_VERIFY=$(lsblk -o NAME,PARTLABEL /dev/mmcblk0 | grep "APP_EMMC")
  if [ -n "$LSBLK_VERIFY" ]; then
    verify "Partition label verified with lsblk"
  else
    log "❌ Partition label verification with lsblk failed"
  fi
else
  log "Partition label is already APP_EMMC"
fi

################################################################################
# Step 7: Enable SPI1 pins
################################################################################
log "Step 7: Configuring SPI1 pins"
if [[ -e /var/lib/spi-test.done ]]; then
    log "Marker file found – SPI‑1 should already be configured"
    if /opt/nvidia/jetson-io/config-by-function.py -l enabled | grep -q spi1; then
        log "SPI‑1 confirmed enabled"
    else
        log "❌ ERROR: SPI‑1 NOT enabled even though marker exists"
        exit 1
    fi
else
    log "Marker file missing – treating this as first run"
    if /opt/nvidia/jetson-io/config-by-function.py -l enabled | grep -q spi1; then
        log "SPI‑1 already enabled → creating marker"
        touch /var/lib/spi-test.done
    else
        log "SPI‑1 disabled → enabling it now"
        # Some boards need the 'dt' path first (it fails harmlessly on Orin)
        /opt/nvidia/jetson-io/config-by-function.py -o dt 1="spi1" || true
        /opt/nvidia/jetson-io/config-by-function.py -o dtbo spi1
        
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




log "Step 8: Running LED test to confirm system setup"
LED_TEST_SCRIPT="/home/truffle/QA/src/led_test.sh"

if [ -f "$LED_TEST_SCRIPT" ]; then
    log "Running LED test script..."
    if bash "$LED_TEST_SCRIPT"; then
        log "✅ LED test completed successfully"
    else
        log "⚠️ LED test failed, but continuing (non-critical)"
    fi
else
    log "⚠️ LED test script not found at $LED_TEST_SCRIPT, skipping"
fi

################################################################################
# Finalize
################################################################################

if [ "$REBOOT_NEEDED" = true ]; then
    log "System changes require a reboot. Rebooting in 10 seconds..."
    sleep 10
    reboot
fi

log "Stage0 completed successfully"
exit 0
root@truff
