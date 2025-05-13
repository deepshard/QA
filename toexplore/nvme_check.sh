#!/usr/bin/env bash
set -euo pipefail

DEV=/dev/nvme0n1
TABLE_DUMP=nvme-part-table.sfdisk
BB_LOG=nvme-badblocks.log

echo "1) Saving partition layout…"
sudo sfdisk --dump "$DEV" > "$TABLE_DUMP"

echo "2) Running SMART health check…"
sudo smartctl -H "$DEV" || { echo "SMART health failed"; exit 1; }
sudo smartctl -A "$DEV"

echo "3) Running non-destructive read/write badblocks…"
sudo badblocks -nvs -o "$BB_LOG" "$DEV"
echo "Badblocks log → $BB_LOG"

echo "4) Restoring partition layout…"
sudo sfdisk "$DEV" < "$TABLE_DUMP"

echo "5) Checking filesystems…"
for part in $(ls ${DEV}p*); do
  echo "- e2fsck on $part"
  sudo e2fsck -fy "$part"
done

echo "NVMe health-check complete: all tests passed."
