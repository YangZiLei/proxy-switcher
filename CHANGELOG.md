# Changelog

## Unreleased

- Windows menu [5]/[6] call `launchers/launch.ps1` and **respect the marker** (no longer force-enable). Recoverable errors return to the menu instead of `break`.
- Desktop launchers on Windows and macOS quit a running instance and wait (up to 12s, then force) so proxy on **or** off matches the current marker. Marker-off starts without inheriting leaked proxy env.
- Windows injects `ALL_PROXY` together with `HTTPS_PROXY` / `HTTP_PROXY` / `NO_PROXY` / `no_proxy`.
- Shared inject helpers: `macos/lib.zsh` and `scripts/ProxySwitcher.ps1` (used by menus, launchers, and CLI wrappers).
- `agy-proxy` / `opencode-proxy` resolve the real CLI from `config.json` (`apps.*.cli`) and PATH, not a hardcoded exe path.
- macOS menu `.app` detects Ghostty / iTerm / Kitty / Terminal.app (`PROXY_SWITCHER_TERMINAL` override). Missing terminal or failed desktop launch shows a dialog. Installer no longer `killall Dock`.
- Windows `scripts/install.ps1` copies `config.example.json` to `config.json` when missing and expands `%LOCALAPPDATA%` desktop paths.
- Top-level `install.sh` refuses Windows `curl | sh` pipe mode; requires `pwsh` from a real repo checkout. `print_verify` only mentions `type opencode-proxy` when `--with-zshrc` was passed.
- README no longer claims this is the “only” solution; platform table matches current behavior.
- CI (`shellcheck` + `pwsh -File scripts/validate.ps1`), `CONTRIBUTING.md`, and a bug issue template.
