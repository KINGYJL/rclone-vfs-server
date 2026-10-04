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
VFS_CACHE_MODE="off"
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

atomic_write() {
    # $1=目标文件 $2=内容。同目录临时文件 + mv，避免读取方读到半截内容
    printf '%s\n' "$2" > "$1.tmp.$$" 2>/dev/null || return 1
    mv -f "$1.tmp.$$" "$1" 2>/dev/null || return 1
    return 0
}

exe_is_module_rclone() {
    _exe=$1
    [ -n "$_exe" ] || return 1
    case "$_exe" in
        "$BIN"|"$BIN (deleted)") return 0 ;;
    esac
    _real=$(readlink -f "$_exe" 2>/dev/null)
    _real_bin=$(readlink -f "$BIN" 2>/dev/null || echo "$BIN")
    [ -n "$_real" ] && [ "$_real" = "$_real_bin" ]
}

pid_is_rclone() {
    _p=$1
    case "$_p" in ''|*[!0-9]*) return 1 ;; esac
    kill -0 "$_p" 2>/dev/null || return 1

    _exe=$(readlink "/proc/$_p/exe" 2>/dev/null)
    if [ -n "$_exe" ]; then
        exe_is_module_rclone "$_exe" && return 0
        return 1
    fi

    # 少数内核读不到 exe 时退回 cmdline 判断
    grep -aqF "$BIN" "/proc/$_p/cmdline" 2>/dev/null
}

probe_host() {
    case "$1" in
        ""|0.0.0.0|::|"::"|"0.0.0.0") echo "127.0.0.1" ;;
        *) echo "$1" ;;
    esac
}

port_is_listening_for_pid() {
    _ppid=$1
    _phost=$(probe_host "$2")
    _pport=$3
    _hex=$(printf '%04X' "$_pport" 2>/dev/null) || _hex=""

    # 首选内核表 + socket inode 归属校验（root 下可读，最准确）
    if [ -n "$_hex" ]; then
        _checked=0
        for _f in "/proc/${_ppid}/net/tcp" "/proc/${_ppid}/net/tcp6"; do
            [ -r "$_f" ] || continue
            _checked=1
            _inodes=$(awk -v pat=":${_hex}" '$2 ~ (pat "$") && $4 == "0A" {print $10}' "$_f" 2>/dev/null)
            [ -n "$_inodes" ] || continue
            # 有监听：确认 socket 属于该进程，避免同网络命名空间里别人占端口误判
            [ -r "/proc/${_ppid}/fd" ] || continue
            for _inode in $_inodes; do
                for _fd in "/proc/${_ppid}/fd"/*; do
                    case "$(readlink "$_fd" 2>/dev/null)" in
                        "socket:[$_inode]") return 0 ;;
                    esac
                done
            done
        done
        [ "$_checked" = "1" ] && return 1
    fi

    # 回退：TCP 连接探测，任何响应（含 401）都算在监听
    if command -v nc >/dev/null 2>&1; then
        nc -w 3 "$_phost" "$_pport" </dev/null >/dev/null 2>&1 && return 0
        return 1
    fi

    # 两种手段都不可用：不判断，交给调用方回退到 PID 存活
    return 0
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
    if [ "${RCLONE_VFS_CACHE_MODE:-$VFS_CACHE_MODE}" = "full" ]; then
        _cache_size=$(du -sh "$CACHE_DIR" 2>/dev/null | awk '{print $1}')
        [ -n "$_cache_size" ] || _cache_size="0"
    else
        _cache_size="off"
    fi
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
    _status_tmp="$STATUS_FILE.tmp.$$"
    cat > "$_status_tmp" << EOF
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
    chmod 644 "$_status_tmp" 2>/dev/null
    mv -f "$_status_tmp" "$STATUS_FILE" 2>/dev/null
}

init_config() {
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
RCLONE_VFS_CACHE_MODE="${VFS_CACHE_MODE}"
RCLONE_CACHE_MAX_AGE="${CACHE_MAX_AGE}"
RCLONE_CACHE_MAX_SIZE="${CACHE_MAX_SIZE}"
EOF
        chmod 600 "$CONF_FILE"
        log "新配置文件已生成 (随机密码)"
    fi

    . "$CONF_FILE"
    RCLONE_PORT=${RCLONE_PORT:-$DEFAULT_PORT}
    RCLONE_LISTEN=${RCLONE_LISTEN:-$LISTEN_ADDR}
    case "${RCLONE_VFS_CACHE_MODE:-}" in
        full) RCLONE_VFS_CACHE_MODE="full" ;;
        *)    RCLONE_VFS_CACHE_MODE="off" ;;
    esac
    if [ "$RCLONE_VFS_CACHE_MODE" = "full" ]; then
        mkdir -p "$CACHE_DIR"
    fi
}

acquire_lock() {
    if mkdir "$LOCK_FILE" 2>/dev/null; then
        echo "$$" > "$LOCK_FILE/pid"
        return 0
    fi

    # 锁已存在：持有者存活才算真占用，否则清理残留锁
    _holder=$(cat "$LOCK_FILE/pid" 2>/dev/null)
    if [ -n "$_holder" ] && kill -0 "$_holder" 2>/dev/null; then
        return 1
    fi

    log "WARN: 清理残留锁 (holder: ${_holder:-unknown})"
    rm -rf "$LOCK_FILE"
    mkdir "$LOCK_FILE" 2>/dev/null || return 1
    echo "$$" > "$LOCK_FILE/pid"
    return 0
}

release_lock() {
    rm -rf "$LOCK_FILE" 2>/dev/null
}

start_rclone() {
    rm -f "$STOP_FLAG_FILE"

    acquire_lock || {
        log "start_rclone: 已有操作在进行，跳过"
        echo "已有操作在进行"
        return 1
    }

    if [ -f "$PID_FILE" ]; then
        _old_pid=$(cat "$PID_FILE" 2>/dev/null)
        if pid_is_rclone "$_old_pid"; then
            log "Rclone 已在运行中 (PID: $_old_pid)"
            echo "Rclone 已在运行中"
            release_lock
            return 0
        fi
        log "WARN: PID 文件失效 (PID: ${_old_pid:-空})，忽略"
        rm -f "$PID_FILE"
    fi

    chmod 755 "$BIN"
    rotate_log "$LOG_FILE"
    rotate_log "$BIN_LOG_FILE"

    _addr="${RCLONE_LISTEN}:${RCLONE_PORT}"
    if [ "$RCLONE_VFS_CACHE_MODE" = "full" ]; then
        mkdir -p "$CACHE_DIR"
        _cache_args="--vfs-cache-mode full --vfs-cache-max-age $RCLONE_CACHE_MAX_AGE --vfs-cache-max-size $RCLONE_CACHE_MAX_SIZE --cache-dir $CACHE_DIR"
    else
        _cache_args="--vfs-cache-mode off"
    fi

    nohup "$BIN" serve webdav /storage/emulated/0 \
        --addr "${_addr}" \
        --user "${RCLONE_USER}" \
        --pass "${RCLONE_PASS}" \
        ${_cache_args} \
        --log-file "${BIN_LOG_FILE}" \
        --log-level "${LOG_LEVEL}" \
        > /dev/null 2>&1 &

    _pid=$!
    atomic_write "$PID_FILE" "$_pid"
    atomic_write "$PORT_FILE" "${RCLONE_PORT}"

    # 真探活：进程存活 + 端口进入 LISTEN，最多等 10 秒
    _wait=0
    while [ $_wait -lt 10 ]; do
        kill -0 "$_pid" 2>/dev/null || break
        port_is_listening_for_pid "$_pid" "$RCLONE_LISTEN" "$RCLONE_PORT" && break
        sleep 1
        _wait=$((_wait + 1))
    done

    # 再等 1 秒复查：绑定失败的 rclone 会立刻退出，避免端口被别的进程占用时误报成功
    sleep 1
    if kill -0 "$_pid" 2>/dev/null && port_is_listening_for_pid "$_pid" "$RCLONE_LISTEN" "$RCLONE_PORT"; then
        log "Rclone 已启动 (PID: $_pid, 端口: ${RCLONE_PORT}, 监听: ${RCLONE_LISTEN})"
        write_status_json "running"
        echo "启动成功 (PID: $_pid)"
        release_lock
        return 0
    else
        log "ERROR: Rclone 启动失败 (端口: ${RCLONE_PORT})"
        [ -f "$BIN_LOG_FILE" ] && tail -3 "$BIN_LOG_FILE" >> "$LOG_FILE" 2>/dev/null
        kill -9 "$_pid" 2>/dev/null
        write_status_json "stopped"
        rm -f "$PID_FILE"
        echo "启动失败: rclone 未在 ${_addr} 监听"
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
        if pid_is_rclone "$_old_pid"; then
            kill_process_tree "$_old_pid"
        else
            log "WARN: PID 文件失效 (PID: ${_old_pid:-空})，跳过"
        fi
        rm -f "$PID_FILE"
    fi

    # 兜底：只杀 exe 指向本模块 rclone 的进程，避免误伤其他 rclone
    for _proc in /proc/[0-9]*; do
        _p=${_proc#/proc/}
        [ "$_p" = "$$" ] && continue
        exe_is_module_rclone "$(readlink "$_proc/exe" 2>/dev/null)" && kill "$_p" 2>/dev/null
    done

    sleep 1
    log "Rclone 已停止"
    write_status_json "stopped"
    echo "已停止"
}

health_check_rclone() {
    _pid=$(cat "$PID_FILE" 2>/dev/null)
    pid_is_rclone "$_pid" || return 1
    . "$CONF_FILE" 2>/dev/null
    _listen=${RCLONE_LISTEN:-$LISTEN_ADDR}
    _port=$(cat "$PORT_FILE" 2>/dev/null || echo "${RCLONE_PORT:-$DEFAULT_PORT}")
    port_is_listening_for_pid "$_pid" "$_listen" "$_port" || return 1
    return 0
}

cmd_start() {
    init_config
    start_rclone
}

cmd_stop() {
    # 不杀看护进程：stop_flag 让看护空转，下一次 start 仍然受看护
    stop_rclone
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
        return 0
    else
        init_config
        write_status_json "stopped"
        echo "状态: 已停止"
        return 1
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

exit $?
