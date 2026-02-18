#!/system/bin/sh

# ==============================================================================
# BeServer Container Status Check
# ==============================================================================

# Source shared utilities
SCRIPTS_DIR=$(cd "$(dirname "$0")" && pwd)
. "$SCRIPTS_DIR/utils.sh"

check_container_status
STATUS=$?

echo "----------------------------------------"
echo "Container: $CHROOT_DIR"
case $STATUS in
    0)
        echo "Status: RUNNING (Mounted + Process)"
        # Check fake_systemd specific status
        # Note: grep pattern might need to be flexible for different ps outputs
        if $BB ps -ef | $BB grep "runsvdir" | $BB grep "fake_systemd" | $BB grep -v grep >/dev/null; then
            echo "Service Manager: ACTIVE (fake_systemd)"
            echo ""
            # Try to list services if systemctl is available
            if [ -x "$CHROOT_DIR/opt/fake_systemd/bin/fake_systemd" ]; then
                 # Capture output to variable to check if empty
                 OUTPUT=$($BB chroot "$CHROOT_DIR" /opt/fake_systemd/bin/fake_systemd status 2>&1)
                 if [ -z "$OUTPUT" ]; then
                     echo "--- No Active Services ---"
                 else
                     echo "--- Active Services ---"
                     echo "$OUTPUT"
                 fi
            fi
        else
            echo "Service Manager: STOPPED (or crashed)"
        fi
        ;;
    1)
        echo "Status: PARTIAL (Mounted only)"
        echo "Hint: Services might be stopped or failed to start."
        ;;
    2)
        echo "Status: STOPPED"
        ;;
esac
echo "----------------------------------------"

exit $STATUS
