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

ui_print "- [5] Installing Runit..."
RUNIT_SRC="$TOOLS/setup/runit"
RUNIT_DEST="$CHROOT_DIR/usr/bin"

if [ ! -d "$RUNIT_DEST" ]; then
  $BB mkdir -p "$RUNIT_DEST"
fi

for bin in chpst runsv runsvdir sv; do
  if [ -f "$RUNIT_SRC/$bin" ]; then
    ui_print "- Installing $bin..."
    $BB cp "$RUNIT_SRC/$bin" "$RUNIT_DEST/"
    $BB chmod 755 "$RUNIT_DEST/$bin"
  else
    ui_print "! Warning: $bin not found in $RUNIT_SRC"
  fi
done

ui_print "- Creating Runit service directories..."
$BB mkdir -p "$CHROOT_DIR/etc/service"
$BB mkdir -p "$CHROOT_DIR/etc/runit"

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