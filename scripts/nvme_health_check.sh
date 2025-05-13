#!/usr/bin/env bash
# nvme_health_check.sh — light‑weight NVMe health & free‑space verifier
# Designed for Jetson AGX Orin with rootfs on /dev/nvme0n1
set -euo pipefail

DEV_CHAR=/dev/nvme0        # controller char dev
DEV_BLOCK=/dev/nvme0n1     # namespace block dev (your root)
LOGDIR=/var/log/nvme_health
TMPDIR=/tmp/nvme_free_space_test
TEST_MB=128                # size of each chunk we write/read (128 MiB)
CHUNKS=8                   # how many chunks to test (= 1 GiB total)

sudo mkdir -p "$LOGDIR" "$TMPDIR"
sudo sudo smartctl -a -x /dev/nvme0n1
info () { echo -e "\e[1;34m$*\e[0m"; }

############ 1. Baseline SMART ############################################
info "Collecting baseline SMART / error log ⏳"
(   echo "===== SMART baseline ====="
    date
    nvme smart-log "$DEV_CHAR"
    echo
    smartctl -x "$DEV_BLOCK"
) | sudo tee "$LOGDIR/pre_smart.txt" > /dev/null

############ 2. Short controller self‑test ################################
info "Startingextended NVMe self‑test (takes ~30 mins)…"
sudo nvme device-self-test "$DEV_CHAR" -s 1   # 2 = extended test

# Poll status every 10 s until done (Current operation == 0)
while :; do
    op=$(nvme self-test-log "$DEV_CHAR" | awk '/Current operation/{print $NF}')
    [[ "$op" == "0" ]] && break
    sleep 30
done
info "Self‑test finished."

sudo nvme self-test-log "$DEV_CHAR" | sudo tee "$LOGDIR/selftest_log.txt"

############ 3. Free‑space write / verify loop ############################
info "Exercising free space with ${CHUNKS}×${TEST_MB} MiB random blocks…"
cd "$TMPDIR"

for i in $(seq 1 "$CHUNKS"); do
    blk="blk${i}.bin"
    sha="blk${i}.sha256"

    dd if=/dev/urandom of="$blk" bs=1M count="$TEST_MB" oflag=direct status=none
    sha256sum "$blk" | tee "$sha" >/dev/null

    # flush to disk, then read back and verify
    sync
    sha256sum -c "$sha" || { echo "❌ checksum mismatch in $blk"; exit 1; }
    rm -f "$blk" "$sha"
    printf "  ✓ chunk %d verified\n" "$i"
done

sync
info "TRIMming freed blocks…"
sudo fstrim -v /

############ 4. Post‑test SMART ###########################################
info "Collecting SMART after tests…"
(   echo "===== SMART after ====="
    date
    nvme smart-log "$DEV_CHAR"
    echo
    smartctl -x "$DEV_BLOCK"
) | sudo tee "$LOGDIR/post_smart.txt" > /dev/null

info "✅ NVMe health check complete. Logs in $LOGDIR"

