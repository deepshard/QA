#!/usr/bin/env bash
# Hotspot test: cycle between hotspot mode and secondary wifi connection
set -euo pipefail

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

log "Starting hotspot test"

# CONFIGURATION
HOST_SSID=$(hostname)  # gives "truffle-xxxx"
CONN_NAME="${HOST_SSID}-hotspot"
HOTSPOT_PSK="runescape"
HOTSPOT_DURATION=1800  # 30 minutes for hotspot
WIFI_DURATION=300    # 5 minutes for wifi connection

# Secondary wifi from stage0.sh
SECONDARY_SSID="TP_LINK_AP_E732"
SECONDARY_PSK="95008158"

# Find Wi-Fi interface
IFACE=$(sudo nmcli -t -f DEVICE,TYPE device status | awk -F: '$2=="wifi"{print $1; exit}')
if [[ -z "$IFACE" ]]; then
    log "❌ No Wi-Fi interface found"
    exit 1
fi
log "Using Wi-Fi interface: $IFACE"

# Helper: check if clients are connected to hotspot
client_connected() {
    # Try using iw to check for stations
    if sudo iw dev "$IFACE" station dump 2>/dev/null | grep -q 'Station'; then
        return 0
    fi
    
    # Fallback to hostapd_cli
    if command -v hostapd_cli &>/dev/null; then
        if sudo hostapd_cli -i "$IFACE" all_sta 2>/dev/null | grep -qE '^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}'; then
            return 0
        fi
    fi
    
    # Check ARP table
    if ip neigh show dev "$IFACE" | grep -q 'REACHABLE'; then
        return 0
    fi
    
    return 1
}

# Helper: get signal strength of current wifi connection
get_signal_strength() {
    local ssid="$1"
    sudo nmcli device wifi list ifname "$IFACE" | grep "$ssid" | awk '{print $6}' | head -1
}

# Step 1: Save and tear down current connection
log "Step 1: Tearing down current network connection"
CURRENT_CONN=$(sudo nmcli -t -f NAME,DEVICE connection show --active | awk -F: -v dev="$IFACE" '$2==dev{print $1}')
if [[ -n "$CURRENT_CONN" ]]; then
    log "Disconnecting from: $CURRENT_CONN"
    sudo nmcli connection down "$CURRENT_CONN"
else
    log "No active WiFi connection found"
fi

# Clean up any existing hotspot connection
if sudo nmcli connection show | grep -q "$CONN_NAME"; then
    log "Removing existing hotspot connection: $CONN_NAME"
    sudo nmcli connection delete "$CONN_NAME" || true
fi

# Step 2: Start hotspot and monitor for specified duration
log "Step 2: Starting hotspot '$HOST_SSID' for $((HOTSPOT_DURATION/60)) minutes"
sudo nmcli device wifi hotspot ifname "$IFACE" ssid "$HOST_SSID" password "$HOTSPOT_PSK" con-name "$CONN_NAME"

log "Hotspot active - monitoring for connections"
sudo nmcli -f NAME,UUID,TYPE,DEVICE connection show --active | grep -i "$CONN_NAME" || true

# Monitor hotspot for specified duration
start_time=$(date +%s)
connected_clients=0
while true; do
    current_time=$(date +%s)
    elapsed=$((current_time - start_time))
    
    if [ $elapsed -ge $HOTSPOT_DURATION ]; then
        break
    fi
    
    if client_connected; then
        connected_clients=$((connected_clients + 1))
        log "✅ Client connected to hotspot '$HOST_SSID' (total connections: $connected_clients)"
    else
        log "Monitoring hotspot '$HOST_SSID' - no clients connected (${elapsed}s/${HOTSPOT_DURATION}s)"
    fi
    
    sleep 30
done

log "Hotspot phase completed - connected clients during test: $connected_clients"

# Step 3: Tear down hotspot
log "Step 3: Tearing down hotspot"
sudo nmcli connection down "$CONN_NAME" || true
sudo nmcli connection delete "$CONN_NAME" || true

# Step 4: Connect to secondary WiFi network
log "Step 4: Connecting to secondary WiFi: $SECONDARY_SSID"
if sudo nmcli device wifi connect "$SECONDARY_SSID" password "$SECONDARY_PSK" ifname "$IFACE"; then
    log "✅ Connected to $SECONDARY_SSID"
    
    # Monitor connection for specified duration
    log "Monitoring WiFi connection for $((WIFI_DURATION/60)) minutes"
    start_time=$(date +%s)
    connection_checks=0
    successful_checks=0
    
    while true; do
        current_time=$(date +%s)
        elapsed=$((current_time - start_time))
        
        if [ $elapsed -ge $WIFI_DURATION ]; then
            break
        fi
        
        connection_checks=$((connection_checks + 1))
        
        # Check if still connected
        if sudo nmcli -t -f NAME,DEVICE connection show --active | grep -q "$SECONDARY_SSID"; then
            successful_checks=$((successful_checks + 1))
            signal_strength=$(get_signal_strength "$SECONDARY_SSID")
            log "✅ Connected to $SECONDARY_SSID - Signal: ${signal_strength:-N/A} (${elapsed}s/${WIFI_DURATION}s)"
        else
            log "❌ Lost connection to $SECONDARY_SSID - attempting reconnect"
            sudo nmcli device wifi connect "$SECONDARY_SSID" password "$SECONDARY_PSK" ifname "$IFACE" || true
        fi
        
        sleep 60  # Check every minute
    done
    
    connection_stability=$((successful_checks * 100 / connection_checks))
    log "WiFi monitoring completed - Connection stability: ${connection_stability}% (${successful_checks}/${connection_checks})"
    
else
    log "❌ Failed to connect to secondary WiFi: $SECONDARY_SSID"
fi

# Step 5: Restore original connection if possible
if [[ -n "$CURRENT_CONN" ]]; then
    log "Step 5: Attempting to restore original connection: $CURRENT_CONN"
    if sudo nmcli connection up "$CURRENT_CONN"; then
        log "✅ Restored connection to $CURRENT_CONN"
    else
        log "❌ Failed to restore original connection"
    fi
else
    log "Step 5: No original connection to restore"
fi

log "✅ Hotspot test completed successfully"
