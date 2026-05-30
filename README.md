# rclone-vfs-server

Magisk / KernelSU 模块 — 基于 Rclone 的 WebDAV 文件传输服务

## 特性

- **WebDAV 服务** — 在 Android 设备上提供 WebDAV 文件访问
- **VFS Full 缓存** — 启用 rclone VFS Full Cache 模式，离线可用
- **KSU WebUI** — 在 KernelSU 管理器中直接启动/停止/查看状态
- **自动启动** — 开机自启，5 秒健康检查自动重启
- **状态同步** — WebUI 定期刷新运行状态、缓存大小和日志
- **随机密码** — 每次安装自动生成随机密码

## 使用

1. 刷入模块后重启
2. 打开 KernelSU → 模块 → Rclone VFS → WebUI
3. 点击 **启动**，然后点击 **打开 WebDAV**
4. 使用任意 WebDAV 客户端连接：

```
地址: http://127.0.0.1:9876
用户: admin
密码: WebUI 中查看
```

### 管理命令

```sh
su -c /data/adb/modules/rclone_vfs_server/scripts/rclone.sh start
su -c /data/adb/modules/rclone_vfs_server/scripts/rclone.sh stop
su -c /data/adb/modules/rclone_vfs_server/scripts/rclone.sh restart
su -c /data/adb/modules/rclone_vfs_server/scripts/rclone.sh status
```

## WebUI 截图

在 KernelSU 模块页点击模块进入 WebUI，可控制服务、查看运行状态、连接信息、实时日志。

## 文件结构

```
rclone_vfs_server/
├── action.sh          # KSU WebUI 入口
├── install.sh         # 安装脚本
├── service.sh         # 开机自启 + 健康检查守护
├── module.prop        # 模块元信息
├── uninstall.sh       # 卸载脚本
├── scripts/
│   └── rclone.sh      # 核心管理脚本
├── webroot/
│   └── index.html     # KSU WebUI 页面
├── system/bin/
│   └── rclone         # rclone 二进制
```

## 日志

| 文件 | 内容 |
|------|------|
| `/data/local/tmp/rclone.log` | Shell 脚本日志（启动/停止/健康检查） |
| `/data/local/tmp/rclone_bin.log` | rclone 二进制日志（文件传输/错误） |
| `/data/local/tmp/rclone.log.old` | 轮转归档 |
| `/data/local/tmp/rclone_bin.log.old` | 轮转归档 |

日志超过 1MB 自动轮转。

## 配置

配置文件：`/data/local/tmp/rclone_vfs.conf`

```ini
RCLONE_USER=admin          # WebDAV 用户名
RCLONE_PASS=xxx            # WebDAV 密码
RCLONE_PORT=9876           # 端口
RCLONE_LISTEN=127.0.0.1    # 监听地址
RCLONE_CACHE_MAX_AGE=720h  # 缓存有效期
RCLONE_CACHE_MAX_SIZE=10G  # 缓存上限
```

## 卸载

在 KernelSU / Magisk 管理中卸载模块即可。

## 下载

- 最新成品包：`dist/rclone-vfs-server-v2.6.1-optimized.zip`
- 更新日志：`CHANGELOG.md`

## 版本历史

- **v2.6.1** — 修复状态刷新、停止标记残留、WebUI 首次启动按钮禁用问题，并加固状态 JSON 输出
- **v2.6** — 日志分离（二进制 vs shell），WebDAV 链接嵌入凭据修复 401，清理死代码
- **v2.5** — 架构重构，外部执行开关模式
- **v2.2** — 性能优化
- **v2.1** — Bug 修复
- **v2.0** — Rclone VFS 全能传输站（优化版）
- **v1.1** — 初始版本

## 致谢

- [rclone](https://rclone.org/) — 核心上传工具
