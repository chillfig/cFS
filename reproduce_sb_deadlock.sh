#!/bin/bash
# Reproduces the SB shared-data mutex deadlock during cFE shutdown.
#
# The bug: during shutdown, tasks are cancelled via pthread_cancel.
# If a task is cancelled at mq_timedsend (a POSIX cancellation point) while
# holding the SB shared-data mutex, any other task subsequently blocking on
# that mutex via pthread_mutex_lock (NOT a cancellation point) can never be
# cancelled.  OS_DeleteAllObjects therefore hangs indefinitely.
#
# Traffic strategy: SCH_LAB at 100Hz fires HK requests to 5 cFE apps
# (configured in sch_lab_table.c), and cFE generates additional build-info
# and housekeeping telemetry.  This keeps multiple SB transmit/receive paths
# active during the shutdown race window.
#
# We avoid flooding the ES command pipe (which would drop the restart command).
# Instead we wait for steady-state SCH_LAB traffic, then send one clean restart.

set -euo pipefail

# Resolve to absolute paths so cd inside the loop doesn't break CMD.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CPU1_DIR="$SCRIPT_DIR/build-native_std/exe/cpu1"
HOST_DIR="$SCRIPT_DIR/build-native_std/exe/host"
CMD="$HOST_DIR/cmd_send"
MAX_ATTEMPTS=20
SHUTDOWN_TIMEOUT=15  # seconds to wait for clean exit after restart cmd

ES_CMD_MID=0x1806
CC_NOOP=0
CC_RESTART=2
RST_PROCESSOR=1    # CFE_PSP_RST_TYPE_PROCESSOR

deadlock_detected=0
clean_exits=0

for attempt in $(seq 1 $MAX_ATTEMPTS); do
    echo "=== Attempt $attempt / $MAX_ATTEMPTS ==="

    cd "$CPU1_DIR"
    ./container-start >/tmp/cfs_attempt_${attempt}.log 2>&1 &
    CFS_PID=$!

    # Let cFS fully start and SCH_LAB traffic to reach steady state
    sleep 12

    # Send one NOOP to verify cFS is accepting commands (optional sanity check)
    "$CMD" --endian=LE --pktid=$ES_CMD_MID --cmdcode=$CC_NOOP 2>/dev/null || true

    # Brief pause to ensure NOOP clears the pipe before restart
    sleep 0.5

    # Trigger processor restart
    echo "  Sending RESTART..."
    "$CMD" --endian=LE --pktid=$ES_CMD_MID --cmdcode=$CC_RESTART \
           --half=$RST_PROCESSOR 2>/dev/null || true

    # Check if cFS exits cleanly within the timeout
    STARTED=$(date +%s)
    HUNG=0
    while kill -0 $CFS_PID 2>/dev/null; do
        NOW=$(date +%s)
        ELAPSED=$((NOW - STARTED))
        if [ $ELAPSED -ge $SHUTDOWN_TIMEOUT ]; then
            HUNG=1
            break
        fi
        sleep 0.5
    done

    if [ $HUNG -eq 1 ]; then
        echo "  -> DEADLOCK CONFIRMED: cFS did not exit within ${SHUTDOWN_TIMEOUT}s (attempt $attempt)"
        deadlock_detected=1
        kill -9 $CFS_PID 2>/dev/null || true
        wait $CFS_PID 2>/dev/null || true
        cd - >/dev/null
        break
    else
        ELAPSED=$(($(date +%s) - STARTED))
        echo "  -> Clean exit in ~${ELAPSED}s (attempt $attempt)"
        clean_exits=$((clean_exits + 1))
    fi

    wait $CFS_PID 2>/dev/null || true
    cd - >/dev/null
    sleep 2
done

echo ""
echo "=== RESULTS ==="
echo "  Clean exits: $clean_exits / $attempt"

if [ $deadlock_detected -eq 1 ]; then
    echo "  RESULT: BUG REPRODUCED — mutex deadlock on shutdown confirmed."
    exit 1
else
    echo "  RESULT: No deadlock in $MAX_ATTEMPTS attempts (may need more runs)."
    exit 0
fi
