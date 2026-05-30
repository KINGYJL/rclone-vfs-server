# Changelog

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
