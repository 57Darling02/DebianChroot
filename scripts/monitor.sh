#!/system/bin/sh
# ==============================================================================
# BeServer Status Monitor
# Updates module.prop description with container status
# ==============================================================================

# 1. Source shared utilities
SCRIPTS_DIR=$(cd "$(dirname "$0")" && pwd)
. "$SCRIPTS_DIR/utils.sh"

PROP_FILE="$MODDIR/module.prop"
BASE_DESC="DebianChroot" # Base description to preserve

# Ensure module.prop exists
if [ ! -f "$PROP_FILE" ]; then
    log_error "monitor: module.prop not found at $PROP_FILE"
    exit 1
fi

log_info "Starting status monitor..."

# 2. Main Loop
while true; do
    # Check container status using utils.sh function
    # Returns: 0=Running, 1=Mounted (Partial), 2=Stopped
    check_container_status
    STATUS_CODE=$?
    
    # Check fake_systemd Daemon Status (Only if container is running)
    DAEMON_STATUS=""
    if [ "$STATUS_CODE" -eq 0 ]; then
         # Check if fake_systemd's runsvdir is running
         if $BB ps -ef | $BB grep "runsvdir -P .*fake_systemd" | $BB grep -v grep >/dev/null; then
             DAEMON_STATUS="✅"
         else
             DAEMON_STATUS="⚠️" # Daemon crashed or stopped
             # Auto-restart logic?
             # nohup chroot ... fake_systemd init &
         fi
    fi
    
    # Get current time using busybox for consistency
    TIMESTAMP=$($BB date "+%H:%M:%S")
    
    # Determine status message with emojis
    case $STATUS_CODE in
        0)
            STATUS_MSG="😋 运行中 | Running $DAEMON_STATUS"
            ;;
        1)
            STATUS_MSG="🤔 仅挂载 | Mounted"
            ;;
        2)
            STATUS_MSG="😵 已停止 | Stopped"
            ;;
        *)
            STATUS_MSG="🧐 未知 | Unknown"
            ;;
    esac
    
    # Construct new description line
    # Format: description=DebianChroot 😋 运行中 | Running [12:30:45]
    NEW_DESC="description=$BASE_DESC $STATUS_MSG [$TIMESTAMP]"
    
    # Atomically update the description line in module.prop
    # We use busybox sed to ensure compatibility
    $BB sed -i "s/^description=.*/$NEW_DESC/" "$PROP_FILE"
    
    # Wait for 10 seconds
    sleep 10
done
