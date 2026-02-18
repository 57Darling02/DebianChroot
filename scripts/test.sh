#!/system/bin/sh

# ==============================================================================
# fake_systemd Diagnostic Tool
# ==============================================================================

SCRIPTS_DIR=$(cd "$(dirname "$0")" && pwd)
. "$SCRIPTS_DIR/utils.sh"

echo "========================================================"
echo "           fake_systemd Diagnostic Tool                 "
echo "========================================================"
echo "Time: $(date)"
echo "Container: $CHROOT_DIR"
echo "========================================================"

# 1. File System Check
echo "[1] Checking Mount Points..."
MISSING_MOUNTS=0
for mount in "proc" "sys" "dev" "dev/pts" "dev/shm"; do
    if $BB mount | grep -q "$CHROOT_DIR/$mount"; then
        echo "  [OK] $mount mounted"
    else
        echo "  [FAIL] $mount NOT mounted"
        MISSING_MOUNTS=1
    fi
done

# 2. Binary & Permissions Check
echo ""
echo "[2] Checking Binaries..."
FAKE_BIN="$CHROOT_DIR/opt/fake_systemd/bin/fake_systemd"
BUSYBOX_BIN="$CHROOT_DIR/opt/fake_systemd/bin/busybox"

if [ -f "$FAKE_BIN" ]; then
    if [ -x "$FAKE_BIN" ]; then
        echo "  [OK] fake_systemd binary exists and executable"
    else
        echo "  [FAIL] fake_systemd binary exists but NOT executable"
        ls -l "$FAKE_BIN"
    fi
else
    echo "  [FAIL] fake_systemd binary NOT found at $FAKE_BIN"
fi

if [ -f "$BUSYBOX_BIN" ]; then
    echo "  [OK] Internal BusyBox exists"
else
    echo "  [FAIL] Internal BusyBox NOT found at $BUSYBOX_BIN"
fi

# 3. Process Check
echo ""
echo "[3] Checking Processes..."
echo "  --- runsvdir processes ---"
$BB ps -ef | grep runsvdir | grep -v grep
echo "  --------------------------"

# 4. Dry Run (The most important part)
echo ""
echo "[4] Attempting Dry Run..."
echo "  Trying to chroot and run fake_systemd check-env..."

if [ ! -d "$CHROOT_DIR" ]; then
    echo "  [FATAL] Chroot directory does not exist!"
    exit 1
fi

# Check if /bin/sh exists in chroot
if [ ! -f "$CHROOT_DIR/bin/sh" ] && [ ! -L "$CHROOT_DIR/bin/sh" ]; then
    echo "  [FAIL] /bin/sh missing in chroot! Script cannot run."
else
    echo "  [OK] /bin/sh exists."
fi

echo "  > Running: chroot ... fake_systemd check-env"
# We explicitly use chroot command
$BB chroot "$CHROOT_DIR" /opt/fake_systemd/bin/fake_systemd check-env
RET=$?

if [ $RET -eq 0 ]; then
    echo "  [OK] check-env successful. Environment seems sane."
else
    echo "  [FAIL] check-env failed with code $RET"
    echo "  Possible reasons: missing libraries, wrong architecture, or path issues."
fi

echo ""
echo "[5] Manual Daemon Start Attempt"
echo "  I will now try to start the daemon in foreground for 5 seconds..."
echo "  Capture this output!"
echo "  --------------------------------------------------------"

# Create a temporary script inside chroot to run init
cat <<EOF > "$CHROOT_DIR/tmp/debug_init.sh"
#!/bin/sh
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
echo "Inside chroot. ID: \$(id)"
echo "Starting fake_systemd init..."
/opt/fake_systemd/bin/fake_systemd init
EOF
chmod +x "$CHROOT_DIR/tmp/debug_init.sh"

# Run it in background
$BB chroot "$CHROOT_DIR" /tmp/debug_init.sh &
PID=$!
echo "  Process started with PID $PID on host."
sleep 5

if kill -0 $PID 2>/dev/null; then
    echo "  [OK] Process is still running after 5 seconds."
    # Kill it to clean up
    kill $PID
else
    echo "  [FAIL] Process died immediately!"
fi

rm "$CHROOT_DIR/tmp/debug_init.sh"

echo "========================================================"
echo "Diagnostic Complete."
