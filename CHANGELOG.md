# Changelog

## Unreleased

- **Grok CLI (xAI Grok Build TUI) 支持**:
  - 新增 `grok-proxy` 命令行包装，按当前模式（自动探测 / 强制代理 / 强制直连）自动注入代理环境后拉起 xAI Grok；
  - 生成 `~/Applications/Grok 代理启动.app` 与 `Grok 代理启动.command` 双击启动器，直接拉起 Ghostty/终端运行 Grok；
  - 主菜单 `switcher.sh` 增加 Grok 状态监控、`[k]` 模式轮转与 `[x]` 在当前窗口直接启动 Grok CLI；
  - 标记体系扩充 `.grok-proxy-on` 与 `.grok-proxy-off`，Windows 脚本亦同步支持 `grok` 校验；
  - 为 Grok 定制深空碳黑（Pitch Black）+ 白色极简 `X` + `GROK` 专属高清图标。
- **macOS 原生 `.app` 启动器与专属配色首字母图标**:
  - 全新生成原生 `.app` Bundle（`LSUIElement=true`），彻底解决双击 `.command` 强制弹系统 Terminal 终端黑框的问题，实现直接唤起 Ghostty 或纯静默后台启动；
  - Swift 原生动态渲染符合 Apple 官方规范的 Squircle 高清 Retina 图标（16×16 至 1024×1024 .icns + .png），各工具专属配色与字母：
    - `代理切换.app`：紫罗兰渐变 + `P` (`PROXY`)
    - `Antigravity 代理启动.app`：电光青蓝渐变 + `A` (`ANTIGRAVITY`)
    - `Gemini 代理启动.app`：星云粉紫极光渐变 + `G` (`GEMINI`)
    - `OpenCode 代理启动.app`：极客翡翠绿渐变 + `O` (`OPENCODE`)
    - `Grok 代理启动.app`：深空碳黑极简 + `X` (`GROK`)
  - 双重注入机制：同时写入 Bundle 内置 `AppIcon.icns` 与 Cocoa `NSWorkspace` 元数据，配合 LaunchServices 即刻生效。
- **Gemini.app 官方桌面端支持与启动无限 Loading 修复**:
  - **无限 Loading 根因修复**：
    1. Gemini 原生二进制内的 libcurl（`curl_api.cc`）在未显式传代理时硬编码了 `curl_easy_setopt(curl, CURLOPT_NOPROXY, "*")`，导致其 OAuth 访问令牌刷新（`https://www.googleapis.com/oauth2/token`）强制直连并在超时 3000ms 后报 `Remapped curl code 28 to 86`，致使客户端永驻加载转圈；通过热补丁置空该硬编码并重签名，彻底恢复其代理能力；
    2. 检测并修正 macOS Wi-Fi 代理绕过列表中的 `172.2*` 误配置（该通配符会错误命中 Google 拥有的 `172.217.*` 节点段导致直连超时），并自动关闭 WPAD PAC 自动探测避免 CFNetwork `-1003` 故障；
    3. 为 Gemini 智能提供 SOCKS5 本地 DNS 解析协议（`socks5://${host}:${port}`），将令牌握手耗时从 >5s 降至 ~0.4s，远低于 Gemini 内部 3s 超时门槛，同时注入 `GRPC_PROXY` 保障全协议链通畅；
    4. 启动器内置 `_psw_patch_gemini_if_needed` 具备自愈能力，即使 Gemini 版本更新亦可无感自动修复。
  - macOS 生成 `~/Applications/Gemini 代理启动.command` 启动器及 `profile.zsh` 中的 `gemini-proxy` 命令；
  - 主菜单 `switcher.sh` 增加 Gemini 状态显示、`[3]` 模式轮转（自动 / 强制代理 / 强制直连）与 `[4]` 桌面端快捷启动；
  - 启动器与库函数内置智能缺省标记名 `.gemini-proxy-on`，在旧版 `config.json` 下零配置平滑兼容；
  - 扩展 Windows 配置模板与脚本校验集合（`[ValidateSet]` 包含 `gemini`）。
- **环境变量注入兼容性优化**：
  - 同时注入大写（`HTTPS_PROXY` / `HTTP_PROXY` / `ALL_PROXY`）与小写（`https_proxy` / `http_proxy` / `all_proxy`）代理变量，兼容 libcurl、J2ObjC、Swift 原生网络栈、Go 及 Python。
- **进程管理与应用辅助守护进程清理**：
  - `launch.sh` 中的 `main_pid` 匹配逻辑增强为对齐空格路径；
  - `kill_main` 与 `kill_old_instance` 增加应用 bundle 路径内辅助守护进程（如 `GeminiAppLauncher`、`crashpad_handler` 等）协同退出与强制清理机制，确保进程重载时彻底应用新代理模式。
- **安装与文档规范化**：
  - 修正顶层 `install.sh` 提示文案与 `README.md` 中残留的 `.app` 描述为 `.command`。
- macOS **smart launch** (behavior change): the per-tool mode is now tri-state — `…-on` marker = force proxy, new `…-off` marker = force direct, **no marker = auto** (probe at launch; inject + notify when a proxy answers, direct + notify otherwise). Previously "no marker" meant direct, so the daily flow no longer requires toggling the switcher menu first. Legacy `-on` markers migrate cleanly; CLI wrappers (`opencode-proxy` / `agy-proxy` / `gemini-proxy`) follow the same tri-state and print a one-line decision note.
- macOS `launch.sh -q` (used by the `.command` launchers): validates config, hands off to a detached `--worker` process and exits immediately, so double-clicking closes the terminal window at once instead of pinning it for up to ~2 min. The worker performs the old-instance kill, injection, launch and white-screen recovery in the background, logging to `~/.config/proxy-switcher/launch.log` (256KB rotation) and reporting the outcome via macOS notifications (sound on failure). Menu [5]/[6] keeps the verbose foreground path.
- macOS menu: `[1]/[2]/[3]` now cycle 自动 → 强制代理 → 强制直连 (status line shows the current mode per tool); the old `[3]/[4]` off items are gone and `[7]/[8]` launch the CLI per the current mode instead of force-enabling proxy first. Windows menu unchanged.
- macOS `lib.zsh`: shared decision point `_psw_decide_injection` + `_psw_get_mode`/`_psw_set_mode`/`_psw_resolve_alive` helpers and `_psw_notify` (osascript, best effort).

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
