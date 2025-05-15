#!/usr/bin/env bash
set -euo pipefail

################################################################################
# Logging
################################################################################
LOG_FILE="/home/truffle/firstboot.log"
echo "Starting first-boot script at $(date)" > "$LOG_FILE"
exec >>"$LOG_FILE" 2>&1

#FLAG=/var/lib/firstboot.done
#if [ -e "$FLAG" ]; then
#    echo "First-boot already completed, exiting."
#    exit 0
#fi

################################################################################
# 1.  Hostname ─ truffle-<last-4-serial>
################################################################################
echo "Step 1: Setting hostname based on device serial"
SERIAL=$(tr -d '\0' </proc/device-tree/serial-number)
HOST="truffle-${SERIAL: -4}"
hostnamectl set-hostname "$HOST"
nmcli general hostname "$HOST"
echo "Hostname set to: $HOST"


################################################################################
# 2.  Connectivity – try client first, fall back to AP
################################################################################
echo "Step 2: Connectivity setup"
WIFI_IF=wlP1p1s0
PRIMARY_SSID="itsalltruffles"          # deliberately wrong for testing
PRIMARY_PSK="itsalwaysbeentruffles"

FALLBACK_NAME="fallback-hotspot"
FALLBACK_PSK="runescape"

# ------------------------------------------------------------------ #
# 2a.  Make sure hotspot profile exists (lowest priority –999)
nmcli -t -f NAME con show | grep -qx "$FALLBACK_NAME" && \
	        nmcli con delete "$FALLBACK_NAME"

nmcli con add type wifi ifname "$WIFI_IF" mode ap \
	        con-name "$FALLBACK_NAME" ssid "$(hostname)" \
		        wifi-sec.key-mgmt wpa-psk wifi-sec.psk "$FALLBACK_PSK" \
			        ipv4.method shared ipv6.method ignore \
				        connection.autoconnect no \
					        connection.autoconnect-priority -999

# ------------------------------------------------------------------ #
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

################################################################################
# 4.  QA repo & SSH permissions
################################################################################
echo "Step 4: Managing SSH permissions and updating QA repository"
QA_DIR=/home/truffle/qa
SSH_DIR=/home/truffle/.ssh
run_as_truffle() { sudo -u truffle -H bash -c "$*"; }

chmod 700 "$SSH_DIR" || true
chmod 600 "$SSH_DIR"/id_ed25519 2>/dev/null || true

if [ -d "$QA_DIR/.git" ]; then
    echo "QA repository exists, attempting to update"
    if run_as_truffle "git -C $QA_DIR fetch --quiet"; then
        run_as_truffle "git -C $QA_DIR pull --ff-only --quiet"
        echo "QA repository updated successfully"
    else
        echo "Failed to fetch updates for QA repository"
    fi
else
    echo "QA repository not found, cloning from GitHub"
    run_as_truffle "git clone https://github.com/deepshard/QA.git $QA_DIR"
    echo "QA repository cloned successfully"
fi

################################################################################
# 5.  MAX-N power mode
################################################################################
echo "Step 5: Ensuring MAX-N power mode"
if ! nvpmodel -q | grep -q 'NV Power Mode: MAXN'; then
    if yes | nvpmodel -m 0; then
        echo "MAX-N activated (reboot may be required)"
    else
        echo "nvpmodel failed non-fatally; continuing"
    fi
else
    echo "Already in MAX-N, skipping"
fi

################################################################################
# 6.  SPI-1 overlay
################################################################################
echo "Step 6: Configuring SPI1 pins"
if ! grep -q spi1 /boot/jetson-io* 2>/dev/null; then
   /opt/nvidia/jetson-io/config-by-function.py -o dtbo spi1
   echo "spi1" > /var/lib/spi1.enabled
   echo "SPI1 pins enabled"
else
   echo "SPI1 pins already enabled"
fi

################################################################################
# 7.  Finalise
################################################################################
chown truffle:truffle "$LOG_FILE"
chmod 644 "$LOG_FILE"
#this is for when u only need it to run once
#touch "$FLAG"
#echo "First-boot completed successfully at $(date)"
exit 0
