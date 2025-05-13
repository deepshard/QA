#!/usr/bin/env bash
set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO: $BASH_COMMAND" >&2' ERR

TMP_FILE="/home/truffle/abd_work/tmp.txt"
HOTSPOT_PASSWORD="runescape"
MAX_RETRY=10
RETRY_INTERVAL=10

# Check if TMP_FILE exists and is not empty
if [[ ! -f "$TMP_FILE" ]] || [[ ! -s "$TMP_FILE" ]]; then
    echo "❌ Error: $TMP_FILE does not exist or is empty"
    exit 1
fi

HOTSPOT_SSID=$(<"$TMP_FILE")

# Create the directory for this specific truffle unit
TRUFFLE_QA_DIR="/home/truffle/abd_work/truffle_QA"
mkdir -p "${TRUFFLE_QA_DIR}/${HOTSPOT_SSID}"
echo "✅ Created directory: ${TRUFFLE_QA_DIR}/${HOTSPOT_SSID}"

# Wi‑Fi interface discovery
IFACE=$(nmcli -t -f DEVICE,TYPE device status | awk -F: '$2=="wifi"{print $1;exit}')
[[ -z "$IFACE" ]] && { echo "❌ No Wi‑Fi interface."; exit 1; }
echo "Using interface: $IFACE"

# Record current connection for restoration later
CURRENT_CONN=$(nmcli -t -f NAME,DEVICE connection show --active | awk -F: -v dev="$IFACE" '$2==dev{print $1}')
CURRENT_SSID=$(nmcli -t -f active,ssid dev wifi | grep "yes" | cut -d':' -f2)

if [[ -n "$CURRENT_CONN" ]]; then
  echo "Disconnecting from $CURRENT_CONN…"
  sudo nmcli connection down "$CURRENT_CONN" || echo "⚠️  Could not down $CURRENT_CONN"
fi

# Function to scan for the hotspot
scan_for_hotspot() {
    echo "→ Scanning for WiFi networks..."
    nmcli device wifi rescan
    sleep 3
    nmcli device wifi list | grep "$HOTSPOT_SSID" || echo "Not found"
}

# Function to connect to the hotspot
connect_to_hotspot() {
    echo "→ Attempting to connect to $HOTSPOT_SSID..."
    if nmcli device wifi connect "$HOTSPOT_SSID" password "$HOTSPOT_PASSWORD"; then
        echo "→ Connection command successful"
        return 0
    else
        echo "→ Connection command failed"
        return 1
    fi
}

# Function to verify connection
verify_connection() {
    local connected_ssid=$(nmcli -t -f active,ssid dev wifi | grep "yes" | cut -d':' -f2)
    echo "→ Connected SSID: $connected_ssid"
    if [[ "$connected_ssid" == "$HOTSPOT_SSID" ]]; then
        return 0
    else
        return 1
    fi
}

# Main logic - scanning for hotspot and attempting to connect
attempt=0
connected=false

while [ $attempt -lt $MAX_RETRY ] && [ "$connected" = false ]; do
    attempt=$((attempt+1))
    echo "→ Attempt $attempt of $MAX_RETRY"
    
    # Scan for the hotspot
    scan_result=$(scan_for_hotspot)
    if echo "$scan_result" | grep -q "$HOTSPOT_SSID"; then
        echo "✅ Found WiFi: $HOTSPOT_SSID"
        
        # Try to connect
        if connect_to_hotspot; then
            sleep 8  # Give more time for connection to establish
            
            # Verify connection
            if verify_connection; then
                echo "✅ Successfully connected to $HOTSPOT_SSID!"
                
                # Test ping to the AGX Orin
                for ip in 10.42.0.1 192.168.1.1 192.168.0.1; do
                    if ping -c 3 $ip &>/dev/null; then
                        echo "✅ Successfully pinged $ip (likely the AGX Orin)"
                        break
                    else
                        echo "Could not ping $ip"
                    fi
                done
                
                connected=true
                
                # Stay connected for a while
                echo "→ Staying connected for 30 seconds..."
                sleep 30
            else
                echo "❌ Connection verification failed"
            fi
        else
            echo "❌ Failed to connect to $HOTSPOT_SSID"
        fi
    else
        echo "⚠️ Hotspot not found in scan results"
    fi
    
    # If not connected, wait before next attempt
    if [ "$connected" = false ]; then
        echo "→ Waiting $RETRY_INTERVAL seconds before next attempt..."
        sleep $RETRY_INTERVAL
    fi
done

# Check final status
if [ "$connected" = false ]; then
    echo "❌ Failed to connect to hotspot after $MAX_RETRY attempts"
else
    echo "→ Disconnecting from hotspot..."
    nmcli connection down "$HOTSPOT_SSID" || nmcli connection down "Hotspot" || echo "Failed to disconnect from hotspot"
fi

# Restore previous WiFi connection
if [[ -n "$CURRENT_CONN" ]]; then
    echo "→ Restoring previous connection: $CURRENT_CONN"
    
    # First try - using the connection name
    if nmcli connection up "$CURRENT_CONN"; then
        echo "→ Connection restore successful"
    else
        echo "⚠️ Failed to restore using connection name, trying SSID..."
        
        # Second try - using the SSID if available
        if [[ -n "$CURRENT_SSID" ]] && nmcli device wifi connect "$CURRENT_SSID"; then
            echo "→ Connection restore successful using SSID"
        else
            echo "❌ Failed to restore connection"
        fi
    fi
else
    echo "→ No previous connection to restore"
fi

echo "✅ Directory created: ${TRUFFLE_QA_DIR}/${HOTSPOT_SSID}"
