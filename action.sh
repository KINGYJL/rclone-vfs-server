#!/system/bin/sh

export PATH=/system/bin:/system/xbin:/data/adb/ap/bin:$PATH

MODDIR=${0%/*}
SCRIPT_DIR="$MODDIR/scripts"

if [ ! -f "$SCRIPT_DIR/rclone.sh" ]; then
    echo "错误: rclone.sh 不存在" >&2
    exit 1
fi

"$SCRIPT_DIR/rclone.sh" toggle

sleep 1
