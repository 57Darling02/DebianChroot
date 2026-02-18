#!/bin/sh

# Core Environment Setup

# 1. Path Auto-detection
_resolve_path() {
    local target="$1"
    if command -v readlink >/dev/null 2>&1; then
        readlink -f "$target"
    else
        # Fallback
        echo "$target"
    fi
}

REAL_PATH=$(_resolve_path "$0")
# If core.sh is sourced from main, REAL_PATH is core.sh path.
# We need ROOT_DIR.
# If sourced from main which is in /bin, ROOT_DIR is ..
# But simpler: assume core.sh is in lib/, so ROOT_DIR is ..
ROOT_DIR=$(dirname $(dirname "$REAL_PATH"))

# 2. Configuration Loading
# Load config from /etc/fake_systemd.conf if it exists (System-wide config)
if [ -f "/etc/fake_systemd.conf" ]; then
    . "/etc/fake_systemd.conf"
fi

# Load config from project root (Local override)
if [ -f "$ROOT_DIR/etc/fake_systemd.conf" ]; then
    . "$ROOT_DIR/etc/fake_systemd.conf"
fi

# 3. Service Directories (Self-contained)
# We enforce project-internal structure for isolation and consistency.
# External /etc/sv is ignored to avoid conflicts.

export SV_REPO="$ROOT_DIR/etc/sv"
export SV_ACTIVE="$ROOT_DIR/service"
export RUN_DIR="$ROOT_DIR/run"
export LOG_DIR="$ROOT_DIR/var/log"
export BIN_DIR="$ROOT_DIR/bin"

# 4. Toolchain Setup (BusyBox First)
# We prefer the embedded busybox to ensure consistent behavior across all distros.

BUSYBOX_BIN="$BIN_DIR/busybox"

if [ -x "$BUSYBOX_BIN" ]; then
    BB="$BUSYBOX_BIN"
else
    # Fallback for dev/test without busybox binary
    BB="busybox" 
    if ! command -v busybox >/dev/null 2>&1; then
       # echo "[ERROR] BusyBox not found in $BUSYBOX_BIN or PATH." >&2
       # Instead of exit, we might warn, but let's be strict for self-contained goal
       :
    fi
fi

# Helper to ensure symlink exists
ensure_symlink() {
    local applet="$1"
    local link_path="$BIN_DIR/$applet"
    if [ ! -e "$link_path" ]; then
        # We use system ln here because our internal tools might not be ready
        # If system ln fails, we try busybox ln if available
        if command -v ln >/dev/null 2>&1; then
             ln -sf "busybox" "$link_path"
        elif [ -x "$BUSYBOX_BIN" ]; then
             "$BUSYBOX_BIN" ln -sf "busybox" "$link_path"
        fi
    fi
}

# Runit Applets
ensure_symlink sv
ensure_symlink runsv
ensure_symlink runsvdir
ensure_symlink chpst

# Define commands using our specific BusyBox Symlinks
SV_CMD="$BIN_DIR/sv"
RUNSV_CMD="$BIN_DIR/runsv"
RUNSVDIR_CMD="$BIN_DIR/runsvdir"

# Standard Utilities (can be called via busybox binary directly)
MKDIR_CMD="$BB mkdir -p"
LN_CMD="$BB ln -sf"
RM_CMD="$BB rm -f"
GREP_CMD="$BB grep"
SED_CMD="$BB sed"
AWK_CMD="$BB awk"

# 5. Initialization & Health Check
# Ensure our private universe exists and is running

# Create directories
$MKDIR_CMD "$SV_REPO" "$SV_ACTIVE" "$RUN_DIR" "$LOG_DIR"

# Check if our private runsvdir is running
# We use a marker file or process check to identify OUR instance
PID_FILE="$RUN_DIR/runsvdir.pid"

check_daemon() {
    if [ -f "$PID_FILE" ]; then
        PID=$(cat "$PID_FILE")
        # Check if process is actually running using ps
        # Note: Busybox ps output format varies, so we keep it simple
        # We check if the PID exists AND if the command line contains our service directory
        # This prevents PID reuse issues
        if $BB ps -o pid,args | $GREP_CMD "^[[:space:]]*$PID" | $GREP_CMD -q "$SV_ACTIVE"; then
            return 0
        fi
    fi
    return 1
}

start_daemon() {
    # Start runsvdir in background, monitoring our private directory
    # nohup to detach, redirect output to log
    # We use setsid if available to truly detach, but nohup is standard
    nohup $RUNSVDIR_CMD -P "$SV_ACTIVE" > "$LOG_DIR/runsvdir.log" 2>&1 &
    echo $! > "$PID_FILE"
    # Give it a moment to initialize
    sleep 1
}

# Auto-start if not running
if ! check_daemon; then
    # Clean up stale PID file
    [ -f "$PID_FILE" ] && rm "$PID_FILE"
    start_daemon
fi
