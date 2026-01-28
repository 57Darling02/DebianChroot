#!/system/bin/sh
MODDIR=${0%/*}
chmod +x "$MODDIR/manager.sh"
chmod +x "$MODDIR/scripts/"*

# Start container service
sh "$MODDIR/scripts/start.sh" -b

# Start status monitor in background
# This updates module.prop every 10 seconds
nohup sh "$MODDIR/scripts/monitor.sh" >/dev/null 2>&1 &

