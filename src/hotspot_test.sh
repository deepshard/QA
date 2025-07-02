#!/usr/bin/env bash
# health_check.sh — Complete system health check script
# Includes: LED test, WiFi hotspot test, NVME health check, and GPU/CPU burn test

# Check if we're already in a screen session
if [ -z "$STY" ]; then
  # We're not in a screen session, so start one
  if [ "$EUID" -ne 0 ]; then
    # We're not root, so use sudo with screen
    exec sudo screen -S stage2 "$0" "$@"
  else
    # We're root, just start screen
    exec screen -S stage2 "$0" "$@"
  fi
  exit 0
fi

set -euo pipefail

# Create logs directory in /home/truffle/qa/scripts/logs
mkdir -p "/home/truffle/qa/scripts/logs"

# CONFIGURATION

#!/usr/bin/env bash
# Run on the Orin (host name truffle-7042)
set -euo pipefail

# Set the Linux PC hostname
PC_USER="truffle"
# List of potential Linux PC hostnames (primary followed by fallback)
PC_HOSTS=("abd.local" "truffle-2.local")
# Will hold the first reachable host
PC_HOST=""
REMOTE_SCRIPT="/home/truffle/abd_work/hotspot_connect.sh"
TMP_REMOTE="/home/truffle/abd_work/tmp.txt"
SSH_KEY="$HOME/.ssh/id_hotspot"

# Get Orin's hostname for SSID and connection name
HOST_SSID=$(hostname)  # gives "truffle-7042"
CONN_NAME="${HOST_SSID}-hotspot"  #dont  Use same name for NetworkManager connection, fucks up stuff
HOTSPOT_PSK="runescape"
DURATION=30  # seconds to keep hotspot active

# 1) Notify the Linux PC about the hotspot SSID
# Try each candidate hostname until one responds
for host in "${PC_HOSTS[@]}"; do
    if ping -c 1 -W 2 "$host" &> /dev/null; then
        PC_HOST="$host"
        echo "→ Successfully reached Linux PC at $PC_HOST"
        break
    fi
done

if [[ -n "$PC_HOST" ]]; then
    # Attempt to SSH and set up the Linux PC
    ssh -i "$SSH_KEY" -o ConnectTimeout=5 ${PC_USER}@${PC_HOST} "mkdir -p /home/truffle/abd_work && echo $HOST_SSID > $TMP_REMOTE"

    # Start the hotspot-connect routine on the PC in background with nohup so it persists
    ssh -i "$SSH_KEY" ${PC_USER}@${PC_HOST} "nohup sudo $REMOTE_SCRIPT > /home/truffle/abd_work/hotspot_nohup.out 2>&1 &"

    # Give the Linux PC script a moment to start
    echo "→ Waiting 5 seconds for Linux PC script to initialize..."
    sleep 5
else
    echo "⚠️ Cannot reach Linux PC (${PC_HOSTS[*]}). Will still create hotspot but PC connection may fail."
fi

# 2) Identify the Wi-Fi interface
IFACE=$(sudo nmcli -t -f DEVICE,TYPE device status | awk -F: '$2=="wifi"{print $1; exit}')
if [[ -z "$IFACE" ]]; then
    echo "❌ No Wi-Fi interface found."
    exit 1
fi
echo "→ Using Wi-Fi interface: $IFACE"

# 3) Save existing connection (if any) so we can restore it later
CURRENT_CONN=$(sudo nmcli -t -f NAME,DEVICE connection show --active | awk -F: -v dev="$IFACE" '$2==dev{print $1}')
if [[ -n "$CURRENT_CONN" ]]; then
    echo "→ Storing currently active connection: $CURRENT_CONN"
    sudo nmcli connection down "$CURRENT_CONN"
else
    echo "→ No active WiFi connection found to store"
fi

# 4) Check if there's already a connection with our name and delete it first
if sudo nmcli connection show | grep -q "$CONN_NAME"; then
    echo "→ Found existing connection named '$CONN_NAME', deleting it first..."
    sudo nmcli connection delete "$CONN_NAME" || true
fi

# 5) Start hotspot on the Orin with explicit connection name
echo "→ Starting hotspot \"$HOST_SSID\" on $IFACE with connection name \"$CONN_NAME\"..."
sudo nmcli device wifi hotspot ifname "$IFACE" ssid "$HOST_SSID" password "$HOTSPOT_PSK" con-name "$CONN_NAME"

# 6) Show hotspot status
echo "→ Hotspot active. Details:"
sudo nmcli -f NAME,UUID,TYPE,DEVICE connection show --active | grep -i "$CONN_NAME" || true
sudo nmcli device status | grep "$IFACE"
echo "→ Hotspot will run for $DURATION seconds..."

# Helper: check if at least one client is associated to the hotspot
client_connected() {
    # 1) Try using iw (works when driver supports station dump)
    if sudo iw dev "$IFACE" station dump 2>/dev/null | grep -q 'Station'; then
        return 0
    fi

    # 2) Fallback to hostapd_cli (more reliable on some Broadcom/Realtek chipsets)
    if command -v hostapd_cli &>/dev/null; then
        if sudo hostapd_cli -i "$IFACE" all_sta 2>/dev/null | grep -qE '^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}'; then
            return 0
        fi
    fi

    # 3) Last-chance: look for reachable peers in the ARP/neighbor table on the hotspot interface
    if ip neigh show dev "$IFACE" | grep -q 'REACHABLE'; then
        return 0
    fi

    return 1
}

# 7) Check for connected clients periodically
for i in $(seq 1 $((DURATION/10))); do
    echo "→ Checking for connected clients (check $i)..."
    if client_connected; then
        echo "✅ Client connected to hotspot '$HOST_SSID'!"
    else
        echo "Waiting for client connection to '$HOST_SSID'..."
    fi
    sleep 10
done

# 8) Tear down hotspot
echo "→ Stopping hotspot \"$CONN_NAME\"..."
sudo nmcli connection down "$CONN_NAME" || true
sudo nmcli connection delete "$CONN_NAME" || true

# 9) Restore previous Wi-Fi connection (if any)
if [[ -n "$CURRENT_CONN" ]]; then
    echo "→ Restoring connection: $CURRENT_CONN"
    sudo nmcli connection up "$CURRENT_CONN"
    
    # Wait for connection to be established
    echo "→ Waiting for WiFi reconnection..."
    for i in $(seq 1 10); do
        if sudo nmcli -t -f NAME,DEVICE connection show --active | grep -q "$CURRENT_CONN"; then
            echo "✅ Successfully reconnected to $CURRENT_CONN"
            break
        fi
        echo "   Waiting... ($i/10)"
        sleep 2
    done
else
    echo "→ No previous connection to restore"
fi

# 10) Try to reconnect to the Linux PC to check results
if [[ -n "$PC_HOST" ]] && ping -c 1 -W 2 "$PC_HOST" &> /dev/null; then
    echo "→ Reconnected to Linux PC, sanity check..."
else
    echo "⚠️ Could not reconnect to Linux PC to check results."
fi

echo "✅ Hotspot test complete."




