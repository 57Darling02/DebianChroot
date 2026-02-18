#!/system/bin/sh

# ==============================================================================
# BeServer Container Stop Script
# ==============================================================================

# Source shared utilities
SCRIPTS_DIR=$(cd "$(dirname "$0")" && pwd)
. "$SCRIPTS_DIR/utils.sh"

# Check root permissions
if [ "$(id -u)" -ne 0 ]; then
    log_error "This script must be run as root."
    exit 1
fi

log_info "Stopping container services..."

# 1. Stop Services
# ------------------------------------------------------------------------------
# Try to stop runit gracefully if possible
if [ -x "$CHROOT_DIR/opt/fake_systemd/bin/fake_systemd" ]; then
    log_info "Stopping fake_systemd services..."
    # We can add a 'shutdown' command to fake_systemd later, 
    # for now we kill the runsvdir process which stops supervision.
    # Ideally, we should stop all services first.
    
    # Optional: Stop all services (might be slow)
    # $BB chroot "$CHROOT_DIR" /opt/fake_systemd/bin/fake_systemd stop all
    
    # Kill runsvdir to release locks
    pkill -f "runsvdir -P .*fake_systemd"
fi

# 2. Kill Processes
# ------------------------------------------------------------------------------
kill_chroot_processes
# Wait for processes to die
sleep 2

# 3. Unmount Filesystems (Reverse Order)
# ------------------------------------------------------------------------------
log_info "Unmounting filesystems..."

# Android Specific
# Note: Check utils.sh for is_mounted logic to avoid errors
safe_umount "$CHROOT_DIR/linkerconfig" "linkerconfig"
safe_umount "$CHROOT_DIR/apex" "apex"
safe_umount "$CHROOT_DIR/sdcard" "sdcard"
safe_umount "$CHROOT_DIR/data" "data"
safe_umount "$CHROOT_DIR/system" "system"

# Standard Linux
safe_umount "$CHROOT_DIR/tmp" "tmp"
safe_umount "$CHROOT_DIR/dev/shm" "dev/shm"
safe_umount "$CHROOT_DIR/dev/pts" "dev/pts"
safe_umount "$CHROOT_DIR/dev" "dev"
safe_umount "$CHROOT_DIR/sys" "sys"
safe_umount "$CHROOT_DIR/proc" "proc"

log_success "Container stopped successfully."
