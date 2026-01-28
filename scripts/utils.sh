#!/system/bin/sh

# ==============================================================================
# Shared Environment & Utilities for BeServer
# ==============================================================================

# 1. Path Resolution
# ------------------------------------------------------------------------------
# Get absolute path of the scripts directory
SCRIPTS_DIR=$(cd "$(dirname "$0")" && pwd)
# Module root is one level up
MODDIR=$(dirname "$SCRIPTS_DIR")
CHROOT_DIR="/data/DebianChroot"
LOG_FILE="$MODDIR/module.log"

# 2. Busybox Resolution
# ------------------------------------------------------------------------------
# Priority: Module Tools > Magisk Internal > System
if [ -x "$MODDIR/tools/bin/busybox" ]; then
    BB="$MODDIR/tools/bin/busybox"
elif [ -x "/data/adb/magisk/busybox" ]; then
    BB="/data/adb/magisk/busybox"
else
    BB="busybox"
fi

# 3. Logging Utilities
# ------------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to write to log file without colors
write_log() {
    # Get current timestamp
    local timestamp=$($BB date "+%Y-%m-%d %H:%M:%S")
    # Remove ANSI color codes for file log
    local clean_msg=$(echo "$1" | $BB sed 's/\x1b\[[0-9;]*m//g')
    echo "[$timestamp] $clean_msg" >> "$LOG_FILE"
}

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
    write_log "[INFO] $1"
}

log_success() {
    echo -e "${GREEN}[OK]${NC} $1"
    write_log "[OK] $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
    write_log "[WARN] $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
    write_log "[ERROR] $1"
}

# 4. Status Checks
# ------------------------------------------------------------------------------
is_mounted() {
    $BB mount | $BB grep -q " $1 "
}

check_container_status() {
    local is_mounted=0
    local is_running=0

    # Check essential mount
    if is_mounted "$CHROOT_DIR/proc"; then
        is_mounted=1
    fi

    # Check runit process
    # We look for runsvdir running specifically for our service directory
    if $BB ps -ef | $BB grep -v grep | $BB grep "runsvdir -P /etc/service" >/dev/null; then
        is_running=1
    fi

    if [ "$is_mounted" -eq 1 ] && [ "$is_running" -eq 1 ]; then
        return 0 # Fully Running
    elif [ "$is_mounted" -eq 1 ]; then
        return 1 # Mounted but not running
    else
        return 2 # Stopped
    fi
}

# 5. Process Management
# ------------------------------------------------------------------------------
kill_chroot_processes() {
    log_info "Killing processes in $CHROOT_DIR..."
    
    # Iterate through all processes in /proc
    for pid in /proc/[0-9]*; do
        [ -d "$pid" ] || continue
        pid_num=${pid##*/}
        
        # Check root of the process
        root_path=$($BB readlink -f "/proc/$pid_num/root" 2>/dev/null)
        
        if [ "$root_path" = "$CHROOT_DIR" ]; then
            # log_info "Killing PID $pid_num..."
            kill -9 "$pid_num" 2>/dev/null
        fi
    done
}

# 6. Mount Management
# ------------------------------------------------------------------------------
safe_umount() {
    local mnt="$1"
    local desc="$2"
    
    # Check if mounted
    if ! is_mounted "$mnt"; then
        return 0
    fi

    # 1. Try normal unmount
    if $BB umount "$mnt" 2>/dev/null; then
        log_success "Unmounted $desc"
        return 0
    fi

    # 2. Try killing processes accessing the mount point (using fuser if avail)
    if $BB fuser -mvk "$mnt" >/dev/null 2>&1; then
        sleep 1
        if $BB umount "$mnt" 2>/dev/null; then
            log_success "Unmounted $desc (after cleanup)"
            return 0
        fi
    fi

    # 3. Lazy unmount
    if $BB umount -l "$mnt" 2>/dev/null; then
        log_warn "Lazy unmounted $desc"
        return 0
    fi

    log_error "Failed to unmount $desc"
    return 1
}

# 7. Network & Permission Fixes
# ------------------------------------------------------------------------------
fix_network_permissions() {
    local chroot_dir="$1"
    
    log_info "Fixing network and permissions..."

    # 1. Fix resolv.conf (Always overwrite to ensure valid DNS)
    # Remove existing file/symlink to avoid issues with broken links (e.g. systemd-resolved links)
    if [ -L "$chroot_dir/etc/resolv.conf" ] || [ -f "$chroot_dir/etc/resolv.conf" ]; then
        $BB rm -f "$chroot_dir/etc/resolv.conf"
    fi
    
    # Using Google DNS and Cloudflare DNS
    echo "nameserver 8.8.8.8" > "$chroot_dir/etc/resolv.conf"
    echo "nameserver 1.1.1.1" >> "$chroot_dir/etc/resolv.conf"
    echo "nameserver 223.5.5.5" >> "$chroot_dir/etc/resolv.conf" # AliDNS as backup
    $BB chmod 644 "$chroot_dir/etc/resolv.conf"

    # 2. Android Paranoid Network & Hardware Groups
    # Ref: https://android.googlesource.com/platform/system/core/+/master/libcutils/include/private/android_filesystem_config.h
    # Full list from linux-manager.sh to ensure maximum compatibility
    local groups="
    1001:aid_radio
    1002:aid_bluetooth
    1003:aid_graphics
    1004:aid_input
    1005:aid_audio
    1006:aid_camera
    1007:aid_log
    1008:aid_compass
    1009:aid_mount
    1010:aid_wifi
    1011:aid_adb
    1012:aid_install
    1013:aid_media
    1014:aid_dhcp
    1015:aid_sdcard_rw
    1016:aid_vpn
    1017:aid_keystore
    1018:aid_usb
    1019:aid_drm
    1020:aid_mdnsr
    1021:aid_gps
    1023:aid_media_rw
    1024:aid_mtp
    1026:aid_drmrpc
    1027:aid_nfc
    1028:aid_sdcard_r
    1029:aid_clat
    1030:aid_loop_radio
    1031:aid_media_drm
    1032:aid_package_info
    1033:aid_sdcard_pics
    1034:aid_sdcard_av
    1035:aid_sdcard_all
    1036:aid_logd
    1037:aid_shared_relro
    1038:aid_dbus
    1039:aid_tlsdate
    1040:aid_media_ex
    1041:aid_audioserver
    1042:aid_metrics_coll
    1043:aid_metricsd
    1044:aid_webserv
    1045:aid_debuggerd
    1046:aid_media_codec
    1047:aid_cameraserver
    1048:aid_firewall
    1049:aid_trunks
    1050:aid_nvram
    1051:aid_dns
    1052:aid_dns_tether
    1053:aid_webview_zygote
    1054:aid_vehicle_network
    1055:aid_media_audio
    1056:aid_media_video
    1057:aid_media_image
    1058:aid_tombstoned
    1059:aid_media_obb
    1060:aid_ese
    1061:aid_ota_update
    1062:aid_automotive_evs
    1063:aid_lowpan
    1064:aid_hsm
    1065:aid_reserved_disk
    1066:aid_statsd
    1067:aid_incidentd
    1068:aid_secure_element
    1069:aid_lmkd
    1070:aid_llkd
    1071:aid_iorapd
    1072:aid_gpu_service
    1073:aid_network_stack
    2000:aid_shell
    2001:aid_cache
    2002:aid_diag
    2900:aid_oem_reserved_start
    2999:aid_oem_reserved_end
    3001:aid_net_bt_admin
    3002:aid_net_bt
    3003:aid_inet
    3004:aid_net_raw
    3005:aid_net_admin
    3006:aid_net_bw_stats
    3007:aid_net_bw_acct
    3009:aid_readproc
    3010:aid_wakelock
    3011:aid_uhid
    9997:aid_everybody
    9998:aid_misc
    9999:aid_nobody
    "

    local group_file="$chroot_dir/etc/group"
    
    # Iterate through groups
    echo "$groups" | while read -r line; do
        # Skip empty lines
        [ -z "$line" ] && continue
        
        gid=${line%%:*}
        name=${line#*:}
        
        # Check if group exists (by GID)
        if $BB grep -q ":$gid:" "$group_file"; then
            # Group exists, ensure root is a member
            # We use sed to append ,root if not present
            if ! $BB grep -q ":$gid:.*root" "$group_file"; then
                # Append root to the group list
                $BB sed -i "s/^\([^:]*:[^:]*:$gid:[^:]*\)$/\1,root/" "$group_file"
                # If the group list was empty (ends with :), handle that
                $BB sed -i "s/^\([^:]*:[^:]*:$gid:\)$/\1root/" "$group_file"
            fi
        else
            # Group does not exist, append it
            echo "$name:x:$gid:root" >> "$group_file"
        fi
    done

    # 3. Fix _apt user permissions (Critical for Debian/Ubuntu apt networking)
    # _apt user needs to be in aid_inet (3003) to access network sockets
    
    # Dynamic detection of usermod path (adapted from linux-manager.sh)
    local usermod_path=$($BB chroot "$chroot_dir" which usermod 2>/dev/null)
    # Validate path
    if [ -z "$usermod_path" ] || [ ! -x "$(echo "$usermod_path" | $BB sed "s#^/#$chroot_dir/#")" ]; then
        usermod_path="/sbin/usermod"
        if [ ! -x "$chroot_dir$usermod_path" ]; then
            usermod_path="/usr/sbin/usermod"
        fi
    fi
    
    local usermod_bin=$($BB basename "$usermod_path")
    local usermod_cmd="$usermod_path" # Use full path inside chroot if needed, but chroot usually needs relative to root or PATH
    
    # We will use 'chroot $chroot_dir usermod ...' so we need the path relative to chroot root?
    # Actually 'which' returns /usr/sbin/usermod.
    # We should run: $BB chroot "$chroot_dir" "$usermod_bin" ... if it's in PATH, or full path.
    # linux-manager.sh uses $usermod_bin (basename) assuming it's in PATH.
    
    if [ -x "$chroot_dir$usermod_path" ]; then
        log_info "Using $usermod_bin to fix permissions..."
        
        # 3.1 Fix root permissions (Add to Android core groups)
        # Copied from linux-manager.sh
        local core_groups="aid_inet,aid_sdcard_rw,aid_sdcard_all,aid_media_rw,aid_net_bt,aid_net_admin,aid_everybody,aid_shell,aid_mount,aid_log"
        local ext_groups="aid_radio,aid_bluetooth,aid_graphics,aid_input,aid_audio,aid_camera,aid_compass,aid_wifi,aid_adb,aid_install,aid_media,aid_dhcp,aid_vpn,aid_keystore,aid_usb,aid_drm,aid_mdnsr,aid_gps,aid_mtp,aid_drmrpc,aid_nfc,aid_sdcard_r,aid_clat,aid_loop_radio,aid_media_drm,aid_package_info,aid_sdcard_pics,aid_sdcard_av,aid_logd,aid_shared_relro,aid_dbus,aid_tlsdate,aid_media_ex,aid_audioserver,aid_metrics_coll,aid_metricsd,aid_webserv,aid_debuggerd,aid_media_codec,aid_cameraserver,aid_firewall,aid_trunks,aid_nvram,aid_dns,aid_dns_tether,aid_webview_zygote,aid_vehicle_network,aid_media_audio,aid_media_video,aid_media_image,aid_tombstoned,aid_media_obb,aid_ese,aid_ota_update,aid_automotive_evs,aid_lowpan,aid_hsm,aid_reserved_disk,aid_statsd,aid_incidentd,aid_secure_element,aid_lmkd,aid_llkd,aid_iorapd,aid_gpu_service,aid_network_stack,aid_cache,aid_diag,aid_oem_reserved_start,aid_oem_reserved_end,aid_net_bt_admin,aid_net_raw,aid_net_bw_stats,aid_net_bw_acct,aid_readproc,aid_wakelock,aid_uhid,aid_misc,aid_nobody,aid_app_start,aid_app_end,aid_cache_gid_start,aid_cache_gid_end,aid_ext_gid_start,aid_ext_gid_end,aid_ext_cache_gid_start,aid_ext_cache_gid_end,aid_shared_gid_start,aid_shared_gid_end,aid_isolated_start,aid_isolated_end,aid_user_offset"
        
        $BB chroot "$chroot_dir" "$usermod_bin" -a -G "$core_groups" root 2>/dev/null
        # $BB chroot "$chroot_dir" "$usermod_bin" -a -G "$ext_groups" root 2>/dev/null # Optional: Add extended groups if needed
        
        # 3.2 Fix _apt permissions
        if $BB chroot "$chroot_dir" id _apt >/dev/null 2>&1; then
             # Change PRIMARY group to aid_inet (3003)
             $BB chroot "$chroot_dir" "$usermod_bin" -g aid_inet _apt 2>/dev/null
             log_info "Fixed _apt primary group to aid_inet"
        fi
    else
        log_warn "usermod not found in container. Falling back to manual method."
        
        # Fallback Method: Change primary group in /etc/passwd to 3003 manually
        if $BB grep -q "^_apt:" "$chroot_dir/etc/passwd"; then
            local apt_gid=3003 # aid_inet
            $BB sed -i "s/^\(_apt:[^:]*:[^:]*\):[^:]*:/\1:$apt_gid:/" "$chroot_dir/etc/passwd"
        fi
    fi

    # Method 3: Disable APT sandbox (Force root) - The most reliable fix for Android
    # Keep this as ultimate fallback/safety net
    local apt_conf_dir="$chroot_dir/etc/apt/apt.conf.d"
    if [ -d "$chroot_dir/etc/apt" ]; then
         $BB mkdir -p "$apt_conf_dir"
         echo 'APT::Sandbox::User "root";' > "$apt_conf_dir/99android-permissions"
         $BB chmod 644 "$apt_conf_dir/99android-permissions"
         log_info "Applied APT sandbox fix (Run as root)"
    fi
    
    log_info "Fixed _apt user permissions"

    # 4. Create /etc/mtab if missing (Some tools like netstat/ping need this)
    if [ ! -e "$chroot_dir/etc/mtab" ]; then
        $BB ln -sf /proc/mounts "$chroot_dir/etc/mtab"
        log_info "Created /etc/mtab symlink"
    fi
    
    # 5. Enable IP Forwarding (often needed for networking)
    $BB sysctl -w net.ipv4.ip_forward=1 >/dev/null 2>&1
    
    log_success "Network and permissions fixed."
}
