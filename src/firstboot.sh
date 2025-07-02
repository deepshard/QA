#!/usr/bin/env bash
set -euo pipefail

################################################################################
# Logging
################################################################################
LOG_FILE="/home/truffle/firstboot.log"
echo "Starting first-boot script at $(date)" > "$LOG_FILE"
exec >>"$LOG_FILE" 2>&1



verify() {
  if [ $? -eq 0 ]; then
    log "✅ Verification passed: $1"
    return 0
  else
    log "❌ Verification failed: $1"
    return 1
  fi
}

# Variable to track if reboot is needed
REBOOT_NEEDED=false

#FLAG=/var/lib/firstboot.done
#if [ -e "$FLAG" ]; then
#    echo "First-boot already completed, exiting."
#    exit 0
#fi

#set hostname truffle-xxxx
echo "Step 1: Setting hostname based on device serial"
SERIAL=$(tr -d '\0' </proc/device-tree/serial-number)
HOST="truffle-${SERIAL: -4}"
hostnamectl set-hostname "$HOST"
nmcli general hostname "$HOST"
echo "Hostname set to: $HOST"


##  connect to wifi 1
echo "Step 2: Connectivity setup"
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


# 2b.  Try the client network and wait up to 15 s
echo "→ attempting to join $PRIMARY_SSID (15 s timeout)"
if nmcli --wait 15 device wifi connect "$PRIMARY_SSID" \
	         password "$PRIMARY_PSK" ifname "$WIFI_IF" autoconnect yes \
		          connection.autoconnect-priority 0; then
    echo "✓ connected to $PRIMARY_SSID"
else
	    echo "✗ client Wi-Fi failed – starting hotspot"
	        nmcli con up "$FALLBACK_NAME"
fi


################################################################################
# 3.  Avahi restart for new hostname
################################################################################
echo "Step 3: Restarting Avahi daemon"
systemctl restart avahi-daemon

#no need to make this too complicatred, ill make the repo temporarily public
echo "updating QA repository"
QA_DIR=/home/truffle/qa
run_as_truffle() { sudo -u truffle -H bash -c "$*"; }

if [ -d "$QA_DIR/.git" ]; then
    echo "QA repository exists, attempting to update"
    if run_as_truffle "cd $QA_DIR && git pull --quiet"; then
        echo "QA repository updated successfully"
    else
        echo "Failed to update QA repository"
    fi
else
    echo "QA repository not found, cloning from GitHub"
    run_as_truffle "git clone https://github.com/deepshard/QA.git $QA_DIR"
    echo "QA repository cloned successfully"
fi

#set max-n power mode
echo "Step 5: Ensuring MAX-N power mode"
if ! nvpmodel -q | grep -q 'NV Power Mode: MAXN'; then
    if yes | nvpmodel -m 0; then
        echo "MAX-N activated (reboot may be required)"
        REBOOT_NEEDED=true
    else
        echo "nvpmodel failed non-fatally; continuing"
    fi
else
    echo "Already in MAX-N, skipping"
fi

################################################################################
# Step 6: Enable SPI1 pins
################################################################################
echo "Step 6: Configuring SPI1 pins"
if [[ -e /var/lib/spi-test.done ]]; then
    echo "Marker file found – SPI‑1 should already be configured"
    if /opt/nvidia/jetson-io/config-by-function.py -l enabled | grep -q spi1; then
        echo "SPI‑1 confirmed enabled"
    else
        echo "❌ ERROR: SPI‑1 NOT enabled even though marker exists"
        exit 1
    fi
else
    echo "Marker file missing – treating this as first run"
    if /opt/nvidia/jetson-io/config-by-function.py -l enabled | grep -q spi1; then
        echo "SPI‑1 already enabled → creating marker"
        touch /var/lib/spi-test.done
    else
        echo "SPI‑1 disabled → enabling it now"
        # Some boards need the 'dt' path first (it fails harmlessly on Orin)
        /opt/nvidia/jetson-io/config-by-function.py -o dt 1="spi1" || true
        /opt/nvidia/jetson-io/config-by-function.py -o dtbo spi1
        
        echo "Adding overlay to extlinux.conf"
        sed -i '/^LABEL .*/{
            :a; n; /^\s*$/b end; /^ *FDTOVERLAY /b end;
            /^ *APPEND /a\ \ \ FDTOVERLAY /boot/jetson-io-hdr40-user-custom.dtbo
            ba; :end
        }' /boot/extlinux/extlinux.conf
        verify "Added overlay to extlinux.conf"

        REBOOT_NEEDED=true
        echo "SPI configuration complete - reboot will be required"
    fi
fi


#rename emmc partition for jetson-io
echo "Starting EMMC partition renaming phase"
# Check current partition label
CURRENT_LABEL=$(sgdisk -p /dev/mmcblk0 | grep "APP" | awk '{print $7}')
if [ "$CURRENT_LABEL" != "APP_EMMC" ]; then
  echo "Changing partition label from APP to APP_EMMC..."
  sgdisk --change-name=1:APP_EMMC /dev/mmcblk0
  partprobe /dev/mmcblk0
  
  # Verify partition rename
  NEW_LABEL=$(sgdisk -p /dev/mmcblk0 | grep "APP_EMMC" | awk '{print $7}')
  if [ "$NEW_LABEL" = "APP_EMMC" ]; then
    echo "✅ Partition successfully renamed to APP_EMMC"
  else
    echo "❌ Partition rename verification failed"
  fi
  
  # Additional verification using lsblk
  LSBLK_VERIFY=$(lsblk -o NAME,PARTLABEL /dev/mmcblk0 | grep "APP_EMMC")
  if [ -n "$LSBLK_VERIFY" ]; then
    verify "Partition label verified with lsblk"
  else
    echo "❌ Partition label verification with lsblk failed"
  fi
else
  echo "Partition label is already APP_EMMC"
fi

################################################################################
# Finalize
################################################################################
chown truffle:truffle "$LOG_FILE"
chmod 644 "$LOG_FILE"

if [ "$REBOOT_NEEDED" = true ]; then
    echo "System changes require a reboot. Rebooting in 10 seconds..."
    sleep 10
    reboot
fi

echo "First-boot completed successfully at $(date)"
exit 0
