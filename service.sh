#!/system/bin/sh

export PATH=/system/bin:/system/xbin:/data/adb/ap/bin:/data/adb/magisk:$PATH

MODDIR=${0%/*}
SCRIPT_DIR="$MODDIR/scripts"
RCLONE_SH="$SCRIPT_DIR/rclone.sh"
STATUS_FILE="$MODDIR/webroot/status.json"
STOP_FLAG_FILE="/data/local/tmp/rclone_stop_flag"
LOG_FILE="/data/local/tmp/rclone.log"
BIN_LOG_FILE="/data/local/tmp/rclone_bin.log"
WATCHDOG_PID_FILE="/data/local/tmp/rclone_watchdog_pid"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"
}

cleanup() {
    log "===== 服务进程退出 ====="
    echo "1" > "$STOP_FLAG_FILE"
    "$RCLONE_SH" stop > /dev/null 2>&1
    rm -f "$WATCHDOG_PID_FILE" "$STOP_FLAG_FILE"
    exit 0
}

trap cleanup SIGTERM SIGINT SIGHUP

wait_for_storage() {
    _timeout=60 _elapsed=0
    while [ ! -d "/storage/emulated/0/Android" ]; do
        sleep 2
        _elapsed=$((_elapsed + 2))
        if [ $_elapsed -ge $_timeout ]; then
            log "WARN: 存储挂载超时(${_timeout}s)，继续启动..."
            return 1
        fi
    done
    log "存储已就绪 (${_elapsed}s)"
    return 0
}

log "===== Rclone VFS 服务启动 ====="

rm -f "$STOP_FLAG_FILE"

wait_for_storage

"$RCLONE_SH" start >> "$LOG_FILE" 2>&1

echo "$$" > "$WATCHDOG_PID_FILE"

_sync_tick=0
while [ ! -f "$STOP_FLAG_FILE" ]; do
    if ! "$RCLONE_SH" status > /dev/null 2>&1; then
        log "WARN: 进程异常退出，5 秒后自动重启..."
        sleep 5
        if [ ! -f "$STOP_FLAG_FILE" ]; then
            "$RCLONE_SH" start >> "$LOG_FILE" 2>&1
        fi
    fi

    _sync_tick=$((_sync_tick + 1))
    if [ $_sync_tick -ge 6 ]; then
        # 每 30 秒同步状态和日志到 webroot
        mkdir -p "$MODDIR/webroot"
        "$RCLONE_SH" status > /dev/null 2>&1
        { tail -100 "$LOG_FILE"; echo "--- rclone 二进制日志 ---"; tail -100 "$BIN_LOG_FILE"; } > "$MODDIR/webroot/log.txt" 2>/dev/null
        chmod 644 "$MODDIR/webroot/log.txt"
        _sync_tick=0
    fi

    sleep 5
done

cleanup
