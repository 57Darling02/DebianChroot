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
# Try to stop runit gracefully if possible (optional, but good practice)
# But since we are killing everything, we can skip to killing processes.

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
