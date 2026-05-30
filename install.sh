#!/system/bin/sh

SKIPMOUNT=false
PROPFILE=false
POSTFSDATA=false
LATESTARTSERVICE=true

on_install() {
    ui_print ""
    ui_print "  🦞 Rclone VFS 全能传输站 v2.6.1"
    ui_print "  ================================"
    ui_print ""
    ui_print "  ✅ Rclone v1.74.1 (2026-05)"
    ui_print "  ✅ VFS Full 缓存 (持久化存储)"
    ui_print "  ✅ 随机密码自动生成"
    ui_print "  ✅ KSU WebUI 管理面板"
    ui_print "  ✅ 进程保活 (每5秒自检)"
    ui_print "  ✅ 日志轮转 (最大1MB)"
    ui_print "  ✅ 外部执行开关 (KSU Execute)"
    ui_print ""
    ui_print "  📦 正在解压..."
    unzip -o "$ZIPFILE" 'system/*' -d "$MODPATH" >&2
    unzip -o "$ZIPFILE" 'scripts/*' -d "$MODPATH" >&2
    unzip -o "$ZIPFILE" 'service.sh' -d "$MODPATH" >&2
    unzip -o "$ZIPFILE" 'action.sh' -d "$MODPATH" >&2
    unzip -o "$ZIPFILE" 'uninstall.sh' -d "$MODPATH" >&2
    unzip -o "$ZIPFILE" 'webroot/*' -d "$MODPATH" >&2
    ui_print "  ✅ 解压完成"
}

set_permissions() {
    set_perm_recursive "$MODPATH/system/bin" 0 0 0755 0755
    set_perm "$MODPATH/service.sh" 0 0 0755
    set_perm "$MODPATH/action.sh" 0 0 0755
    set_perm "$MODPATH/scripts/rclone.sh" 0 0 0755
    set_perm "$MODPATH/uninstall.sh" 0 0 0755
    set_perm_recursive "$MODPATH/webroot" 0 0 0644 0644
}
