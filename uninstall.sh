#!/system/bin/sh

echo ""
echo "  Rclone VFS 卸载清理"
echo "  ===================="
echo ""

STOP_FLAG_FILE="/data/local/tmp/rclone_stop_flag"
PID_FILE="/data/local/tmp/rclone_vfs_pid"
WATCHDOG_PID_FILE="/data/local/tmp/rclone_watchdog_pid"
MODDIR="/data/adb/modules/rclone_vfs_server"
BIN="$MODDIR/system/bin/rclone"
REAL_BIN=$(readlink -f "$BIN" 2>/dev/null || echo "$BIN")

mkdir -p /data/local/tmp
echo "1" > "$STOP_FLAG_FILE" 2>/dev/null

echo "  停止服务..."

_wpid=$(cat "$WATCHDOG_PID_FILE" 2>/dev/null)
[ -n "$_wpid" ] && kill "$_wpid" 2>/dev/null

_pid=$(cat "$PID_FILE" 2>/dev/null)
[ -n "$_pid" ] && kill "$_pid" 2>/dev/null

# 兜底：只杀 exe 指向本模块 rclone 的进程，避免误伤其他 rclone 进程
for _proc in /proc/[0-9]*; do
    _pid=${_proc#/proc/}
    [ "$_pid" = "$$" ] && continue
    _exe=$(readlink "$_proc/exe" 2>/dev/null)
    case "$_exe" in
        "$BIN"|"$BIN (deleted)") kill "$_pid" 2>/dev/null; continue ;;
    esac
    _real=$(readlink -f "$_exe" 2>/dev/null)
    [ -n "$_real" ] && [ "$_real" = "$REAL_BIN" ] && kill "$_pid" 2>/dev/null
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
