#!/bin/sh

# fake_systemd Installation Script
# Supports installing into a chroot/container rootfs via DESTDIR

set -e

# Default paths
# We install to /opt/fake_systemd by default for isolation
PREFIX="/opt/fake_systemd"
DESTDIR=""

usage() {
    echo "Usage: $0 [options]"
    echo "Options:"
    echo "  --destdir DIR   Root directory for installation (default: /)"
    echo "  --prefix DIR    Installation prefix (default: /opt/fake_systemd)"
    echo "  --help          Show this help message"
    exit 1
}

# Parse arguments
while [ $# -gt 0 ]; do
    case "$1" in
        --destdir)
            DESTDIR="$2"
            shift 2
            ;;
        --prefix)
            PREFIX="$2"
            shift 2
            ;;
        --help)
            usage
            ;;
        *)
            echo "Unknown option: $1"
            usage
            ;;
    esac
done

# Normalize paths
[ -n "$DESTDIR" ] && DESTDIR="${DESTDIR%/}"
[ -n "$PREFIX" ] && PREFIX="${PREFIX%/}"

INSTALL_DIR="$DESTDIR$PREFIX"

echo "Installing fake_systemd to $INSTALL_DIR..."

# Resolve source directory (where this script is located)
# This handles the case where script is run from another directory
SRC_DIR=$(cd "$(dirname "$0")" && pwd)

# Create directories
mkdir -p "$INSTALL_DIR/bin"
mkdir -p "$INSTALL_DIR/lib"
mkdir -p "$INSTALL_DIR/etc/sv"
mkdir -p "$INSTALL_DIR/service"
mkdir -p "$INSTALL_DIR/run"
mkdir -p "$INSTALL_DIR/var/log"

# Install main script
echo "Installing main binary from $SRC_DIR/main..."
if [ -f "$SRC_DIR/main" ]; then
    cp "$SRC_DIR/main" "$INSTALL_DIR/bin/fake_systemd"
    chmod 755 "$INSTALL_DIR/bin/fake_systemd"
else
    echo "ERROR: main script not found at $SRC_DIR/main"
    exit 1
fi

# Install libraries
echo "Installing libraries..."
if [ -d "$SRC_DIR/lib" ]; then
    cp -r "$SRC_DIR/lib/"* "$INSTALL_DIR/lib/"
else
    echo "ERROR: lib directory not found at $SRC_DIR/lib"
    exit 1
fi

# Install BusyBox (if available in bin/)
# In a real build environment, we should ensure busybox exists.
# For now, we try to copy it if it exists, or rely on post-install setup.
if [ -f "$SRC_DIR/bin/busybox" ]; then
    echo "Installing bundled BusyBox..."
    cp "$SRC_DIR/bin/busybox" "$INSTALL_DIR/bin/"
    chmod 755 "$INSTALL_DIR/bin/busybox"
else
    echo "[WARN] bundled BusyBox not found in $SRC_DIR/bin/. Please ensure 'busybox' is available in $PREFIX/bin/."
fi

# Create systemctl symlink in target's /usr/bin for convenience
# This makes it available in PATH
SYSTEM_BIN="$DESTDIR/usr/bin"
mkdir -p "$SYSTEM_BIN"
echo "Creating /usr/bin/systemctl symlink..."
ln -sf "$PREFIX/bin/fake_systemd" "$SYSTEM_BIN/systemctl"

# --- GLOBAL TAKEOVER LOGIC ---
echo "Configuring global Runit takeover..."

# 1. Ensure internal symlinks exist in installation dir
# (These are needed for the wrapper scripts to work)
# Note: In cross-install, we can't run busybox to make links, so we use 'ln'
for applet in sv runsv runsvdir chpst; do
    ln -sf "busybox" "$INSTALL_DIR/bin/$applet"
done

# 2. Replace system binaries with wrappers/symlinks
# We replace: sv, runsv, runsvdir, chpst in /usr/bin

# Function to create wrapper or symlink
create_takeover() {
    local bin="$1"
    local target="$SYSTEM_BIN/$bin"
    
    echo "Taking over $bin..."
    rm -f "$target"
    
    # For 'sv', we need a wrapper to force SVDIR
    if [ "$bin" = "sv" ]; then
        cat <<EOF > "$target"
#!/bin/sh
# fake_systemd takeover wrapper for sv
# Forces SVDIR to internal service directory
export SVDIR="$PREFIX/service"
exec "$PREFIX/bin/sv" "\$@"
EOF
        chmod 755 "$target"
    else
        # For runsv/runsvdir/chpst, direct symlink to internal binary is fine
        # They don't depend on SVDIR env var usually, or runsvdir takes it as arg
        ln -sf "$PREFIX/bin/$bin" "$target"
    fi
}

for bin in sv runsv runsvdir chpst; do
    create_takeover "$bin"
done

echo "Global takeover complete. Runit tools in /usr/bin now point to fake_systemd."
echo "Installation complete."
