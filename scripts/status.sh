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
        echo -e "Status: ${GREEN}RUNNING${NC} (Mounted + Runit)"
        ;;
    1)
        echo -e "Status: ${YELLOW}PARTIAL${NC} (Mounted only)"
        echo "Hint: Services might be stopped or failed to start."
        ;;
    2)
        echo -e "Status: ${RED}STOPPED${NC}"
        ;;
esac
echo "----------------------------------------"

exit $STATUS
