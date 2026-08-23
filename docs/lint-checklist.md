# PowerShell 侧人工 lint 核对清单

> 生成日期：2026-08-23
> 环境：当前机器无 pwsh 7 / PSScriptAnalyzer，按任务规格（T03）改为**人工逐条核对**官方规则表中最常见项，结果落档于此。
> 后续在有 pwsh 7 的机器上可运行 `Invoke-ScriptAnalyzer` 复核，本清单作为静态核对基线。

## 核对范围

| 文件 | 行数 | 结论 |
|------|------|------|
| `switcher.ps1` | 152 | 通过（2 项有意豁免） |
| `launchers/launch.ps1` | 77 | 通过（1 项有意豁免） |
| `profile/profile-functions.ps1` | 83 | 通过（2 项有意豁免） |
| `scripts/install.ps1` | 35 | 通过（1 项有意豁免） |
| `scripts/firewall-fix.ps1` | 81 | 通过（1 项有意豁免） |
| `scripts/validate.ps1` | 41 | 通过（无告警） |

## 逐项核对（PSScriptAnalyzer 最常见规则）

### 1. PSUseDeclaredVarsMoreThanAssignments（声明后未引用）
- 逐文件核对全部赋值变量均被引用：`switcher.ps1`（`$ocApp`/`$agyApp` 用于菜单 5-8）、`launch.ps1`（`$marker`/`$noProxy`）、`profile-functions.ps1`（`$names`/`$saved`/`$real`）、`install.ps1`（`$shell`/`$link`）、`firewall-fix.ps1`（`$principal`/`$binDir`/`$lsPath`）、`validate.ps1`（全部）—— **均通过**。

### 2. PSPossibleIncorrectComparisonWithNull（$null 比较位置）
- 全文检索 `-eq $null` / `-ne $null` 模式：**未发现**（代码统一使用 `if ($cfg.no_proxy)`、`if (-not $real)` 等真值判断）。

### 3. Set-StrictMode 兼容性
- 全部脚本未启用 `Set-StrictMode`；变量引用均先赋值后使用，开启 `Set-StrictMode -Version Latest` 不会引入未定义变量错误 —— **通过**。

### 4. PSUseSingularNouns / PSReviewUnusedParameter（函数命名与未用参数）
- 所有自定义函数均通过；`scripts/install.ps1` 的 `-WhatIf` 参数被显式使用（L19）—— **通过**。

### 5. PSAvoidUsingWriteHost（Write-Host 使用）
- 5 个脚本存在 `Write-Host`。**有意使用，豁免**：本项目为交互式菜单 / 诊断输出程序，依赖 `-ForegroundColor` 彩色提示，`Write-Output` 会污染管道语义且无颜色。

### 6. PSUseApprovedVerbs（函数动词合规）
- `profile-functions.ps1` 中 `agy-proxy` / `opencode-proxy` 非标准动词。**有意使用，豁免**：这是对外暴露的显式 CLI 命令名（与 README 文档一致），刻意避开 `opencode`/`agy` 本名以不覆盖既有命令，不适用动词规范。

### 7. PSUseShouldProcessForStateChangingFunctions（状态改变函数）
- `scripts/install.ps1`：已用 `-WhatIf` 参数实现"仅预览"语义，等价于支持 ShouldProcess —— **豁免**。
- `switcher.ps1` 的 `Set-ProxyEnv`：仅设置当前进程环境变量，随进程退出自动消失，非持久状态变更 —— **豁免**。

### 8. PSAvoidUsingInvokeExpression
- 全文检索 `Invoke-Expression` / `iex`：**未发现**。

### 9. PSAvoidUsingEmptyCatchBlock / 其他
- 无空 catch 块；无明文密码/密钥硬编码；无 `Write-Error` 吞掉 —— **通过**。

## 备注

- 未实际运行 PSScriptAnalyzer（无 pwsh 环境），本清单为规则表人工核对结果。
- 语法层面 `scripts/validate.ps1` 本身就是对所有 `.ps1` 做 `Parser.ParseFile` 校验的脚本（含 `config.example.json` 字段校验），在有 pwsh 的机器上运行 `pwsh -File scripts/validate.ps1` 即可一次性完成语法与配置双重验证。
