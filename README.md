# proxy-switcher

> 为 AI 编程工具（opencode / Antigravity CLI）提供**按工具独立**的代理开关，不污染全局环境变量。

## 缘由（为什么需要它）

使用国外模型服务时，经常遇到 403 地域封锁（`This model is not available in your region`），需要用代理访问。常见的解决方案各有痛点：

| 方案 | 问题 |
|------|------|
| 开启 TUN（虚拟网卡） | 接管**所有**流量，时好时坏，且栈模式（gvisor/system/mixed）行为不稳定 |
| 全局环境变量 `HTTPS_PROXY` | 影响 curl / git / npm / 所有程序，无法按工具区分 |
| FastLink 等"系统代理"开关 | 只影响认系统代理的程序（Chromium 系），且同样全局生效 |
| `--proxy-server` 参数启动 Electron | **会劫持应用本地回环请求**（Antigravity 的 UI 是 `https://127.0.0.1:<port>` 本地页面），直接白屏 |

而 AI 工具们本身又各有各的脾气：

- **opencode**：桌面端核心流量走内置 Node 服务（认 `HTTPS_PROXY` 环境变量）；终端 CLI 也是 Node 进程
- **Antigravity (agy)**：桌面端是 Electron（Chromium 网络栈**会读取 `HTTPS_PROXY` 环境变量**，因此本地 UI 页面也会走代理）；真正访问 Google API 的是它 spawn 的 `language_server.exe`（Go 进程，**认环境变量**）。所以注入代理时必须用 `NO_PROXY=127.0.0.1,localhost` 把本地页面排除在外——否则 UI 加载本地 `https://127.0.0.1:<port>` 时也会走代理，代理未就绪即白屏。

所以正确的控制面不是"代理软件怎么配"，而是**在启动每个工具时，按需注入环境变量**。

## 设计思路

核心是一个很简单的机制：**标记文件（marker file）+ 启动器读取**。

```
┌─────────────────┐   写/删标记    ┌──────────────────────┐
│  switcher.ps1   │ ───────────▶  │ %USERPROFILE%\.opencode-proxy-on  │
│  (菜单工具)      │               │ %USERPROFILE%\.agy-proxy-on       │
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
- **标记文件在 `%USERPROFILE%`**：任何用户目录下都生效，不污染项目仓库
- **只影响新进程**：已打开的终端/应用需重启才生效（进程环境变量机制使然，这也是预期行为）
- **Electron 桌面端特殊处理**：Antigravity 桌面端**不能**加 `--proxy-server`（会白屏，见上表）；注入 `HTTPS_PROXY` 让 `language_server.exe` 走代理的同时，必须额外注入 `NO_PROXY=127.0.0.1,localhost`，确保 UI 本地页面（`<port>` 为动态端口）直连、不被代理劫持。仅注入 `HTTPS_PROXY` 而漏掉 `NO_PROXY` 同样会导致白屏（代理未就绪时本地页请求超时）

### 启动器矩阵

| 工具 | 桌面端 | 终端 |
|------|--------|------|
| opencode | `launchers/opencode-launch.bat` → `launch.ps1 -App opencode -Mode desktop` | `switcher.ps1` 选项 6 / profile 函数 |
| antigravity | `launchers/antigravity-launch.bat` → `launch.ps1 -App antigravity -Mode desktop` | `switcher.ps1` 选项 8 / profile 函数 |

（可选）将 `profile/profile-functions.ps1` dot-source 进 PowerShell profile 后，终端使用独立命令 `opencode-proxy` / `agy-proxy` 按标记走代理，不会覆盖你已有的 `opencode`、`agy` 函数或插件。

## 安装与使用

1. **复制配置**：`config.example.json` → `config.json`，按注释填写代理地址和各工具的安装路径
2. **启动菜单**：双击 `switcher.bat`（或 `pwsh -File switcher.ps1`）。项目依赖 PowerShell 7（命令为 `pwsh`）：

   ```powershell
   pwsh --version
   ```

   如果系统没有 `pwsh`，请先安装 PowerShell 7。

   ```
   [1] Enable  proxy for opencode (CLI + Desktop)
   [2] Enable  proxy for antigravity (CLI + Desktop)
   [3] Disable proxy for opencode (direct)
   [4] Disable proxy for antigravity (direct)
   [5] Enable & launch opencode Desktop
   [6] Enable & launch opencode CLI (this window)
   [7] Enable & launch Antigravity Desktop
   [8] Enable & launch Antigravity CLI (this window)
   [9] Exit
   ```

3. **（推荐）把桌面端快捷方式指向启动器**，这样双击图标也会自动读标记：
   - 开始菜单 `OpenCode.lnk` / `Antigravity.lnk` → 目标改为 `launchers/xxx-launch.bat`
   - 注意：应用更新有时会重置快捷方式，需重新指向
4. **（可选）装 profile 函数**：见 `profile/profile-functions.ps1` 头部说明。使用独立命令：

   ```powershell
   opencode-proxy --version
   agy-proxy --version
   ```

   这两个函数只在当前 PowerShell 会话注入代理环境，不会修改用户级环境变量，也不会覆盖原始命令。

5. **（可选）创建快捷方式**：先配置 `config.json`，再运行：

   ```powershell
   pwsh -File scripts/install.ps1
   ```

   快捷方式会创建到开始菜单的 `proxy-switcher` 文件夹。此脚本不修改防火墙。

## 故障排查

### Antigravity 桌面端白屏 / `ERR_CONNECTION_TIMED_OUT`

```
(node:xxxx) electron: Failed to load URL: https://127.0.0.1:<port>/ with error: ERR_CONNECTION_TIMED_OUT
```

**根因（已修复）**：启动器注入 `HTTPS_PROXY` 时若未豁免 localhost，Chromium 会用该代理加载本地 UI 页面 `https://127.0.0.1:<port>`。代理未就绪（`127.0.0.1:7892` 未监听 / 刚启动）时，这条本地请求超时 → 白屏。`launch.ps1` 现已在注入代理的同时设置 `NO_PROXY=127.0.0.1,localhost`，本地页面强制直连，从根上消除此问题。

**仍建议运行一次防火墙规则（双重保障）**：Windows 防火墙默认可能拦截回环入站，导致同样症状。以管理员身份运行一次即可（规则持久，无需每次重跑）：

1. 以管理员身份运行 `scripts/firewall-fix.ps1`（仅为 Antigravity.exe / language_server.exe 创建回环入站和应用出站规则）
2. 按需在 Windows 防火墙中开启对应网络配置文件；脚本不会修改防火墙总开关
3. 不要长期关闭防火墙

**排查顺序**：先确认代理是否开着（`Test-NetConnection 127.0.0.1 7892`）；开着仍白屏时再检查防火墙规则是否仍在（`Get-NetFirewallRule -DisplayName "proxy-switcher*"`）。

### 终端里 token exchange failed / 直连超时

说明进程没拿到代理环境变量：
- 确认对应工具的标记已开启（菜单 `[1]`/`[2]`）
- **新开终端**再运行（已开终端不继承）
- 若用了 profile 函数，确认 `config.json` 存在且路径正确

## 目录结构

```
proxy-switcher/
├── switcher.bat            # 菜单入口（双击）
├── switcher.ps1            # 主菜单（读 config.json）
├── config.example.json     # 配置模板（复制为 config.json）
├── config.json             # 你的配置（gitignore）
├── launchers/
│   ├── launch.ps1          # 统一启动器（读标记 → 注入环境 → 启动）
│   ├── opencode-launch.bat
│   └── antigravity-launch.bat
├── scripts/
│   ├── firewall-fix.ps1    # 回环防火墙规则（需管理员）
│   ├── install.ps1         # 创建开始菜单快捷方式
│   └── validate.ps1        # 配置和脚本语法检查
├── profile/
│   └── profile-functions.ps1  # 可选：opencode/agy 自动读标记函数
└── README.md
```

## License

MIT
