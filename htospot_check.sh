#!/usr/bin/env bash
# hotspot-test.sh — spin up a Wi-Fi hotspot for 60 s and then tear it down

set -euo pipefail

# Parameters
HOTSPOT_SSID="Orin-Hotspot-Test"
HOTSPOT_PSK="TestPass1234"
DURATION=60   # seconds to keep hotspot active

# 1) Identify the Wi-Fi interface
IFACE=$(nmcli -t -f DEVICE,TYPE device status | awk -F: '$2=="wifi"{print $1; exit}')
if [[ -z "$IFACE" ]]; then
  echo "❌ No Wi-Fi interface found."
  exit 1
fi
echo "→ Using Wi-Fi interface: $IFACE"

# 2) Save existing connection (if any) so we can restore it later
CURRENT_CONN=$(nmcli -t -f NAME,DEVICE connection show --active | awk -F: -v dev="$IFACE" '$2==dev{print $1}')
if [[ -n "$CURRENT_CONN" ]]; then
  echo "→ Storing currently active connection: $CURRENT_CONN"
  nmcli connection down "$CURRENT_CONN"
fi

# 3) Start hotspot
echo "→ Starting hotspot \"$HOTSPOT_SSID\" on $IFACE..."
nmcli device wifi hotspot ifname "$IFACE" ssid "$HOTSPOT_SSID" password "$HOTSPOT_PSK"

# 4) Show hotspot status
echo "→ Hotspot active. Details:"
nmcli -f NAME,UUID,TYPE,DEVICE connection show --active | grep hotspot || true
nmcli device status | grep "$IFACE"

echo "→ Hotspot will run for $DURATION seconds..."
sleep "$DURATION"

# 5) Tear down hotspot
echo "→ Stopping hotspot..."
nmcli connection down "$HOTSPOT_SSID" || true
nmcli connection delete "$HOTSPOT_SSID" || true

# 6) Restore previous Wi-Fi connection (if any)
if [[ -n "$CURRENT_CONN" ]]; then
  echo "→ Restoring connection: $CURRENT_CONN"
  nmcli connection up "$CURRENT_CONN"
fi

echo "✅ Hotspot test complete."
