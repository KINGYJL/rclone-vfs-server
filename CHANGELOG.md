# Changelog

## v2.6.2 - 2026-10-04

### Fixed

- Keepalive was dead: `rclone.sh status` always exited 0, so the watchdog never saw a failure and never restarted rclone. `status` now returns 0 running / 1 stopped, and the script propagates real exit codes.
- Watchdog was killed by `stop`: `cmd_stop` no longer kills the supervisor. The watchdog now stays alive and idles while the stop flag is set, so a later start keeps supervision, status sync, and log sync.
- Stale lock could block every future start: the lock now stores the holder pid and is reclaimed when the holder is gone. Failures are no longer masked by a trailing `exit 0`.
- Start verification: instead of a fixed 2 s `kill -0`, the script now waits up to 10 s for the port to reach LISTEN and reports the real failure.
- PID file reuse: the pid is validated against `/proc/<pid>/exe` before it is trusted, so a recycled pid can no longer fake "already running" or be killed by mistake.
- Process cleanup no longer greps `ps` for `rclone`; it matches `/proc/*/exe` pointing at the module's rclone only.
- `status.json` is written atomically (temp file + rename), so the WebUI can no longer read a half-written file.

### Changed

- VFS cache is now optional and off by default (`RCLONE_VFS_CACHE_MODE=off|full` in the config). Cache flags and `--cache-dir` are only passed to rclone in `full` mode.
- Module renamed to `Rclone WebDAV 传输站` (module id unchanged, upgrades keep working).

### Package

- Bumped module version to v2.6.2, `versionCode` to 10.
- Built artifact: `dist/rclone-vfs-server-v2.6.2-optimized.zip`.

## v2.6.1 - 2026-05-30

### Fixed

- Refresh `webroot/status.json` whenever `scripts/rclone.sh status` runs, so the WebUI shows current uptime, cache size, and service state.
- Clear stale `/data/local/tmp/rclone_stop_flag` before starting rclone, fixing restart/start issues after stopping from the WebUI or action entrypoint.
- Keep WebUI controls usable when `status.json` is missing or unavailable, allowing first-run startup from the panel.
- Quote script paths in `service.sh` and `action.sh` for more reliable command execution.

### Hardened

- Escape string values before writing `status.json`, preventing malformed JSON if config values contain quotes or backslashes.
- Validate numeric JSON fields such as port and log size before writing status output.

### Package

- Bumped module version from `v2.6` to `v2.6.1`.
- Bumped `versionCode` from `8` to `9`.
- Built artifact: `dist/rclone-vfs-server-v2.6.1-optimized.zip`.
