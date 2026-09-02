# proxy-switcher

> 按工具注入进程环境变量，修复 Antigravity / OpenCode 桌面端在代理下白屏，且不污染全局环境。
> Injects per-tool process environment variables to fix Antigravity / OpenCode desktop white-screen behind a proxy, without touching global env.
>
> 为 AI 编程工具（opencode / Antigravity）提供**按工具独立**的代理开关，不污染全局环境变量。
> Per-tool proxy toggle for AI coding tools — with zero global-env pollution.
>
> 跨平台：**Windows**（PowerShell 7） + **macOS**（zsh 零依赖）

## 一行命令安装 / One-line install

**macOS**（zsh 零依赖，唯一前置：本地代理客户端已运行）：

```bash
curl -fsSL https://raw.githubusercontent.com/YangZiLei/proxy-switcher/main/install.sh | sh
# 想同时获得 CLI 注入函数（opencode-proxy / agy-proxy），加 --with-zshrc：
curl -fsSL https://raw.githubusercontent.com/YangZiLei/proxy-switcher/main/install.sh | sh -s -- --with-zshrc
```

**Windows**（PowerShell 7；须从仓库检出，不支持 `curl | sh`）：

```powershell
git clone https://github.com/YangZiLei/proxy-switcher.git
cd proxy-switcher
pwsh -File scripts/install.ps1   # 若无 config.json 则从 example 生成（桌面路径展开为 %LOCALAPPDATA%），并创建开始菜单快捷方式
```

> Windows 侧必须用 `git clone` 获取仓库——安装器生成的快捷方式指向仓库内脚本，`curl | sh` 式一行安装不适用于 Windows（macOS 侧可，因其会自动浅克隆）。需要 PowerShell 7（`pwsh`），与 `switcher.bat` 相同。安装器幂等，重复执行安全；fork 部署时可用 `PROXY_SWITCHER_REPO_URL` 环境变量覆盖默认克隆地址。

## 为什么需要按工具注入 / Why per-tool injection

现有方案都不解决"桌面端 Electron AI 工具 + 代理"这个组合问题：

| 方案 | 问题 |
|------|------|
| 开启 TUN（虚拟网卡） | 接管**所有**流量，时好时坏，且栈模式（gvisor/system/mixed）行为不稳定 |
| 全局环境变量 `HTTPS_PROXY` | 影响 curl / git / npm / 所有程序，无法按工具区分 |
| FastLink 等"系统代理"开关 | 只影响认系统代理的程序（Chromium 系），且同样全局生效 |
| `--proxy-server` 参数启动 Electron | **会劫持应用本地回环请求**（Antigravity 的 UI 是 `https://127.0.0.1:<port>` 本地页面），直接白屏 |

而 AI 工具们本身又各有各的脾气：

- **opencode**：桌面端核心流量走内置 Node 服务（认 `HTTPS_PROXY` 环境变量）；终端 CLI 也是 Node 进程
- **Antigravity (agy)**：桌面端是 Electron；真正访问 Google API 的是它 spawn 的 `language_server`（Go 进程，**认环境变量**）。Electron UI 只加载本地页面 `https://127.0.0.1:<port>`（端口动态）

所以正确的控制面不是"代理软件怎么配"，而是**在启动每个工具时，按需注入环境变量**。

## 设计思路 / Design

核心是一个很简单的机制：**标记文件（marker file）+ 启动器读取**。

```
┌─────────────────┐   写/删标记    ┌──────────────────────┐
│  switcher (菜单) │ ───────────▶  │ $HOME\.opencode-proxy-on  │
│                 │               │ $HOME\.agy-proxy-on       │
└─────────────────┘               └──────────────────────┘
                                            │ 启动时读取
                                            ▼
                                  ┌──────────────────────┐
                                  │ 启动器 (launcher)     │
                                  │ 有标记 → 注入代理环境  │
                                  │ 无标记 → 原样启动      │
                                  └──────────────────────┘
```

- **不写全局环境变量**：开关只影响 opencode / antigravity 两个工具，curl、git、npm、浏览器完全不受影响
- **标记文件在用户主目录**：任何目录下都生效，不污染项目仓库
- **只影响新进程**：已打开的终端需重启才生效；**桌面端**由启动器在检测到已运行实例时先退出再拉起，使当前标记生效（进程环境变量机制使然）
- **统一注入 `NO_PROXY=127.0.0.1,localhost`**：`HTTPS_PROXY` 注入后必须豁免回环，否则 Electron UI 加载本地页面也会走代理 → 白屏（详见下方"白屏"章节）。默认值如左；两个平台的 `config.json` 都可用 `no_proxy` 键覆盖（缺省时回落到 `127.0.0.1,localhost`）
- **代理变量集合**：标记开启时注入 `HTTPS_PROXY` / `HTTP_PROXY` / `ALL_PROXY` / `NO_PROXY` / `no_proxy`（Windows 与 macOS 相同）
- **CLI 注入只作用于子进程**：`opencode-proxy` / `agy-proxy` 用临时环境前缀（zsh）/ try+finally 清理（PowerShell）注入，命令退出后当前终端不会残留代理变量

## 平台差异 / Platform differences

两个平台的关键机制相同（marker + 注入），但**桌面端启动方式**和**白屏根因**完全不同：

| 维度 | Windows | macOS |
|------|---------|-------|
| 运行时 | PowerShell 7（`pwsh`）+ `.bat` | zsh 脚本（零依赖，无需安装任何东西） |
| 菜单入口 | `switcher.bat`（双击） | `macos/install.sh` 生成 `代理切换.app`（双击；自动选 Ghostty / iTerm / Kitty / Terminal.app） |
| CLI 注入 | `profile/profile-functions.ps1` → `opencode-proxy`/`agy-proxy`（CLI 路径来自 `config.json` / PATH） | `macos/profile.zsh` → `opencode-proxy`/`agy-proxy` |
| 桌面端启动 | `Start-Process`（子进程继承环境变量）；菜单 [5]/[6] 调用 `launchers/launch.ps1`，**按标记**注入（不强制开标记） | 直接 exec bundle 内二进制（`open -a` 不传 env），注入后 spawn 的 `language_server` 继承 |
| 单实例 | 启动器按桌面 exe 路径找主进程（排除 `--type=` 的 Helper），退出并等待后再拉起 | 按 argv[0] 精确匹配主进程，退出并等待（最长 12s + SIGKILL）后再拉起 |
| 白屏根因 | 代理未就绪时 Chromium 把本地页面也走代理 + 防火墙拦回环 | **language_server 启动要 ~37s**，Electron 过早加载本地页 30s 超时定格 |
| 白屏修复 | 注入 `NO_PROXY` 豁免回环 + `scripts/firewall-fix.ps1` 防火墙放行 | `--no-proxy-server` + 启动器经 CDP 自动重载窗口（`recoverWhiteScreen`；缺 Node 时提示并跳过） |

---

## Windows 安装与使用

1. **安装**：`pwsh -File scripts/install.ps1`。若仓库里还没有 `config.json`，会从 `config.example.json` 复制并展开 `%LOCALAPPDATA%` 桌面路径；按需改 `proxy.url`。然后创建开始菜单快捷方式。
2. **启动菜单**：双击 `switcher.bat`（或 `pwsh -File switcher.ps1`）。依赖 PowerShell 7。macOS 主菜单排版与数字相同。

   ```powershell
   pwsh --version
   ```

   ```
   ── opencode ──────────────────────
   [1] 开启 代理 (CLI + 桌面)
   [3] 关闭 代理 (直连)
   [5] 启动 桌面端 (按标记注入代理)
   [7] 开启代理并启动 CLI (本窗口)

   ── Antigravity ───────────────────
   [2] 开启 代理 (CLI + 桌面)
   [4] 关闭 代理 (直连)
   [6] 启动 桌面端 (按标记注入代理)
   [8] 开启代理并启动 CLI (本窗口)

   [9] 退出
   ```

   数字与旧版相同（奇数 opencode、偶数 Antigravity）。[1]–[4] 只切换标记。[5]/[6] **不改标记**，交给启动器：有标记则注入代理（含 `ALL_PROXY`），无标记则直连启动；若应用已在运行则先退出再拉起。[7]/[8] **会先开标记**再在本窗口跑 CLI，退出后恢复环境。

3. **（推荐）把桌面端快捷方式指向启动器**：开始菜单 `OpenCode.lnk` / `Antigravity.lnk` → 目标改为 `launchers/xxx-launch.bat`（应用更新有时会重置快捷方式，需重新指向）
4. **（可选）装 profile 函数**：把 `profile/profile-functions.ps1` dot-source 进 PowerShell profile，使用独立命令 `opencode-proxy` / `agy-proxy`，不覆盖你已有的 `opencode`/`agy`

### Windows 白屏排查

```
electron: Failed to load URL: https://127.0.0.1:<port>/ with error: ERR_CONNECTION_TIMED_OUT
```

**根因（已修复）**：注入 `HTTPS_PROXY` 时未豁免 localhost → Chromium 用代理加载本地 UI 页面，代理未就绪即超时白屏。`launchers/launch.ps1` 已在注入时设置 `NO_PROXY=127.0.0.1,localhost`。

**仍建议运行一次防火墙规则（双重保障）**：Windows 防火墙默认可能拦截回环入站，导致同样症状。以管理员运行 `scripts/firewall-fix.ps1`（仅为 Antigravity.exe / language_server.exe 创建回环入站和应用出站规则；不修改防火墙总开关）。规则持久，无需每次重跑。

---

## macOS 安装与使用

零依赖（zsh + python3 + curl，均为 macOS/Xcode CLT 自带）。**白屏自动恢复需要 Node ≥ 21**（用于 CDP 重载；Xcode CLT 不带 node，若缺失或版本过低，启动器会提示并优雅降级为手动 `Cmd+R`）。**首次只需一条命令**：

```bash
cd macos
./install.sh --with-zshrc     # --with-zshrc 可选：把 opencode-proxy/agy-proxy 挂进 ~/.zshrc
```

`install.sh` 会：
1. 复制 `switcher.sh` / `launch.sh` / `profile.zsh` / `lib.zsh` / `open-menu.sh` 到 `~/.config/proxy-switcher/`
2. 生成 `config.json`（首次，按需改代理地址；默认 `http://127.0.0.1:7892`）
3. 生成三个带图标的双击启动器到 `~/Applications/`：
   - **代理切换.app**（自动选择 Ghostty / iTerm / Kitty / Terminal.app 打开主菜单）
   - **OpenCode 代理启动.app**
   - **Antigravity 代理启动.app**
4. （可选）把 `profile.zsh` 追加进 `~/.zshrc`

> 菜单应用按顺序检测终端，也可用环境变量 `PROXY_SWITCHER_TERMINAL` 覆盖（可执行文件路径，或传给 `open -na` 的应用名）。找不到终端时会弹出对话框，提示自行运行 `~/.config/proxy-switcher/switcher.sh`。桌面启动器若 `launch.sh` 失败也会弹出对话框，而不是静默失败。

### 使用

| 场景 | 操作 |
|------|------|
| 开关代理 | 双击 `代理切换.app`（或 `~/.config/proxy-switcher/switcher.sh`）；菜单与 Windows 相同：奇数 opencode、偶数 Antigravity，`[1]/[2]` 开、`[3]/[4]` 关 |
| Antigravity CLI | 新终端 `agy-proxy ...` |
| opencode CLI | 新终端 `opencode-proxy ...` |
| Antigravity 桌面端 | 双击 `Antigravity 代理启动.app`（自动注入 + 白屏恢复） |
| OpenCode 桌面端 | 双击 `OpenCode 代理启动.app` |

### macOS 白屏（重点）

```
electron: Failed to load URL: https://127.0.0.1:<port>/ with error: ERR_TIMED_OUT
```

**根因与 Windows 不同**：不是代理/防火墙，而是 **language_server 启动太慢**（日志显示 `initialized server successfully in ~37s`，启动时含 playwright 驱动下载 404 重试、网络初始化）。Electron 在 LS 就绪前就加载本地页 → 30s 超时 → 白屏定格（无自动重试）。实测 LS 就绪后 `curl -k https://127.0.0.1:<port>/` 返回 200，CDP 重载一次即恢复。

**解决（已内置于 `launch.sh`）**：
1. `apps.antigravity.chromiumArgs = "--no-proxy-server"`：让 Chromium 强制直连，规避系统 PAC（如失效的 `http://wpad/wpad.dat`）劫持回环代理解析；API 流量仍由 language_server（Go）走 `HTTPS_PROXY`
2. `apps.antigravity.recoverWhiteScreen = true`：启动后轮询 LS 直到 HTTPS 200，再经 CDP（remote-debugging-port）重载主窗口，直到窗口标题变成真实 app

**其他要点**（均已在 `launch.sh` 处理）：
- macOS `open -a` 不传递环境变量 → 必须直接 exec bundle 内二进制
- Electron 单实例锁：二次启动 env 会被转发给旧实例后退出 → 启动器先**彻底杀掉旧实例**（等旧进程完全消失再拉起，最长 12s + SIGKILL），**标记关闭时同样重启**，以免旧实例仍带着代理环境
- 进程检测：macOS GUI app 的 comm 被截断成 16 字符 → 用 `ps -axo args=` 按 argv[0] 精确匹配主进程，不误伤 Helper
- 直接用 `--no-proxy-server` 启动的 Antigravity 桌面端，其 UI 与 language_server 不受影响

**白屏仍在？**：等 LS 就绪后按 `Cmd+R` 手动重载；或确认代理客户端端口与 `config.json` 的 `proxy.url` 一致。

> **单实例说明**：Electron 是单实例——同一应用二次启动会把请求转发给旧进程后退出。Windows 与 macOS 启动器都会在应用已运行时先退出旧实例再按当前标记拉起，所以切换代理开关后再次启动即生效。

---

## 目录结构

```
proxy-switcher/
├── install.sh                     # 顶层一键安装器（检测平台 → 调平台安装器 → 打印验证方式）
├── switcher.bat / switcher.ps1     # Windows 菜单（pwsh）
├── config.example.json             # Windows 配置模板（%LOCALAPPDATA% 占位，安装时展开）
├── launchers/                      # Windows 桌面启动器
├── scripts/
│   ├── ProxySwitcher.ps1           # Windows 共用：读配置 / 注入 / 恢复环境
│   ├── install.ps1                 # 生成 config.json + 开始菜单快捷方式
│   ├── firewall-fix.ps1
│   └── validate.ps1
├── profile/
│   └── profile-functions.ps1       # Windows CLI 注入函数（opencode-proxy / agy-proxy）
├── macos/
│   ├── install.sh                  # macOS 一键安装（生成 .app + 图标）
│   ├── lib.zsh                     # macOS 共用：读配置 / 按标记注入
│   ├── switcher.sh                 # macOS 主菜单（zsh）
│   ├── launch.sh                   # macOS 桌面启动器（注入 + 白屏恢复）
│   ├── open-menu.sh                # 菜单 .app：检测终端并打开 switcher.sh
│   ├── profile.zsh                 # macOS CLI 注入函数
│   └── config.example.json         # macOS 配置模板
├── .github/
│   ├── workflows/ci.yml
│   └── ISSUE_TEMPLATE/bug.yml
├── docs/
│   └── lint-checklist.md           # PowerShell 侧人工 lint 核对清单（无 pwsh 环境时）
├── CONTRIBUTING.md
├── CHANGELOG.md
└── README.md
```

## Legal & Disclaimer

- This is an independent developer utility, **not affiliated with or endorsed by** opencode, Antigravity/Google, FastLink, Clash, v2rayN, or any other vendor. Product names appear nominatively for interoperability identification only; no official logos are used.
- **No proxy service included**: this repository ships no servers, nodes, subscriptions, accounts, or credentials. It only writes local marker files and sets process-scoped environment variables pointing at a proxy you already run yourself.
- You are solely responsible for using this tool in compliance with applicable local laws and regulations and with the terms of service of any services you access.
- Provided "AS IS", without warranty of any kind (see the MIT License below).

## License

MIT
