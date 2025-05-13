#!/usr/bin/env bash
set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO: $BASH_COMMAND" >&2' ERR

TMP_FILE="/home/truffle/abd_work/tmp.txt"
HOTSPOT_PASSWORD="runescape"
MAX_RETRY=10
RETRY_INTERVAL=10
LOG_DIR="/home/truffle/abd_work"

mkdir -p "$LOG_DIR"

# Check if TMP_FILE exists and is not empty
if [[ ! -f "$TMP_FILE" ]] || [[ ! -s "$TMP_FILE" ]]; then
    echo "❌ Error: $TMP_FILE does not exist or is empty" | tee -a "${LOG_DIR}/error.log"
    exit 1
fi

HOTSPOT_SSID=$(<"$TMP_FILE")
TIMESTAMP=$(date +%m%d%y_%H%M%S)
LOG_FILE="${LOG_DIR}/${HOTSPOT_SSID}_${TIMESTAMP}.txt"

# tee ALL output from now on
exec > >(tee -a "$LOG_FILE") 2>&1
echo "=== hotspot_connect.sh started $(date) ==="

# Wi‑Fi interface discovery
IFACE=$(nmcli -t -f DEVICE,TYPE device status | awk -F: '$2=="wifi"{print $1;exit}')
[[ -z "$IFACE" ]] && { echo "❌ No Wi‑Fi interface."; exit 1; }
echo "Using interface: $IFACE"

# Record network information before disconnecting
echo "→ Saving current network state..."
CURRENT_CONN=$(nmcli -t -f NAME,DEVICE connection show --active | awk -F: -v dev="$IFACE" '$2==dev{print $1}')
CURRENT_SSID=$(nmcli -t -f active,ssid dev wifi | grep "yes" | cut -d':' -f2)
echo "Current connection: $CURRENT_CONN"
echo "Current SSID: $CURRENT_SSID"

# Save connection details to a file for better restoration
if [[ -n "$CURRENT_CONN" ]]; then
    echo "$CURRENT_CONN" > "${LOG_DIR}/previous_connection.txt"
    echo "$CURRENT_SSID" >> "${LOG_DIR}/previous_connection.txt"
    echo "→ Saved connection details to ${LOG_DIR}/previous_connection.txt"
fi

if [[ -n "$CURRENT_CONN" ]]; then
  echo "Disconnecting from $CURRENT_CONN…"
  sudo nmcli connection down "$CURRENT_CONN" || echo "⚠️  Could not down $CURRENT_CONN"
fi

# Log nmcli status after disconnection
echo "→ nmcli status after disconnection:" | tee -a "$LOG_FILE"
nmcli device status | tee -a "$LOG_FILE"

# Function to scan for the hotspot
scan_for_hotspot() {
    echo "→ Scanning for WiFi networks..." | tee -a "$LOG_FILE"
    nmcli device wifi rescan
    sleep 3
    echo "→ Available networks:" | tee -a "$LOG_FILE"
    nmcli device wifi list | tee -a "$LOG_FILE"
    nmcli device wifi list | grep "$HOTSPOT_SSID" || echo "Not found"
}

# Function to connect to the hotspot
connect_to_hotspot() {
    echo "→ Attempting to connect to $HOTSPOT_SSID with password $HOTSPOT_PASSWORD..." | tee -a "$LOG_FILE"
    if nmcli device wifi connect "$HOTSPOT_SSID" password "$HOTSPOT_PASSWORD"; then
        echo "→ Connection command successful" | tee -a "$LOG_FILE"
        return 0
    else
        echo "→ Connection command failed" | tee -a "$LOG_FILE"
        return 1
    fi
}

# Function to verify connection
verify_connection() {
    echo "→ Verifying connection..." | tee -a "$LOG_FILE"
    local connected_ssid=$(nmcli -t -f active,ssid dev wifi | grep "yes" | cut -d':' -f2)
    echo "→ Connected SSID: $connected_ssid" | tee -a "$LOG_FILE"
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
    echo "→ Attempt $attempt of $MAX_RETRY" | tee -a "$LOG_FILE"
    
    # Scan for the hotspot
    scan_result=$(scan_for_hotspot)
    if echo "$scan_result" | grep -q "$HOTSPOT_SSID"; then
        echo "✅ Found WiFi: $HOTSPOT_SSID" | tee -a "$LOG_FILE"
        
        # Try to connect
        if connect_to_hotspot; then
            sleep 8  # Give more time for connection to establish
            
            # Verify connection
            if verify_connection; then
                echo "✅ Successfully connected to $HOTSPOT_SSID!" | tee -a "$LOG_FILE"
                
                # Test ping to the AGX Orin (assuming it has IP 10.42.0.1 in hotspot mode)
                echo "→ Attempting to ping AGX Orin..." | tee -a "$LOG_FILE"
                for ip in 10.42.0.1 192.168.1.1 192.168.0.1; do
                    if ping -c 3 $ip &>/dev/null; then
                        echo "✅ Successfully pinged $ip (likely the AGX Orin)" | tee -a "$LOG_FILE"
                        break
                    else
                        echo "Could not ping $ip" | tee -a "$LOG_FILE"
                    fi
                done
                
                connected=true
                
                # Stay connected for a while
                echo "→ Staying connected for 30 seconds..." | tee -a "$LOG_FILE"
                sleep 30
                
                # Take some connection info for the logs
                echo "→ Connection details:" | tee -a "$LOG_FILE"
                nmcli connection show --active | tee -a "$LOG_FILE"
                ip addr show dev "$IFACE" | tee -a "$LOG_FILE"
                ip route | tee -a "$LOG_FILE"
            else
                echo "❌ Connection verification failed" | tee -a "$LOG_FILE"
            fi
        else
            echo "❌ Failed to connect to $HOTSPOT_SSID" | tee -a "$LOG_FILE"
        fi
    else
        echo "⚠️ Hotspot not found in scan results" | tee -a "$LOG_FILE"
    fi
    
    # If not connected, wait before next attempt
    if [ "$connected" = false ]; then
        echo "→ Waiting $RETRY_INTERVAL seconds before next attempt..." | tee -a "$LOG_FILE"
        sleep $RETRY_INTERVAL
    fi
done

# Check final status
if [ "$connected" = false ]; then
    echo "❌ Failed to connect to hotspot after $MAX_RETRY attempts" | tee -a "$LOG_FILE"
else
    echo "→ Disconnecting from hotspot..." | tee -a "$LOG_FILE"
    nmcli connection down "$HOTSPOT_SSID" || nmcli connection down "Hotspot" || echo "Failed to disconnect from hotspot" | tee -a "$LOG_FILE"
fi

# Enhanced restore previous WiFi connection
if [[ -n "$CURRENT_CONN" ]]; then
    echo "→ Restoring previous connection: $CURRENT_CONN" | tee -a "$LOG_FILE"
    
    # First try - using the connection name
    if nmcli connection up "$CURRENT_CONN"; then
        echo "→ Connection restore successful using connection name" | tee -a "$LOG_FILE"
    else
        echo "⚠️ Failed to restore using connection name, trying SSID..." | tee -a "$LOG_FILE"
        
        # Second try - using the SSID if available
        if [[ -n "$CURRENT_SSID" ]] && nmcli device wifi connect "$CURRENT_SSID"; then
            echo "→ Connection restore successful using SSID" | tee -a "$LOG_FILE"
        else
            echo "❌ Failed to restore connection using both methods" | tee -a "$LOG_FILE"
            
            # List available networks as a fallback
            echo "→ Available networks:" | tee -a "$LOG_FILE"
            nmcli device wifi list | tee -a "$LOG_FILE"
        fi
    fi
    
    # Verify reconnection
    sleep 8
    RECONNECTED_CONN=$(nmcli -t -f NAME,DEVICE connection show --active | awk -F: -v dev="$IFACE" '$2==dev{print $1}')
    if [[ -n "$RECONNECTED_CONN" ]]; then
        echo "✅ Successfully reconnected to a network: $RECONNECTED_CONN" | tee -a "$LOG_FILE"
    else
        echo "❌ Failed to reconnect to any network" | tee -a "$LOG_FILE"
    fi
else
    echo "→ No previous connection to restore" | tee -a "$LOG_FILE"
fi

echo "→ Test completed at $(date)" | tee -a "$LOG_FILE"
echo "Log file saved as $LOG_FILE" | tee -a "$LOG_FILE"

# Create a simple summary file for easy checking
SUMMARY_FILE="${LOG_DIR}/latest_test_summary.txt"
{
    echo "Test of $HOTSPOT_SSID at $(date)"
    echo "Connected successfully: $connected"
    echo "Log file: $LOG_FILE"
} > "$SUMMARY_FILE"

# Make sure logs are readable even if created as root
chmod 644 "$LOG_FILE" "$SUMMARY_FILE" "$LOG_DIR/hotspot_debug.log" "${LOG_DIR}/previous_connection.txt" 2>/dev/null || true
