#!/usr/bin/env bash
set -euo pipefail

DEV=/dev/mmcblk0
TABLE_DUMP=emmc-part-table.sfdisk
BB_LOG=emmc-badblocks.log

echo "Saving eMMC partition layout…"
sudo sfdisk --dump "$DEV" > "$TABLE_DUMP"

echo "SMART (if supported) or basic info…"
sudo smartctl -i "$DEV" || echo "SMART not supported on eMMC"

echo "Running non-destructive badblocks…"
sudo badblocks -nvs -o "$BB_LOG" "$DEV"

echo "Restoring partition layout…"
sudo sfdisk "$DEV" < "$TABLE_DUMP"

echo "Checking filesystems…"
for part in $(ls ${DEV}p*); do
  echo "- e2fsck on $part"
  sudo e2fsck -fy "$part"
done

echo "eMMC health-check complete."
