SKIPMOUNT=false
PROPFILE=false
POSTFSDATA=false
LATESTARTSERVICE=true

SKIPUNZIP=1
ASH_STANDALONE=1

if [ "$ARCH" != "arm64" ]; then
  ui_print "! Unsupported architecture: $ARCH"
  ui_print "! Please use arm64 architecture."
  abort
fi

ui_print "- [1] Extracting module bese files..."
unzip -o "$ZIPFILE" 'module.prop' -d "$MODPATH" >&2
unzip -o "$ZIPFILE" 'service.sh' -d "$MODPATH" >&2
unzip -o "$ZIPFILE" 'scripts/*' -d "$MODPATH" >&2
set_perm_recursive "$MODPATH/scripts" 0 0 0755 0755

ui_print "- [2] Deploying tools files..."
unzip -o "$ZIPFILE" 'tools/*' -d "$MODPATH" >&2
ui_print "- Set permissions for tools files."
set_perm_recursive "$MODPATH/tools" 0 0 0755 0755

ui_print "- [3] Set tools environment variable."
TOOLS=$MODPATH/tools
ui_print "- Tools path: $TOOLS"
BB=$TOOLS/bin/busybox
chmod 755 "$BB"
set_perm "$BB" 0 0 0755
ui_print "- Busybox path: $BB"

ui_print "- [4] Setting up Debian Rootfs..."
CHROOT_DIR="/data/DebianChroot"

if [ -d "$CHROOT_DIR" ] && [ -f "$CHROOT_DIR/bin/bash" ]; then
  ui_print "- Detected existing Debian container."
  ui_print "- Skipping rootfs extraction to preserve data."
  ui_print "- Note: If you want to reinstall clean, please uninstall the module first."
else
  if [ ! -d "$CHROOT_DIR" ]; then
    ui_print "- Creating $CHROOT_DIR..."
    mkdir -p "$CHROOT_DIR"
  fi

  ui_print "- Extracting rootfs to $CHROOT_DIR..."
  unzip -p "$ZIPFILE" 'common/debian-bookworm-rootfs.tar.xz' | $BB tar -xJ -C "$CHROOT_DIR"

  if [ $? -ne 0 ]; then
    ui_print "! Failed to extract rootfs."
    abort
  fi
fi

ui_print "- [5] Installing fake_systemd (Global Takeover)..."

FAKE_SYSTEMD_SRC="$TOOLS/setup/fake_systemd"
ui_print "- Source: $FAKE_SYSTEMD_SRC"

# Diagnostic check for source files
if [ ! -f "$FAKE_SYSTEMD_SRC/install.sh" ]; then
    ui_print "! Error: install.sh not found!"
    ls -l "$FAKE_SYSTEMD_SRC" >&2
elif [ ! -f "$FAKE_SYSTEMD_SRC/main" ]; then
    ui_print "! Error: main script not found in source!"
    ls -l "$FAKE_SYSTEMD_SRC" >&2
else
    # Execute installer
    # We use sh explicitly
    ui_print "- Running installer..."
    
    # Run install.sh and capture output to log
    # Note: Magisk busybox sh might be limited, ensuring path is absolute
    sh "$FAKE_SYSTEMD_SRC/install.sh" --destdir "$CHROOT_DIR" --prefix "/opt/fake_systemd" >&2
    
    if [ $? -ne 0 ]; then
        ui_print "! Installation script returned error."
    fi

    # Verification
    INSTALLED_BIN="$CHROOT_DIR/opt/fake_systemd/bin/fake_systemd"
    if [ ! -f "$INSTALLED_BIN" ]; then
        ui_print "! CRITICAL: fake_systemd binary missing after install!"
        ui_print "! Attempting manual copy fallback..."
        
        # Manual Fallback
        TARGET_DIR="$CHROOT_DIR/opt/fake_systemd"
        $BB mkdir -p "$TARGET_DIR/bin"
        $BB mkdir -p "$TARGET_DIR/lib"
        $BB mkdir -p "$TARGET_DIR/etc/sv"
        $BB mkdir -p "$TARGET_DIR/service"
        $BB mkdir -p "$TARGET_DIR/run"
        $BB mkdir -p "$TARGET_DIR/var/log"
        
        $BB cp "$FAKE_SYSTEMD_SRC/main" "$TARGET_DIR/bin/fake_systemd"
        $BB chmod 755 "$TARGET_DIR/bin/fake_systemd"
        if [ -d "$FAKE_SYSTEMD_SRC/lib" ]; then
            $BB cp -r "$FAKE_SYSTEMD_SRC/lib/." "$TARGET_DIR/lib/"
        fi
        
        if [ -f "$TARGET_DIR/bin/fake_systemd" ]; then
            ui_print "- Manual copy successful."
            # Also need to create symlinks manually if install.sh failed
            SYSTEM_BIN="$CHROOT_DIR/usr/bin"
            $BB mkdir -p "$SYSTEM_BIN"
            $BB ln -sf "/opt/fake_systemd/bin/fake_systemd" "$SYSTEM_BIN/systemctl"
        else
            ui_print "! Manual copy FAILED."
        fi
    fi

    # Post-install: Copy busybox if not present (install.sh tries but might fail if src missing)
    if [ ! -f "$CHROOT_DIR/opt/fake_systemd/bin/busybox" ]; then
        ui_print "- Bundling BusyBox into fake_systemd..."
        $BB cp "$BB" "$CHROOT_DIR/opt/fake_systemd/bin/busybox"
        $BB chmod 755 "$CHROOT_DIR/opt/fake_systemd/bin/busybox"
    fi
    
    # Ensure legacy Runit directories exist (managed by fake_systemd now)
    $BB mkdir -p "$CHROOT_DIR/etc/service"
    $BB mkdir -p "$CHROOT_DIR/etc/runit"
    
    ui_print "- fake_systemd installed and configured for global takeover."
fi

ui_print "- [6] Configuring Rootfs..."

# 安装 LM (Linux Manager) 内部脚本到容器
LM_SRC="$TOOLS/setup/lm"
LM_DEST="$CHROOT_DIR/usr/local/lm"
LM_BIN="$CHROOT_DIR/usr/bin/lm"

if [ -d "$LM_SRC" ]; then
  ui_print "- Installing LM scripts..."
  $BB mkdir -p "$LM_DEST"
  $BB cp -r "$LM_SRC/." "$LM_DEST/"
  $BB chmod -R 755 "$LM_DEST"
  
  # 创建 /usr/bin/lm 软链接，方便直接调用
  # 注意：这里创建的是相对链接或者绝对链接，在chroot内部看来是 /usr/local/lm/...
  # 我们直接写入一个wrapper脚本或者软链接
  # 简单起见，直接软链接：ln -sf /usr/local/lm/lm-bash.sh /usr/bin/lm
  $BB ln -sf /usr/local/lm/lm-bash.sh "$LM_BIN"
  ui_print "- LM scripts installed to /usr/local/lm"
else
  ui_print "! Warning: LM scripts not found in $LM_SRC"
fi

# 预先创建必要的挂载点，防止挂载时目录不存在报错
ui_print "- Creating mount points..."
for dir in dev proc sys apex sdcard storage; do
  $BB mkdir -p "$CHROOT_DIR/$dir"
done
$BB mkdir -p "$CHROOT_DIR/dev/pts"
$BB mkdir -p "$CHROOT_DIR/dev/shm"

ui_print "- Rootfs setup completed!"