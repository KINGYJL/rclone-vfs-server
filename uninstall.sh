#!/system/bin/sh

echo ""
echo "  Rclone VFS 卸载清理"
echo "  ===================="
echo ""

STOP_FLAG_FILE="/data/local/tmp/rclone_stop_flag"
PID_FILE="/data/local/tmp/rclone_vfs_pid"
WATCHDOG_PID_FILE="/data/local/tmp/rclone_watchdog_pid"

mkdir -p /data/local/tmp
echo "1" > "$STOP_FLAG_FILE" 2>/dev/null

echo "  停止服务..."

_wpid=$(cat "$WATCHDOG_PID_FILE" 2>/dev/null)
[ -n "$_wpid" ] && kill "$_wpid" 2>/dev/null

_pid=$(cat "$PID_FILE" 2>/dev/null)
[ -n "$_pid" ] && kill "$_pid" 2>/dev/null

# 兜底：用 ps 扫描 rclone 进程
ps 2>/dev/null | grep "[r]clone" | while read _line; do
    _p=$(echo "$_line" | awk '{print $2}')
    [ -n "$_p" ] && kill "$_p" 2>/dev/null
done

sleep 1

echo "  清理缓存..."
rm -rf /data/adb/rclone_cache 2>/dev/null
rm -f /data/local/tmp/rclone.log
rm -f /data/local/tmp/rclone.log.old
rm -f /data/local/tmp/rclone_bin.log
rm -f /data/local/tmp/rclone_bin.log.old
rm -f /data/local/tmp/rclone_vfs.conf
rm -f /data/local/tmp/rclone_vfs_last_port
rm -f /data/local/tmp/rclone_vfs_pid
rm -f /data/local/tmp/rclone_watchdog_pid
rm -f /data/local/tmp/rclone_stop_flag
rm -f /data/local/tmp/rclone_vfs_lock

echo "  清理完成"
echo ""
