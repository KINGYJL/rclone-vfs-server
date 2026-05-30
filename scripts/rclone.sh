#!/system/bin/sh

MODDIR="/data/adb/modules/rclone_vfs_server"
BIN="$MODDIR/system/bin/rclone"

CONF_FILE="/data/local/tmp/rclone_vfs.conf"
CACHE_DIR="/data/adb/rclone_cache"
LOG_FILE="/data/local/tmp/rclone.log"
BIN_LOG_FILE="/data/local/tmp/rclone_bin.log"
PID_FILE="/data/local/tmp/rclone_vfs_pid"
WATCHDOG_PID_FILE="/data/local/tmp/rclone_watchdog_pid"
STOP_FLAG_FILE="/data/local/tmp/rclone_stop_flag"
STATUS_FILE="$MODDIR/webroot/status.json"
PORT_FILE="/data/local/tmp/rclone_vfs_last_port"
LOCK_FILE="/data/local/tmp/rclone_vfs_lock"

DEFAULT_PORT=9876
LISTEN_ADDR="127.0.0.1"
CACHE_MAX_AGE="720h"
CACHE_MAX_SIZE="10G"
LOG_LEVEL="INFO"
LOG_MAX_SIZE=1048576

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"
}

rotate_log() {
    _file=$1
    [ -f "$_file" ] || return 0
    _size=$(stat -c%s "$_file" 2>/dev/null || echo 0)
    [ "$_size" -gt "$LOG_MAX_SIZE" ] 2>/dev/null || return 0
    mv "$_file" "${_file}.old"
    log "日志轮转: $(basename "$_file") 已归档"
}

json_escape() {
    printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; s/	/\\t/g'
}

generate_password() {
    if [ -r /dev/urandom ]; then
        dd if=/dev/urandom bs=8 count=1 2>/dev/null | md5sum | cut -c1-16
    else
        printf '%s%s%s' "$$" "$(date +%s)" "$$" | md5sum | cut -c1-16
    fi
}

write_status_json() {
    _status=$1
    _pid=$(cat "$PID_FILE" 2>/dev/null || echo "")
    _port=$(cat "$PORT_FILE" 2>/dev/null || echo "$DEFAULT_PORT")
    . "$CONF_FILE" 2>/dev/null
    case "$_port" in
        ''|*[!0-9]*) _port="$DEFAULT_PORT" ;;
    esac
    _cache_size=$(du -sh "$CACHE_DIR" 2>/dev/null | awk '{print $1}' || echo "0")
    _log_size=$(stat -c%s "$LOG_FILE" 2>/dev/null || echo 0)
    case "$_log_size" in
        ''|*[!0-9]*) _log_size=0 ;;
    esac
    if [ "$_status" = "running" ] && [ -n "$_pid" ]; then
        _uptime=$(ps -o pid,etime -p "$_pid" 2>/dev/null | tail -1 | awk '{print $2}' || echo "N/A")
    else
        _uptime="N/A"
    fi

    _status_json=$(json_escape "$_status")
    _pid_json=$(json_escape "$_pid")
    _uptime_json=$(json_escape "$_uptime")
    _user_json=$(json_escape "${RCLONE_USER:-admin}")
    _pass_json=$(json_escape "${RCLONE_PASS:-}")
    _listen_json=$(json_escape "${RCLONE_LISTEN:-$LISTEN_ADDR}")
    _cache_dir_json=$(json_escape "$CACHE_DIR")
    _cache_size_json=$(json_escape "$_cache_size")

    mkdir -p "$MODDIR/webroot"
    cat > "$STATUS_FILE" << EOF
{
  "status": "${_status_json}",
  "pid": "${_pid_json}",
  "port": ${_port},
  "uptime": "${_uptime_json}",
  "user": "${_user_json}",
  "pass": "${_pass_json}",
  "has_password": $( [ -n "${RCLONE_PASS:-}" ] && echo true || echo false ),
  "listen": "${_listen_json}",
  "cache_dir": "${_cache_dir_json}",
  "cache_size": "${_cache_size_json}",
  "log_size": ${_log_size}
}
EOF
    chmod 644 "$STATUS_FILE"
}

init_config() {
    mkdir -p "$CACHE_DIR"
    _need_gen=false

    if [ ! -f "$CONF_FILE" ]; then
        _need_gen=true
    else
        . "$CONF_FILE" 2>/dev/null
        if [ -z "$RCLONE_USER" ] || [ -z "$RCLONE_PASS" ]; then
            log "WARN: 配置文件损坏，重新生成"
            _need_gen=true
        fi
    fi

    if [ "$_need_gen" = true ]; then
        _pass=$(generate_password)
        cat > "$CONF_FILE" << EOF
# Rclone VFS 配置 - 自动生成，请勿手动编辑
RCLONE_USER="admin"
RCLONE_PASS="${_pass}"
RCLONE_PORT=${DEFAULT_PORT}
RCLONE_LISTEN="${LISTEN_ADDR}"
RCLONE_CACHE_MAX_AGE="${CACHE_MAX_AGE}"
RCLONE_CACHE_MAX_SIZE="${CACHE_MAX_SIZE}"
EOF
        chmod 600 "$CONF_FILE"
        log "新配置文件已生成 (随机密码)"
    fi

    . "$CONF_FILE"
    RCLONE_PORT=${RCLONE_PORT:-$DEFAULT_PORT}
    RCLONE_LISTEN=${RCLONE_LISTEN:-$LISTEN_ADDR}
}

acquire_lock() {
    mkdir "$LOCK_FILE" 2>/dev/null
}

release_lock() {
    rmdir "$LOCK_FILE" 2>/dev/null
}

start_rclone() {
    rm -f "$STOP_FLAG_FILE"

    acquire_lock || {
        log "start_rclone: 已有操作在进行，跳过"
        echo "已有操作在进行"
        return 1
    }

    if [ -f "$PID_FILE" ]; then
        _old_pid=$(cat "$PID_FILE")
        if kill -0 "$_old_pid" 2>/dev/null; then
            log "Rclone 已在运行中 (PID: $_old_pid)"
            echo "Rclone 已在运行中"
            release_lock
            return 0
        fi
        rm -f "$PID_FILE"
    fi

    mkdir -p "$CACHE_DIR"
    chmod 755 "$BIN"
    rotate_log "$LOG_FILE"
    rotate_log "$BIN_LOG_FILE"

    _addr="${RCLONE_LISTEN}:${RCLONE_PORT}"

    nohup "$BIN" serve webdav /storage/emulated/0 \
        --addr "${_addr}" \
        --user "${RCLONE_USER}" \
        --pass "${RCLONE_PASS}" \
        --vfs-cache-mode full \
        --vfs-cache-max-age "${RCLONE_CACHE_MAX_AGE}" \
        --vfs-cache-max-size "${RCLONE_CACHE_MAX_SIZE}" \
        --cache-dir "${CACHE_DIR}" \
        --log-file "${BIN_LOG_FILE}" \
        --log-level "${LOG_LEVEL}" \
        > /dev/null 2>&1 &

    _pid=$!
    echo "$_pid" > "$PID_FILE"
    echo "${RCLONE_PORT}" > "$PORT_FILE"

    sleep 2
    if kill -0 "$_pid" 2>/dev/null; then
        log "Rclone 已启动 (PID: $_pid, 端口: ${RCLONE_PORT}, 监听: ${RCLONE_LISTEN})"
        write_status_json "running"
        echo "启动成功 (PID: $_pid)"
        release_lock
        return 0
    else
        log "ERROR: Rclone 启动失败"
        write_status_json "stopped"
        rm -f "$PID_FILE"
        echo "启动失败"
        release_lock
        return 1
    fi
}

kill_process_tree() {
    _pid=$1
    [ -z "$_pid" ] && return 1
    kill "$_pid" 2>/dev/null
    sleep 1
    kill -0 "$_pid" 2>/dev/null && kill -9 "$_pid" 2>/dev/null
}

stop_rclone() {
    echo "1" > "$STOP_FLAG_FILE"

    if [ -f "$PID_FILE" ]; then
        _old_pid=$(cat "$PID_FILE" 2>/dev/null)
        [ -n "$_old_pid" ] && kill_process_tree "$_old_pid"
        rm -f "$PID_FILE"
    fi

    _bin_name=$(basename "$BIN")
    ps 2>/dev/null | grep "[${_bin_name%?}]${_bin_name#?}" | while read _line; do
        _p=$(echo "$_line" | awk '{print $2}')
        [ -n "$_p" ] && [ "$_p" != "$$" ] && kill "$_p" 2>/dev/null
    done

    sleep 1
    log "Rclone 已停止"
    write_status_json "stopped"
    echo "已停止"
}

health_check_rclone() {
    _pid=$(cat "$PID_FILE" 2>/dev/null)
    [ -z "$_pid" ] && return 1
    kill -0 "$_pid" 2>/dev/null || return 1
    return 0
}

cmd_start() {
    init_config
    start_rclone
}

cmd_stop() {
    stop_rclone
    if [ -f "$WATCHDOG_PID_FILE" ]; then
        _wpid=$(cat "$WATCHDOG_PID_FILE")
        kill -0 "$_wpid" 2>/dev/null && kill "$_wpid" 2>/dev/null
        rm -f "$WATCHDOG_PID_FILE"
    fi
}

cmd_restart() {
    cmd_stop
    sleep 2
    cmd_start
}

cmd_status() {
    if health_check_rclone; then
        _pid=$(cat "$PID_FILE" 2>/dev/null || echo "N/A")
        _port=$(cat "$PORT_FILE" 2>/dev/null || echo "$DEFAULT_PORT")
        . "$CONF_FILE" 2>/dev/null
        _uptime=$(ps -o pid,etime -p "$_pid" 2>/dev/null | tail -1 | awk '{print $2}' || echo "N/A")
        write_status_json "running"
        echo "状态: 运行中"
        echo "PID: $_pid"
        echo "端口: $_port"
        echo "运行时间: $_uptime"
        echo "用户: ${RCLONE_USER:-admin}"
    else
        init_config
        write_status_json "stopped"
        echo "状态: 已停止"
    fi
}

cmd_toggle() {
    if health_check_rclone; then
        echo "正在停止..."
        cmd_stop
    else
        echo "正在启动..."
        cmd_start
    fi
}

case "${1:-status}" in
    start)   cmd_start ;;
    stop)    cmd_stop ;;
    restart) cmd_restart ;;
    status)  cmd_status ;;
    toggle)  cmd_toggle ;;
    *)
        echo "用法: rclone.sh {start|stop|restart|status|toggle}"
        exit 1
        ;;
esac

exit 0
