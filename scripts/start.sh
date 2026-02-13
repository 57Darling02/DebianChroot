#!/system/bin/sh

# ==============================================================================
# BeServer Container Start Script
# ==============================================================================

# Source shared utilities
SCRIPTS_DIR=$(cd "$(dirname "$0")" && pwd)
. "$SCRIPTS_DIR/utils.sh"

# Check for root permissions
if [ "$(id -u)" -ne 0 ]; then
    log_error "This script must be run as root."
    exit 1
fi

# ==============================================================================
# Helper Functions (Local to Start)
# ==============================================================================

mount_fs() {
    local source="$1"
    local target="$2"
    local type="$3"
    local options="$4"

    # Create mount point if it doesn't exist
    if [ ! -d "$target" ]; then
        $BB mkdir -p "$target"
    fi

    if is_mounted "$target"; then
        return 0
    fi

    log_info "Mounting $target..."
    
    if [ "$type" = "bind" ]; then
        if ! $BB mount --bind "$source" "$target" 2>/dev/null; then
            # Fallback to system mount
            /system/bin/mount -o bind "$source" "$target"
        fi
    elif [ "$type" = "rbind" ]; then
        if ! $BB mount --rbind "$source" "$target" 2>/dev/null; then
             /system/bin/mount -o rbind "$source" "$target"
        fi
    else
        # Try with options first
        if ! $BB mount -t "$type" -o "$options" "$source" "$target" 2>/dev/null; then
             # Try without options (sometimes 'defaults' causes issues)
             if ! $BB mount -t "$type" "$source" "$target" 2>/dev/null; then
                 # Fallback to system mount
                 /system/bin/mount -t "$type" -o "$options" "$source" "$target"
             fi
        fi
    fi

    if [ $? -eq 0 ]; then
        log_success "Mounted $target"
    else
        log_error "Failed to mount $target"
    fi
}

# ==============================================================================
# Background Setup Logic
# ==============================================================================

setup_background() {
    # Check if already running
    check_container_status
    if [ $? -eq 0 ]; then
        log_info "Container is already running."
        return 0
    fi

    log_info "Starting background setup..."

    # 1. Prepare Host Environment
    # Ensure /dev/net/tun exists on host for VPN support
    if [ ! -c /dev/net/tun ]; then
        $BB mkdir -p /dev/net
        $BB mknod /dev/net/tun c 10 200
    fi

    # 2. Wait for Storage (Fix for boot timing)
    local retries=0
    while [ ! -d "/sdcard" ] && [ $retries -lt 30 ]; do
        sleep 1
        retries=$((retries + 1))
    done
    
    if [ ! -d "/sdcard" ]; then
        log_warn "Storage (/sdcard) not ready after waiting. Skipping sdcard mount."
    fi

    # 3. Essential System Mounts
    mount_fs "proc" "$CHROOT_DIR/proc" "proc" "defaults"
    mount_fs "sysfs" "$CHROOT_DIR/sys" "sysfs" "defaults"
    mount_fs "/dev" "$CHROOT_DIR/dev" "bind" ""
    mount_fs "devpts" "$CHROOT_DIR/dev/pts" "devpts" "mode=620,ptmxmode=000"
    mount_fs "tmpfs" "$CHROOT_DIR/dev/shm" "tmpfs" "mode=1777"
    mount_fs "tmpfs" "$CHROOT_DIR/tmp" "tmpfs" "mode=1777"
    mount_fs "tmpfs" "$CHROOT_DIR/run" "tmpfs" "mode=0755,nosuid,nodev"

    # 3. Android Specific Bind Mounts
    mount_fs "/system" "$CHROOT_DIR/system" "bind" "ro"
    mount_fs "/data" "$CHROOT_DIR/data" "bind" ""
    mount_fs "/sdcard" "$CHROOT_DIR/sdcard" "bind" ""
    
    # Mount APEX (Android 10+)
    if [ -d "/apex" ]; then
        mount_fs "/apex" "$CHROOT_DIR/apex" "rbind" ""
    fi
    
    # Mount linkerconfig (Android 11+)
    if [ -d "/linkerconfig" ]; then
        mount_fs "/linkerconfig" "$CHROOT_DIR/linkerconfig" "bind" "ro"
    fi

    # 4. Fix Special Files
    # Ensure standard streams exist
    if [ ! -e "$CHROOT_DIR/dev/stdin" ]; then $BB ln -sf /proc/self/fd/0 "$CHROOT_DIR/dev/stdin"; fi
    if [ ! -e "$CHROOT_DIR/dev/stdout" ]; then $BB ln -sf /proc/self/fd/1 "$CHROOT_DIR/dev/stdout"; fi
    if [ ! -e "$CHROOT_DIR/dev/stderr" ]; then $BB ln -sf /proc/self/fd/2 "$CHROOT_DIR/dev/stderr"; fi

    # 5. Network & Permissions Configuration
    fix_network_permissions "$CHROOT_DIR"

    # Ensure hosts file exists and is valid
    if [ ! -f "$CHROOT_DIR/etc/hosts" ] || [ -L "$CHROOT_DIR/etc/hosts" ]; then
        $BB rm -f "$CHROOT_DIR/etc/hosts"
        echo "127.0.0.1 localhost" > "$CHROOT_DIR/etc/hosts"
        echo "::1 localhost ip6-localhost" >> "$CHROOT_DIR/etc/hosts"
        $BB chmod 644 "$CHROOT_DIR/etc/hosts"
        log_success "Generated hosts file"
    fi

    # 6. Start Runit (Init System)
    if $BB ps -ef | $BB grep "runsvdir -P /etc/service" | $BB grep -v grep >/dev/null; then
        log_info "Runit is already running."
    else
        log_info "Starting Runit..."
        # Start runsvdir in background within chroot
        export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
        
        $BB nohup $BB chroot "$CHROOT_DIR" /usr/bin/runsvdir -P /etc/service >/dev/null 2>&1 &
        
        sleep 1
        if $BB ps -ef | $BB grep "runsvdir -P /etc/service" | $BB grep -v grep >/dev/null; then
            log_success "Runit started successfully."
        else
            log_error "Failed to start Runit."
        fi
    fi
}

# ==============================================================================
# Foreground Entry Logic
# ==============================================================================

enter_shell() {
    log_info "Entering container shell..."
    
    export TERM="xterm-256color"
    export HOME="/root"
    export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
    export TMPDIR="/tmp"
    export ANDROID_DATA="/data"
    export ANDROID_ROOT="/system"
    export ANDROID_ART_ROOT="/apex/com.android.art"
    export ANDROID_RUNTIME_ROOT="/apex/com.android.runtime"
    export ANDROID_I18N_ROOT="/apex/com.android.i18n"
    export ANDROID_TZDATA_ROOT="/apex/com.android.tzdata"
    
    # Unset variables that might conflict
    unset LD_PRELOAD
    unset PREFIX

    # Priority: su -> bash -> fallback su
    # We prefer 'su -l' because it calls initgroups() to apply supplementary groups (GIDs)
    # defined in /etc/group, which is critical for Android network permissions (aid_inet, aid_net_raw).
    local SU_PATH="/usr/bin/su"
    local BASH_PATH="/usr/bin/bash"
    local ENV_PATH="/usr/bin/env"

    if [ -x "$CHROOT_DIR$SU_PATH" ] && [ -x "$CHROOT_DIR$ENV_PATH" ]; then
        # Use env to clear environment if needed, but here we just call su -l
        # We assume su is in path inside chroot or at /usr/bin/su
        $BB chroot "$CHROOT_DIR" /usr/bin/su -l
    elif [ -x "$CHROOT_DIR$BASH_PATH" ]; then
        $BB chroot "$CHROOT_DIR" /usr/bin/bash -l
    else
        # Fallback to whatever /bin/sh or su is available
        $BB chroot "$CHROOT_DIR" su -l
    fi
}

# ==============================================================================
# Main Execution
# ==============================================================================

case "$1" in
    -b|--background)
        setup_background
        ;;
    -h|--help)
        echo "Usage: $0 [OPTIONS]"
        echo "  (No args)       Start background services (if needed) and enter shell"
        echo "  -b, --background Only start background services"
        echo "  -h, --help      Show this help message"
        ;;
    *)
        setup_background
        enter_shell
        ;;
esac
