# Changelog

## Unreleased

- macOS: drop AppleScript applet (`.app`) launchers in favor of `.command` files. The applets were ad-hoc signed with no stable Bundle ID, so every rebuild invalidated TCC grants and macOS re-prompted for Downloads/Pictures access (child processes' file access was also attributed to the applet). `.command` files run as the terminal itself and reuse its existing authorizations. `install.sh` now writes the three `.command` launchers and removes leftover `.app` applets; icon generation (`gen_icns`/`build_app`) removed.

- macOS `install.sh`: `build_app` now compiles into a temp bundle and only swaps it in on success (temp name keeps the `.app` suffix, otherwise `osacompile` emits a flat file). Previously `rm -rf` ran before `osacompile`, so a failed build left the user with **no launcher at all**. Failed builds are reported and no longer abort the whole install.
- macOS `profile.zsh`: new `proxy-switch` command opens the menu from any terminal (same as double-clicking `~/Applications/代理切换.app`).

- macOS `lib.zsh`: `config.json` is flattened once into a zsh assoc-array cache instead of spawning one `python3` per lookup (menu frame: ~7 spawns ≈ 0.3s → 0). `_psw_config_reload()` invalidates it after the `[0]` picker writes the file.
- macOS `lib.zsh`: new `_psw_prepare_path()` (called by `switcher.sh` / `launch.sh`) appends `/usr/sbin`, `/sbin`, `/usr/local/bin`, `/opt/homebrew/bin` plus optional `path.extra` from `config.json`. Double-clicking a `.app` runs through `osascript` with a minimal PATH that has no `/usr/sbin`, so `lsof` — needed by `recoverWhiteScreen` to find the `language_server` port — was invisible; self-managed `node` installs are covered by `path.extra`.

- Windows `launch.ps1`: rename desktop inject flag to `$injectMode` so it does not collide with the `[ValidateSet]` `$Mode` parameter (PowerShell is case-insensitive; the old `$mode` assignment re-validated and crashed options 5/6).
- Menus on Windows and macOS use the same single-page layout grouped by tool (odd numbers = opencode, even = Antigravity). Key numbers are unchanged.
- Proxy port auto-detect: enabling/launching first verifies `proxy.url`, then falls back to the OS system proxy (Windows registry / macOS `scutil --proxy`), then scans common local HTTP ports (7897/7890/7892/7893/7899/7895/10809/2080/2081/8080/20171/20172). Swapping proxy apps no longer requires editing `config.json`. Menu shows the resolved address and its source; new `[0]` picker lists reachable proxies and can save the choice to `config.json`. Optional `proxy.auto_detect` (default true), `proxy.candidates`, `proxy.candidate_ports`.

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
